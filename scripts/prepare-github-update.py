#!/usr/bin/env python3
"""Prepare a signed GitHub appcast from a verified, notarized DMG. Never publishes."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import urllib.request
from sparkle_bundle import ROOT, PUBLIC_KEY, ACCOUNT
from sparkle_feed import signed_feed


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def digest(path):
    with path.open('rb') as stream:
        return stream_digest(stream)


def stream_digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dmg', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--published', action='store_true', help='Also verify the existing public asset')
    args = parser.parse_args()
    dmg = args.dmg.resolve()
    match = re.fullmatch(r'we-sync-(\d+\.\d+\.\d+)-macos-arm64\.dmg', dmg.name)
    if not match or not dmg.is_file() or args.out.exists():
        parser.error('Use a versioned DMG and a new output directory')
    version = match[1]
    identity = ('anchor apple generic and certificate leaf[subject.OU] = "T695TT4HT9" '
                'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
    run('/usr/bin/codesign', '--verify', '--strict', '-R', '=' + identity, str(dmg))
    run('/usr/bin/xcrun', 'stapler', 'validate', str(dmg))
    run('/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', str(dmg))
    with tempfile.TemporaryDirectory(prefix='we-sync-update-') as directory:
        mount = Path(directory) / 'volume'
        mount.mkdir()
        run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
            '-mountpoint', str(mount), str(dmg))
        try:
            app = mount / 'we-sync.app'
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R',
                '=' + identity + ' and identifier "me.greenbubbles.GreenBubbles"', str(app))
            run('/usr/bin/xcrun', 'stapler', 'validate', str(app))
            run('/usr/sbin/spctl', '--assess', '--type', 'execute', str(app))
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            build = info['CFBundleVersion']
            if (info['CFBundleShortVersionString'] != version or not re.fullmatch(r'[1-9]\d*', build)
                    or info['CFBundleExecutable'] != 'greenbubbles-history'):
                raise RuntimeError('DMG and application version mismatch')
            if run('/usr/bin/lipo', '-archs', str(app / 'Contents/MacOS/greenbubbles-history')).strip() != 'arm64':
                raise RuntimeError('Unexpected architecture')
        finally:
            run('/usr/bin/hdiutil', 'detach', str(mount))
    sha = digest(dmg)
    url = f'https://github.com/wherexml/wesync/releases/download/v{version}/{dmg.name}'
    if args.published:
        request = urllib.request.Request(f'https://api.github.com/repos/wherexml/wesync/releases/tags/v{version}',
                                         headers={'User-Agent': 'we-sync-release-verification'})
        with urllib.request.urlopen(request, timeout=30) as response:
            release = json.load(response)
        if release['draft'] or release['prerelease']:
            raise RuntimeError('Only public stable releases may enter this feed')
        with urllib.request.urlopen(url, timeout=120) as response:
            remote = stream_digest(response)
        if remote != sha:
            raise RuntimeError('Public asset differs from the reviewed local DMG')
    key = run(str(ROOT / '.build/artifacts/sparkle/Sparkle/bin/generate_keys'), '--account', ACCOUNT, '-p').strip()
    if key != PUBLIC_KEY:
        raise RuntimeError('Existing updater key does not match the pinned public key; do not regenerate it')
    args.out.mkdir(parents=True, mode=0o700)
    feed = args.out / 'appcast.xml'
    signed_feed(dmg, url, version, build, feed)
    receipt = {'version': version, 'build': build, 'archiveSHA256': sha,
               'feedSHA256': digest(feed), 'downloadURL': url, 'signatureVerified': True,
               'developerIDAndNotarizationVerified': True, 'publicAssetVerified': args.published,
               'publishedByThisCommand': False}
    (args.out / 'prepared.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
