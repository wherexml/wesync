#!/usr/bin/env python3
"""Installed-app read-only E2E. Quit through native UI before cold/concurrent cases.
The query CLI owns startup; this script never opens, hides or activates a window.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import pwd
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--case', choices=['cold', 'running', 'concurrent'], required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
cli = Path('/Applications/we-sync.app/Contents/MacOS/greenbubbles')
app = '/Applications/we-sync.app/Contents/MacOS/greenbubbles-history'
policy = Path(pwd.getpwuid(os.getuid()).pw_dir) / 'Library/Application Support/GreenBubbles/ai-read-policy.json'

def fingerprint():
    return (hashlib.sha256(policy.read_bytes()).digest(), policy.stat().st_mode & 0o777) if policy.exists() else None

before = fingerprint()
processes = subprocess.check_output(['/bin/ps', '-axo', 'comm='], text=True).splitlines()
running = app in [line.strip() for line in processes]
if args.case in ['cold', 'concurrent'] and running:
    raise SystemExit('Quit we-sync through native UI before this case.')
if args.case == 'running' and not running:
    raise SystemExit('Run the cold case first.')
args.out = args.out.resolve()
args.out.parent.mkdir(parents=True, exist_ok=True)
observer = ROOT / '.build/background-query-observer'
subprocess.run(['xcrun', 'swiftc', str(ROOT/'scripts/background-query-observer.swift'), '-o', str(observer)], check=True)
metrics = args.out.with_suffix('.window-metrics.json')
ready = metrics.with_suffix('.json.ready')
ready.unlink(missing_ok=True)
watch = subprocess.Popen([str(observer), str(metrics), '12'])
try:
    deadline = time.monotonic() + 10
    while not ready.exists():
        if watch.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError('Window observer did not start')
        time.sleep(.02)
    # Deny the client's direct database, config and old credential reads.
    home = str(Path(pwd.getpwuid(os.getuid()).pw_dir))
    roots = [home+'/Library/Containers/com.tencent.xinWeChat', home+'/.greenbubbles-acquire', home+'/.greenbubbles']
    profile = '(version 1)(allow default)(deny file-read* '+ ' '.join('(subpath '+json.dumps(x)+')' for x in roots) + ')'
    def query(_):
        start = time.monotonic()
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', profile, str(cli), 'source', 'status'], capture_output=True, timeout=40)
        try:
            payload = json.loads(result.stdout)
            passed = result.returncode == 0 and payload.get('ok') is True
        except ValueError:
            passed = False
        return {'passed': passed, 'seconds': round(time.monotonic()-start, 3)}
    if args.case == 'concurrent':
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            results = list(executor.map(query, range(4)))
    else:
        results = [query(i) for i in range(3 if args.case == 'running' else 1)]
    watch.wait(timeout=20)
    window = json.loads(metrics.read_text())
    unchanged = before == fingerprint()
    marker_removed = not (policy.parent / 'query-start-mode').exists()
    report = {'case': args.case, 'queries': results, 'window': window, 'startupMarkerRemoved': marker_removed,
              'clientDirectDatabaseReadsDenied': True, 'policyUnchanged': unchanged,
              'passed': unchanged and marker_removed and window['passed'] and all(x['passed'] for x in results)}
    args.out.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    if not report['passed']:
        raise SystemExit(1)
finally:
    if watch.poll() is None:
        watch.terminate()
        watch.wait(timeout=5)
    ready.unlink(missing_ok=True)
