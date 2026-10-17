#!/usr/bin/env python3
"""Cross-version CLI acceptance using synthetic data only; no personal settings.

Failure cases: old/new snapshots must be readable in both directions using
recovery words and Argon2 passphrases; wrong protectors must fail; TOML settings
must retain output behavior and reject invalid/unknown fields. Only hashes and
check statuses are written to the artifact, never recovery words or passphrases.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--fixture-generator", type=Path, required=True)
    args = parser.parse_args()
    binaries = [args.baseline.resolve(), args.candidate.resolve()]
    checks = {}
    report = {"status": "RUNNING", "syntheticOnly": True,
              "privateDataRecorded": False, "checks": checks,
              "binarySHA256": [hashlib.sha256(p.read_bytes()).hexdigest() for p in binaries]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="wesync-dependency-e2e-") as directory:
            root = Path(directory)
            config = root / "config.toml"
            config.write_text('[output]\nformat = "json"\n')
            config.chmod(0o600)
            env = dict(os.environ, GREENBUBBLES_CONFIG_FILE=str(config),
                       GREENBUBBLES_QUERY_PROFILES_FILE=str(root / "absent-profiles.json"))
            source = root / "source"
            conversation = "wxid_dependency_fixture"
            source_key = os.urandom(32).hex() + "\n"
            subprocess.run([str(args.fixture_generator.resolve()), str(source)],
                           input=source_key, text=True, check=True, capture_output=True)

            def run(binary, arguments, stdin=None, success=True):
                result = subprocess.run([str(binary), *map(str, arguments)], input=stdin,
                                        capture_output=True, text=True, env=env, timeout=120)
                if (result.returncode == 0) != success:
                    if result.returncode:
                        # Failure responses contain no protector values. Keep the
                        # synthetic diagnostic local; artifact stays status-only.
                        print(result.stderr[:1000])
                        try:
                            print(json.loads(result.stdout).get("error", {}).get("code", ""))
                        except ValueError:
                            pass
                    raise RuntimeError("Synthetic command returned unexpected status: " +
                                       arguments[0] + " " + str(result.returncode))
                return result.stdout

            query = ["messages", "list", source, "--passphrase-stdin", "--conversation", conversation, "--limit", "1"]
            for index, binary in enumerate(binaries):
                response = json.loads(run(binary, query, source_key))
                assert len(response["items"]) == 1
                checks[f"binary-{index}-toml-json-output"] = "PASS"
                for label, contents in (("syntax", "[output"), ("unknown", "[output]\nunknown = true\n")):
                    config.write_text(contents)
                    run(binary, query, source_key, success=False)
                    checks[f"binary-{index}-toml-reject-{label}"] = "PASS"
                config.write_text('[output]\nformat = "json"\n')

            # Synthetic secret is random, kept in process memory and stdin only.
            passphrase = os.urandom(32).hex() + "\n"
            for index, writer in enumerate(binaries):
                reader = binaries[1 - index]
                kit = root / f"kit-{index}"
                wrong_kit = root / f"wrong-kit-{index}"
                snapshot = root / f"snapshot-{index}"
                run(writer, ["snapshot", "recovery-kit", "create", kit])
                run(reader, ["snapshot", "recovery-kit", "create", wrong_kit])
                run(writer, ["snapshot", "create", source, snapshot, "--source-passphrase-stdin",
                             "--snapshot-recovery-kit", kit, "--snapshot-passphrase-stdin"], source_key + passphrase)
                for mode, access, stdin in (
                    ("words", ["--snapshot-recovery-kit", kit], None),
                    ("passphrase", ["--snapshot-passphrase-stdin"], passphrase),
                ):
                    run(reader, ["snapshot", "verify", snapshot, *access], stdin)
                    data = json.loads(run(reader, ["messages", "list", snapshot, *access,
                                                   "--conversation", conversation, "--limit", "1", "--json"], stdin))
                    assert len(data["items"]) == 1
                    assert "synthetic dependency roundtrip" in json.dumps(data["items"])
                    checks[f"writer-{index}-reader-{1-index}-{mode}-verify-and-read"] = "PASS"
                run(reader, ["snapshot", "verify", snapshot, "--snapshot-passphrase-stdin"],
                    os.urandom(32).hex() + "\n", success=False)
                checks[f"writer-{index}-wrong-passphrase-rejected"] = "PASS"
                run(reader, ["snapshot", "verify", snapshot, "--snapshot-recovery-kit", wrong_kit], success=False)
                checks[f"writer-{index}-wrong-recovery-words-rejected"] = "PASS"
        report["status"] = "PASS"
    except Exception as error:
        report["status"] = "FAIL"
        report["failureType"] = type(error).__name__
        raise
    finally:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} synthetic cross-version checks; {args.report}")


if __name__ == "__main__":
    main()
