#!/usr/bin/env python3
"""Run unchanged Rust E2E in an isolated OS account, never the user's policy."""
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
REPORT = ROOT / '.build/rust-e2e-isolated/result.json'

def fingerprint():
    if not POLICY.exists():
        return None
    return [hashlib.sha256(POLICY.read_bytes()).hexdigest(), POLICY.stat().st_mode & 0o777]

def run(args):
    subprocess.run(args, check=True)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--proxy-only', action='store_true')
args = parser.parse_args()
before = fingerprint()
passed = False
try:
    run(['docker', 'info', '--format', '{{.OSType}}/{{.Architecture}}'])
    run(['docker', 'build', '-t', IMAGE, str(ROOT / 'scripts/rust-e2e')])
    with tempfile.TemporaryDirectory(prefix='wesync-synthetic-e2e-') as temporary:
        source = Path(temporary)
        crate = source / 'Native/GreenBubbles'
        crate.mkdir(parents=True)
        for name in ['Cargo.toml', 'Cargo.lock', 'src', 'tests', 'examples', 'compat']:
            origin = ROOT / 'Native/GreenBubbles' / name
            destination = crate / name
            if origin.is_dir():
                shutil.copytree(origin, destination)
            else:
                shutil.copy2(origin, destination)
        (source / 'docs').mkdir()
        shutil.copy2(ROOT / 'docs/send-canonical-vectors.json', source / 'docs/send-canonical-vectors.json')
        (source / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/verify-ai-read-blacklist.py', source / 'scripts/verify-ai-read-blacklist.py')
        shutil.copy2(ROOT / 'scripts/query-proxy-e2e.py', source / 'scripts/query-proxy-e2e.py')
        common = ['docker', 'run', '--rm', '--cap-drop=ALL', '--security-opt=no-new-privileges',
                  '--mount', f'type=bind,src={source},dst=/source,readonly',
                  '--mount', 'type=volume,src=wesync-e2e-cargo,dst=/cargo',
                  '--mount', 'type=volume,src=wesync-e2e-target,dst=/target']
        # Dependency preparation sees only the same allowlisted source snapshot.
        run(common + [IMAGE, 'bash', '-euc', 'cp -R /source/. /work/; cargo fetch --locked'])
        command = ('cp -R /source/. /work/; cargo build --offline --locked; ' if args.proxy_only else
            'cp -R /source/. /work/; cargo test --offline --locked --all-targets; '
            'python3 /work/scripts/verify-ai-read-blacklist.py /target/debug/greenbubbles; ')
        output = subprocess.run(common + ['--network=none', IMAGE, 'bash', '-euc', command +
            'python3 /work/scripts/query-proxy-e2e.py /target/debug/greenbubbles'],
            check=True, text=True, stdout=subprocess.PIPE)
        print(output.stdout)
        marker = output.stdout.rfind('\n{')
        proxy_report = json.loads(output.stdout[marker + 1:])
        destination = ROOT / 'docs/acceptance/ai-query-proxy-20261116/synthetic.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(proxy_report, indent=2) + '\n')
        passed = True
finally:
    unchanged = before == fingerprint()
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({'passed': passed and unchanged, 'hostPolicyUnchanged': unchanged,
        'platform': 'isolated local Linux container', 'testNetwork': 'none',
        'source': 'allowlisted source and synthetic fixtures only', 'hostPolicyModified': False,
        'hostHomeMounted': False, 'image': IMAGE}, indent=2) + '\n')
    if not unchanged:
        raise RuntimeError('Host policy changed during isolated E2E; review concurrent edits')
print(f'PASS: {REPORT}')
