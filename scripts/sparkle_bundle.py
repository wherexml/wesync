#!/usr/bin/env python3
"""Embed the pinned Sparkle framework; sign nested code before the host bundle."""
from pathlib import Path
import argparse
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FEED = 'https://raw.githubusercontent.com/wherexml/wesync/main/updates/appcast.xml'
PUBLIC_KEY = 'Ezf1BaLI+RnN7zPKzrRp2gxsyYhDvWYSEwiFuxIkJXg='
ACCOUNT = 'me.greenbubbles.GreenBubbles.sparkle'


def embed_sparkle(app, identity, distribution=False):
    if not re.fullmatch(r'[0-9A-Fa-f]{40}', identity) and not identity.startswith('Developer ID Application: '):
        raise RuntimeError('Use an existing Apple certificate fingerprint or Developer ID identity; never ad-hoc')
    source = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    if not source.is_dir():
        raise RuntimeError('Resolve the pinned Swift package before packaging')
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    framework.parent.mkdir(parents=True, exist_ok=True)
    if framework.exists():
        shutil.rmtree(framework)
    subprocess.run(['/usr/bin/ditto', str(source), str(framework)], check=True)
    version = framework / 'Versions/B'
    flags = ['--force', '--sign', identity, '--options', 'runtime', '--preserve-metadata=entitlements']
    if distribution:
        flags.append('--timestamp')
    # Preserve the Downloader's sandbox and network entitlements; never disable library validation.
    for item in [version / 'Autoupdate', version / 'Updater.app',
                 version / 'XPCServices/Downloader.xpc', version / 'XPCServices/Installer.xpc', framework]:
        subprocess.run(['/usr/bin/codesign', *flags, str(item)], check=True, capture_output=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(framework)], check=True)
    details = subprocess.run(['/usr/bin/codesign', '-dvv', str(framework)], check=True,
                             text=True, capture_output=True).stderr
    authorities = ['Authority=Developer ID Application:']
    if not distribution:
        authorities.append('Authority=Apple Development:')
    if not any(value in details for value in authorities) or not re.search(r'TeamIdentifier=[A-Z0-9]{10}', details):
        raise RuntimeError('Sparkle must retain an Apple-issued signing identity')
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'SPARKLE_LICENSE.txt', resources / 'SPARKLE_LICENSE.txt')
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(SUFeedURL=FEED, SUPublicEDKey=PUBLIC_KEY, SURequireSignedFeed=True,
                SUSignedFeedFailureExpirationInterval=0,
                SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=True,
                SUAllowsAutomaticUpdates=False, SUAutomaticallyUpdate=False, SUSendProfileInfo=False)
    info_path.write_bytes(plistlib.dumps(info))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--distribution', action='store_true')
    args = parser.parse_args()
    embed_sparkle(args.app, args.identity, args.distribution)
