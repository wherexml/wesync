#!/usr/bin/env python3
"""Read-only capability check. Never prints subprocess output or credentials."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


APP_CLI = "/Applications/we-sync.app/Contents/MacOS/greenbubbles"


def probe(binary, args):
    try:
        result = subprocess.run([binary, *args], stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=30)
        return result.returncode, result.stdout
    except (OSError, subprocess.TimeoutExpired):
        return None, ""


def check(binary=None, profile=None):
    resolved = shutil.which(binary or "greenbubbles")
    if not resolved and binary is None:
        resolved = shutil.which(APP_CLI)
    if not resolved:
        return {"ok": False, "checks": {"cli": "missing"},
                "next": "Install we-sync or select an existing Rust CLI with --greenbubbles."}
    code, output = probe(resolved, ["messages", "list", "--help"])
    compatible = code == 0 and all(option in output for option in (
        "--conversation", "--since", "--until", "--json", "--query-stdin"))
    checks = {"cli": "compatible" if compatible else "unsupported-query-cli"}
    if compatible:
        # A named profile is optional. The live default is a bounded source
        # status with no profile, source path, or passphrase argument.
        source_args = ["source", "status", "--profile", profile] if profile else ["source", "status"]
        code, output = probe(resolved, source_args)
        try:
            payload = json.loads(output)
            valid = code == 0 and payload.get("ok") is True and payload.get("schema") == "greenbubbles.query.v1"
        except (ValueError, AttributeError):
            valid = False
        checks["source"] = "ready" if valid else "live-source-unavailable"
    ready = compatible and checks.get("source") == "ready"
    if ready:
        next_step = "The existing connection works. Continue with we-search."
    elif compatible:
        next_step = "Check existing source selection, credentials and access in references/setup.md."
    else:
        next_step = "Select a compatible Rust CLI. The source was not opened."
    return {"ok": ready, "binary": str(Path(resolved).resolve()), "checks": checks,
            "next": next_step}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--greenbubbles", default=os.environ.get("GREENBUBBLES_CLI") or None)
    parser.add_argument("--profile")
    args = parser.parse_args()
    result = check(args.greenbubbles, args.profile)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
