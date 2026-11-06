#!/usr/bin/env python3
"""Cross-version snapshot E2E with two lockfiles, isolated from host policy/data.

Both builds use the current Rust source: use only for dependency-only changes.
Failures: changed host policy, dependency preparation/build errors, incompatible
old/new snapshots, wrong protectors accepted, or missing report fail the run.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'wesync-rust-e2e:1.94.0-v1'
POLICY = Path(pwd.getpwuid(os.getuid()).pw_dir) / 'Library/Application Support/GreenBubbles/ai-read-policy.json'


def fingerprint():
    if not POLICY.exists():
        return None
    return [hashlib.sha256(POLICY.read_bytes()).hexdigest(), POLICY.stat().st_mode & 0o777]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline_lock', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    before = fingerprint()
    try:
        with tempfile.TemporaryDirectory(prefix='wesync-dependency-isolated-') as temp:
            source = Path(temp)
            crate = source / 'Native/GreenBubbles'
            crate.mkdir(parents=True)
            for name in ['Cargo.toml', 'Cargo.lock', 'src', 'examples']:
                origin = ROOT / 'Native/GreenBubbles' / name
                if origin.is_dir():
                    shutil.copytree(origin, crate / name)
                else:
                    shutil.copy2(origin, crate / name)
            shutil.copy2(args.baseline_lock, source / 'baseline.lock')
            shutil.copy2(ROOT / 'scripts/dependency-upgrade-e2e.py', source / 'compatibility.py')
            output = source / 'result'
            output.mkdir(mode=0o777)
            output.chmod(0o777)
            common = ['docker', 'run', '--rm', '--cap-drop=ALL', '--security-opt=no-new-privileges',
                      '--mount', f'type=bind,src={source},dst=/source,readonly',
                      '--mount', f'type=bind,src={output},dst=/result',
                      '--mount', 'type=volume,src=wesync-e2e-cargo,dst=/cargo',
                      '--mount', 'type=volume,src=wesync-dependency-target,dst=/target']
            subprocess.run(common + [IMAGE, 'bash', '-euc',
                'cp -R /source/. /work/; cargo fetch --locked; '
                'cp /work/baseline.lock Cargo.lock; cargo fetch --locked'], check=True)
            subprocess.run(common + ['--network=none', IMAGE, 'bash', '-euc',
                'cp -R /source/. /work/; cp Cargo.lock /work/candidate.lock; '
                'cp /work/baseline.lock Cargo.lock; cargo build --offline --locked; '
                'cp /target/debug/greenbubbles /work/baseline-greenbubbles; '
                'cp /work/candidate.lock Cargo.lock; cargo build --offline --locked; '
                'cargo build --offline --locked --example dependency_upgrade_fixture; '
                'python3 /work/compatibility.py /work/baseline-greenbubbles '
                '/target/debug/greenbubbles /result/compatibility.json '
                '--fixture-generator /target/debug/examples/dependency_upgrade_fixture'], check=True)
            report = json.loads((output / 'compatibility.json').read_text())
            report.update(platform='isolated local Linux container', testNetwork='none',
                          hostHomeMounted=False, hostPolicyUnchanged=before == fingerprint(),
                          buildScope='same current Rust source with baseline and candidate lockfiles')
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + '\n')
    finally:
        if before != fingerprint():
            raise RuntimeError('Host policy changed during compatibility E2E')


if __name__ == '__main__':
    main()
