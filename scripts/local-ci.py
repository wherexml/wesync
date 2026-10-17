#!/usr/bin/env python3
"""Run the repository checks on macOS; retain local logs and a JSON result.

See docs/LOCAL_CI.md. This runs synthetic fixtures and the existing test suites,
not installed-app acceptance. Never include real chat data in these checks.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CHECKS = json.loads(r'''[
  {
    "name": "Verify pinned audit tools",
    "cwd": ".",
    "command": "test \"$(cargo audit --version | awk '{print $NF}')\" = '0.22.2'\ntest \"$(cargo about --version | awk '{print $NF}')\" = '0.9.2'"
  },
  {
    "name": "Show Swift version",
    "cwd": ".",
    "command": "swift --version"
  },
  {
    "name": "Check formatting",
    "cwd": ".",
    "command": "swift format lint --strict --recursive Package.swift Sources Tests"
  },
  {
    "name": "Run tests",
    "cwd": ".",
    "command": "swift test"
  },
  {
    "name": "Verify text emoji and bounded local stickers end to end",
    "cwd": ".",
    "command": "scripts/sticker-acceptance/local-e2e.sh\ncat docs/acceptance/emoji-fix-20261002/synthetic.json"
  },
  {
    "name": "Build release executable",
    "cwd": ".",
    "command": "swift build -c release"
  },
  {
    "name": "Check distribution dependency baseline",
    "cwd": ".",
    "command": "swift scripts/check-distribution-inventory.swift"
  },
  {
    "name": "Check secret hygiene",
    "cwd": ".",
    "command": "swift scripts/check-secret-hygiene.swift"
  },
  {
    "name": "Check cross-language pinned build profile",
    "cwd": ".",
    "command": "swift scripts/check-pinned-build-profile.swift"
  },
  {
    "name": "Test the personal-memory driver",
    "cwd": ".",
    "command": "python3 -m unittest discover -s scripts -p 'test_*.py' -v"
  },
  {
    "name": "Check Homebrew formula syntax",
    "cwd": ".",
    "command": "ruby -c Formula/greenbubbles.rb"
  },
  {
    "name": "Check packaging manifests",
    "cwd": ".",
    "command": "bash -n scripts/package-send-helper.sh\nbash -n scripts/check-public-release.sh\npython3 -m py_compile scripts/personal-memory-parallel.py\nbash scripts/check-public-release.sh\nplutil -lint Packaging/GreenBubbles/Info.plist\nplutil -lint Packaging/GreenBubblesInputHelper/Info.plist\nplutil -lint Packaging/GreenBubblesInputHelper/me.greenbubbles.InputHelper.plist\nplutil -lint Packaging/GreenBubbles.entitlements\nplutil -lint Packaging/GreenBubblesInputHelper.entitlements"
  },
  {
    "name": "Check the release helper contains no diagnostic bypass",
    "cwd": ".",
    "command": "# These subcommands drive input and read screen content without a\n# capability, an approval, the outbox, the audit journal, or the XPC\n# peer check. In a binary holding Accessibility and Screen Recording\n# they would be an unauthenticated bypass of the whole architecture.\nswift build -c release --product greenbubbles-input-helper\n# Greps for a usage string that exists only inside the debug block.\n# Checking for subcommand names is unreliable: words like \"capture\"\n# and \"windows\" occur in framework strings.\nif strings .build/release/greenbubbles-input-helper |\n  grep -q 'focus-probe --profile'; then\n  echo \"error: the release helper contains the debug diagnostics\" >&2\n  exit 1\nfi\necho \"release helper contains no diagnostic bypass\""
  },
  {
    "name": "Check the send path ships closed",
    "cwd": ".",
    "command": "# A build with no pinned release verifying key must refuse every\n# release-signed calibration profile, so the send path cannot leave\n# the dry-run stage by default.\nif grep -q 'generatedReleasePublicKeys: \\[String\\] = \\[\\]' \\\n  Sources/GreenBubblesSendKit/SendReleaseTrust.swift; then\n  echo \"release trust root is empty by default\"\nelse\n  echo \"error: a release verifying key is committed to the repository\" >&2\n  exit 1\nfi"
  },
  {
    "name": "Show Rust version",
    "cwd": ".",
    "command": "rustc --version && cargo --version"
  },
  {
    "name": "Audit Rust dependencies",
    "cwd": "Native/GreenBubbles",
    "command": "cargo audit --file Cargo.lock"
  },
  {
    "name": "Reproduce the third-party notice bundle",
    "cwd": "Native/GreenBubbles",
    "command": "cargo about generate --locked --fail \\\n  -o \"$RUNNER_TEMP/THIRD_PARTY_NOTICES.md\" about.hbs\ndiff -u ../../THIRD_PARTY_NOTICES.md \"$RUNNER_TEMP/THIRD_PARTY_NOTICES.md\""
  },
  {
    "name": "Check Rust formatting",
    "cwd": "Native/GreenBubbles",
    "command": "cargo fmt --check"
  },
  {
    "name": "Lint restoration engine",
    "cwd": "Native/GreenBubbles",
    "command": "cargo clippy --locked --all-targets -- -D warnings"
  },
  {
    "name": "Run restoration-engine tests",
    "cwd": "Native/GreenBubbles",
    "command": "cargo test --locked --all-targets"
  },
  {
    "name": "Verify exact-message sticker metadata end to end",
    "cwd": ".",
    "command": "cargo build --locked --manifest-path Native/GreenBubbles/Cargo.toml\npython3 scripts/sticker-acceptance/metadata-e2e.py Native/GreenBubbles/target/debug/greenbubbles docs/acceptance/emoji-fix-20261002/metadata.json\ncat docs/acceptance/emoji-fix-20261002/metadata.json"
  },
  {
    "name": "Verify AI read blacklist end to end",
    "cwd": ".",
    "command": "python3 scripts/verify-ai-read-blacklist.py Native/GreenBubbles/target/debug/greenbubbles\ncat docs/acceptance/ai-read-blacklist/cli-e2e.json"
  },
  {
    "name": "Check the cross-language send vectors are current",
    "cwd": "Native/GreenBubbles",
    "command": "cargo run --locked --quiet --example send_canonical_vectors \\\n  >\"$RUNNER_TEMP/send-canonical-vectors.json\"\ndiff -u ../../docs/send-canonical-vectors.json \"$RUNNER_TEMP/send-canonical-vectors.json\""
  }
]''')


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def source_digest():
    digest = hashlib.sha256()
    names = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    for name in sorted(set(names.split(b"\0")) - {b""}):
        path = ROOT / os.fsdecode(name)
        digest.update(name + b"\0")
        if path.is_symlink():
            digest.update(os.fsencode(os.readlink(path)))
        elif path.is_file():
            digest.update(path.read_bytes())
        else:
            digest.update(b"<missing>")
        digest.update(b"\0")
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="List checks without running them")
    args = parser.parse_args()
    if args.list:
        for index, check in enumerate(CHECKS, 1):
            print(f"{index:02d}. {check['name']} ({check['cwd']})\n{check['command']}\n")
        return 0
    if sys.platform != "darwin":
        parser.error("These checks require macOS 14 or later")

    if sys.version_info < (3, 11):
        for name in ("python3.12", "python3.13", "python3.14", "python3.11"):
            candidate = shutil.which(name)
            if candidate:
                version = subprocess.run(
                    [candidate, "-c", "import sys; sys.exit(sys.version_info < (3, 11))"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                if version.returncode == 0:
                    os.execv(candidate, [candidate, str(Path(__file__).resolve()), *sys.argv[1:]])
        parser.error("Python 3.11+ is required; install it before running local checks")

    started = datetime.now(timezone.utc)
    run_dir = ROOT / ".build/local-ci" / started.strftime("%Y%m%dT%H%M%S.%fZ")
    run_dir.mkdir(parents=True)
    temporary = run_dir / "tmp"
    temporary.mkdir()
    # Every nested `python3` command must use this same supported interpreter,
    # even when /usr/bin/python3 (3.9) appears first in the login shell PATH.
    runtime_bin = temporary / "bin"
    runtime_bin.mkdir()
    (runtime_bin / "python3").symlink_to(sys.executable)
    environment = dict(
        os.environ, RUNNER_TEMP=str(temporary),
        PATH=str(runtime_bin) + os.pathsep + os.environ.get("PATH", ""),
    )
    results = [dict(check, status="NOT_RUN") for check in CHECKS]
    report = {
        "startedAt": started.isoformat(),
        "pythonVersion": sys.version.split()[0],
        "sourceRevision": git("rev-parse", "HEAD").decode().strip(),
        "workingTreeChanged": bool(git("status", "--porcelain")),
        "sourceSHA256": source_digest(),
        "syntheticOnly": True,
        "installedAppAcceptance": "NOT_RUN",
        "status": "RUNNING",
        "checks": results,
    }
    summary = run_dir / "summary.json"

    def save():
        summary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")

    save()
    exit_code = 1
    try:
        for index, result in enumerate(results, 1):
            log_name = f"{index:02d}.log"
            result.update(status="RUNNING", log=log_name)
            save()
            print(f"[{index}/{len(results)}] {result['name']}", flush=True)
            tick = time.monotonic()
            with (run_dir / log_name).open("w") as log:
                process = subprocess.run(
                    ["/bin/bash", "-euo", "pipefail", "-c", result["command"]],
                    cwd=ROOT / result["cwd"], env=environment,
                    stdout=log, stderr=subprocess.STDOUT,
                )
            result.update(
                status="PASS" if process.returncode == 0 else "FAIL",
                exitCode=process.returncode,
                durationSeconds=round(time.monotonic() - tick, 2),
            )
            save()
            print(f"  {result['status']} ({result['durationSeconds']}s)", flush=True)
            if process.returncode != 0:
                break
        else:
            exit_code = 0
    except KeyboardInterrupt:
        report["interrupted"] = True
        exit_code = 130
    except OSError as error:
        report["error"] = str(error)
    finally:
        for result in results:
            if result["status"] == "RUNNING":
                result["status"] = "INTERRUPTED" if exit_code == 130 else "FAIL"
        report.update(
            status="PASS" if exit_code == 0 else "FAIL",
            completedAt=datetime.now(timezone.utc).isoformat(),
        )
        save()
        print(f"{report['status']}: {summary}", flush=True)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
