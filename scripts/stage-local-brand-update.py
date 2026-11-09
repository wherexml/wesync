#!/usr/bin/env python3
"""Stage a signed we-sync presentation update without changing connection tools.

An optional rebuilt main executable may update UI copy. Never installs or
touches connection data, and requires the installed signing identity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def requirement(app):
    result = run('/usr/bin/codesign', '-d', '-r-', str(app))
    return next(line.removeprefix('# ') for line in (result.stdout + result.stderr).splitlines()
                if 'designated =>' in line)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('/Applications/we-sync.app'))
    parser.add_argument('--main-executable', type=Path,
                        help='Optional rebuilt greenbubbles-history; all helpers stay unchanged')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--identity', required=True, help='Exact SHA-1 certificate fingerprint')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9A-Fa-f]{40}', args.identity):
        parser.error('Supply a certificate fingerprint; ad-hoc signing is not supported.')
    source = args.source.resolve()
    output = args.output.resolve()
    if output.exists() or output == source or source in output.parents:
        parser.error('Output must be a new directory outside the installed bundle.')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(source))
    source_requirement = requirement(source)
    original = {str(p.relative_to(source)): digest(p)
                for p in source.rglob('*') if p.is_file()}
    output.mkdir(parents=True, mode=0o700)
    baseline = output / 'Baseline.app'
    candidate = output / 'we-sync.app'
    # ditto preserves macOS metadata. The baseline also proves stable identity
    # across two different resource envelopes; both copies stay outside /Applications.
    for target in (baseline, candidate):
        run('/usr/bin/ditto', str(source), str(target))
    if args.main_executable:
        shutil.copy2(args.main_executable, candidate / 'Contents/MacOS/greenbubbles-history')
    resources = candidate / 'Contents/Resources'
    for name in ('GreenBubbles.icns', 'GreenBubbles-black.png'):
        shutil.copy2(ROOT / 'Resources/Brand' / name, resources / name)
    plist = candidate / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleIconFile'] = 'GreenBubbles'
    info['CFBundleName'] = 'we-sync'
    info['CFBundleDisplayName'] = 'we-sync'
    info['CFBundleVersion'] = str(int(info['CFBundleVersion']) + 1)
    plist.write_bytes(plistlib.dumps(info))
    for target in (baseline, candidate):
        # Do not use --deep while signing: preserve the query-tool bytes and
        # its remembered digest. Do not preserve the old ad-hoc requirement.
        run('/usr/bin/codesign', '--force', '--sign', args.identity,
            '--preserve-metadata=entitlements,flags,runtime', str(target))
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(target))
    baseline_requirement = requirement(baseline)
    candidate_requirement = requirement(candidate)
    if (source_requirement != baseline_requirement
            or baseline_requirement != candidate_requirement or 'cdhash' in candidate_requirement):
        raise RuntimeError('Signing identity is not stable across the resource update.')
    for rel, expected in original.items():
        if rel.startswith('Contents/MacOS/') and rel != 'Contents/MacOS/greenbubbles-history':
            if digest(candidate / rel) != expected:
                raise RuntimeError('A preserved helper changed: ' + rel)
    source_info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'GBStickerQuerySHA256'):
        if info.get(key) != source_info.get(key):
            raise RuntimeError('A preserved application identity field changed: ' + key)
    for rel, expected in original.items():
        if digest(source / rel) != expected:
            raise RuntimeError('Installed app changed while staging; do not install this candidate.')
    receipt = {
        'sourceBundleVersion': plistlib.loads((source / 'Contents/Info.plist').read_bytes())['CFBundleVersion'],
        'candidateBundleVersion': info['CFBundleVersion'],
        'certificateSHA1': args.identity.upper(),
        'designatedRequirement': candidate_requirement,
        'sameIdentityAcrossResourceUpdate': True,
        'signatureVerification': 'PASS',
        'queryAndSendBinariesUnchanged': True,
        'allHelperBinariesUnchanged': True,
        'applicationDisplayName': info['CFBundleDisplayName'],
        'mainExecutableRebuilt': bool(args.main_executable),
        'installedBundleUnchanged': True,
        'sourceFilesSHA256': original,
        'installedRestartAcceptance': 'PENDING',
        'scope': 'Local-only signing; not Developer ID distribution or notarization.',
    }
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Signed candidate prepared:', candidate)
    print('Signature and stable identity checks: PASS. Installation is a separate step.')


if __name__ == '__main__':
    main()
