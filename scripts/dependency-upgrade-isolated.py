#!/usr/bin/env python3
"""Cross-version snapshot E2E, isolated from host policy and data.

Use --baseline-revision for manifest changes. Otherwise both builds use current source.
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
    parser.add_argument('--baseline-revision')
    parser.add_argument('--expect-engine', nargs=2, metavar=('SQLITE', 'SQLCIPHER'))
    args = parser.parse_args()
    if args.expect_engine and not args.baseline_revision:
        parser.error('--expect-engine requires --baseline-revision')
    before = fingerprint()
    try:
        with tempfile.TemporaryDirectory(prefix='wesync-dependency-isolated-') as temp:
            source = Path(temp)
            crate = source / 'Native/GreenBubbles'
            crate.mkdir(parents=True)
            for name in ['Cargo.toml', 'Cargo.lock', 'src', 'examples', 'compat']:
                origin = ROOT / 'Native/GreenBubbles' / name
                if name == 'compat' and not origin.exists():
                    continue
                if origin.is_dir():
                    shutil.copytree(origin, crate / name)
                else:
                    shutil.copy2(origin, crate / name)
            shutil.copy2(args.baseline_lock, source / 'baseline.lock')
            shutil.copy2(ROOT / 'scripts/dependency-upgrade-e2e.py', source / 'compatibility.py')
            if args.baseline_revision:
                baseline = source / 'baseline'
                baseline.mkdir()
                archive = baseline / 'source.tar'
                subprocess.run(['git', 'archive', '--output', str(archive), args.baseline_revision,
                                'Native/GreenBubbles'], cwd=ROOT, check=True)
                shutil.unpack_archive(archive, baseline)
                archive.unlink()
                old_crate = baseline / 'Native/GreenBubbles'
                if (old_crate / 'Cargo.lock').read_bytes() != args.baseline_lock.read_bytes():
                    raise ValueError('Baseline lock does not match the selected source revision')
                # The E2E driver builds the same synthetic generator with both engines.
                name = 'examples/dependency_upgrade_fixture.rs'
                shutil.copy2(crate / name, old_crate / name)
            output = source / 'result'
            output.mkdir(mode=0o777)
            output.chmod(0o777)
            common = ['docker', 'run', '--rm', '--cap-drop=ALL', '--security-opt=no-new-privileges',
                      '--mount', f'type=bind,src={source},dst=/source,readonly',
                      '--mount', f'type=bind,src={output},dst=/result',
                      '--mount', 'type=volume,src=wesync-e2e-cargo,dst=/cargo',
                      '--mount', 'type=volume,src=wesync-dependency-target,dst=/target']
            if args.baseline_revision:
                old_manifest = '/work/baseline/Native/GreenBubbles/Cargo.toml'
                fetch_old = f'cargo fetch --locked --manifest-path {old_manifest}; '
                build_old = (
                    f'cargo build --offline --locked --manifest-path {old_manifest} '
                    '--bin greenbubbles --example dependency_upgrade_fixture; '
                    'cp /target/debug/examples/dependency_upgrade_fixture /work/baseline-fixture; '
                )
                verify_flags = ['--baseline-fixture-generator', '/work/baseline-fixture']
                if args.expect_engine:
                    verify_flags += ['--expect-engine', *args.expect_engine]
            else:
                fetch_old = 'cp /work/baseline.lock Cargo.lock; cargo fetch --locked; '
                build_old = ('cp Cargo.lock /work/candidate.lock; cp /work/baseline.lock Cargo.lock; '
                             'cargo build --offline --locked --bin greenbubbles; '
                             'cp /work/candidate.lock Cargo.lock; ')
                verify_flags = []
            subprocess.run(common + [IMAGE, 'bash', '-euc',
                'cp -R /source/. /work/; cargo fetch --locked; ' + fetch_old], check=True)
            subprocess.run(common + ['--network=none', IMAGE, 'bash', '-euc',
                'cp -R /source/. /work/; ' + build_old +
                'cp /target/debug/greenbubbles /work/baseline-greenbubbles; '
                'cargo build --offline --locked --bin greenbubbles --example dependency_upgrade_fixture; '
                'python3 /work/compatibility.py /work/baseline-greenbubbles '
                '/target/debug/greenbubbles /result/compatibility.json '
                '--fixture-generator /target/debug/examples/dependency_upgrade_fixture "$@"',
                'compatibility', *verify_flags], check=True)
            report = json.loads((output / 'compatibility.json').read_text())
            report.update(platform='isolated local Linux container', testNetwork='none',
                          hostHomeMounted=False, hostPolicyUnchanged=before == fingerprint(),
                          buildScope=(f'baseline source {args.baseline_revision} and candidate source'
                                      if args.baseline_revision else
                                      'same current Rust source with baseline and candidate lockfiles'))
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + '\n')
    finally:
        if before != fingerprint():
            raise RuntimeError('Host policy changed during compatibility E2E')


if __name__ == '__main__':
    main()
