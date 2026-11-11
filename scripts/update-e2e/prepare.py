#!/usr/bin/env python3
"""Build an isolated, same-identity native Sparkle update and loopback feed."""
from pathlib import Path
import argparse
import functools
import hashlib
import http.server
import json
import os
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from sparkle_bundle import embed_sparkle
from sparkle_feed import signed_feed, SIGN

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--identity', required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--product-ui', action='store_true', default=True, help='Use the real application with synthetic chats (default)')
parser.add_argument('--minimal-host', dest='product_ui', action='store_false', help='Only for isolated transport debugging; not UI acceptance')
parser.add_argument('--automatic', action='store_true', help='Check and download without a manual click')
args = parser.parse_args()
root = args.out.resolve()
root.mkdir(mode=0o700)
server_root = root / 'server'
server_root.mkdir()
framework = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
key = root / 'test-signing-material'
generator = '''import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
'''
public = subprocess.run(['swift', '-', str(key)], input=generator, text=True,
                        check=True, capture_output=True).stdout.strip()
key.chmod(0o600)
binary = root / 'update-preview'
if args.product_ui:
 subprocess.run(['swift','build','--product','greenbubbles-history'],cwd=ROOT,check=True)
 shutil.copy2(ROOT/'.build/debug/greenbubbles-history',binary)
else:
 subprocess.run(['swiftc', '-D', 'DEBUG', '-parse-as-library', '-target', 'arm64-apple-macos14',
                '-F', str(framework.parent), '-framework', 'Sparkle',
                '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                str(ROOT / 'Sources/GreenBubblesHistoryApp/HistoryUpdater.swift'),
                str(ROOT / 'Sources/GreenBubblesHistoryApp/HistoryUpdateNotice.swift'),
                str(ROOT / 'Sources/GreenBubblesHistoryApp/HistoryDesign.swift'),
                str(ROOT / 'scripts/update-e2e/Host.swift'), '-o', str(binary)], check=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *unused):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(server_root)))
port = server.server_port
assert port >= 10000
base = f'http://127.0.0.1:{port}'
app = root / 'we-sync Update Preview.app'


def make_app(target, build):
    mac = target / 'Contents/MacOS'
    mac.mkdir(parents=True)
    shutil.copy2(binary, mac / 'update-preview')
    info = {'CFBundleExecutable': 'update-preview', 'CFBundleIdentifier': 'me.greenbubbles.UpdaterPreview',
            'CFBundleName': 'we-sync Update Preview', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.10.0', 'CFBundleVersion': str(build),
            'CFBundleDevelopmentRegion': 'zh_CN', 'LSMinimumSystemVersion': '14.0',
            'GBUpdatePreview': True, 'GBUpdateEvidenceDirectory': str(root)}
    if args.product_ui:
        info.update(CFBundleIdentifier='me.greenbubbles.PresentationPreview',GBOfflineAcceptance=True)
        fixture=target/'Contents/Resources/offline-fixture'
        (fixture/'session').mkdir(parents=True)
        (fixture/'session/session.db').write_bytes(b'Synthetic notification fixture')
        (fixture/'update-notice-acceptance').touch()
        shutil.copy2(ROOT/'Resources/Brand/GreenBubbles.iconset/icon_128x128.png',fixture/'sample.png')
        for name in ['GreenBubbles.icns','GreenBubbles-black.png']:
            shutil.copy2(ROOT/'Resources/Brand'/name,target/'Contents/Resources'/name)
        info['CFBundleIconFile']='GreenBubbles'
        shutil.copy2(ROOT/'scripts/presentation-fixture/greenbubbles',mac/'greenbubbles')
        subprocess.run(['codesign','--force','--sign',args.identity,str(mac/'greenbubbles')],check=True,capture_output=True)
    (target / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    embed_sparkle(target, args.identity)
    info = plistlib.loads((target / 'Contents/Info.plist').read_bytes())
    info.update(SUFeedURL=base + '/appcast.xml', SUPublicEDKey=public,
                SUEnableAutomaticChecks=args.automatic, SUShowReleaseNotes=False,
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    (target / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', args.identity, str(target)], check=True, capture_output=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True)


make_app(app, 1)
candidate = root / 'candidate/we-sync Update Preview.app'
make_app(candidate, 2)
archive = server_root / 'update.zip'
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(candidate), str(archive)], check=True)
signed_feed(archive, base + '/update.zip', '0.10.0', 2, server_root / 'available.xml', key)
signed_feed(archive, base + '/update.zip', '0.10.0', 1, server_root / 'current.xml', key)
bad = server_root / 'invalid.xml'
bad.write_bytes((server_root / 'available.xml').read_bytes().replace(b'we-sync 0.10.0', b'tampered title'))
verification = subprocess.run([str(SIGN), '--ed-key-file', str(key), '--verify', str(bad)], capture_output=True)
assert verification.returncode != 0
tampered = server_root / 'tampered.zip'
shutil.copy2(archive, tampered)
with tampered.open('ab') as stream:
    stream.write(b'tampered')
signed_feed(tampered, base + '/tampered.zip', '0.10.0', 2, server_root / 'bad-archive.xml', key)
# Keep the feed signature valid while binding it to the original archive's signature/length.
import xml.etree.ElementTree as ET
valid = ET.parse(server_root / 'available.xml').getroot()
valid.find('./channel/item/enclosure').set('url', base + '/tampered.zip')
ET.ElementTree(valid).write(server_root / 'bad-archive.xml', encoding='utf-8', xml_declaration=True)
subprocess.run([str(SIGN), '--ed-key-file', str(key), str(server_root / 'bad-archive.xml')], check=True, capture_output=True)
shutil.copy2(server_root / ('available.xml' if args.automatic else 'current.xml'), server_root / 'appcast.xml')
receipt = {'application': str(app), 'feed': base + '/appcast.xml', 'port': port,
           'baselineBuild': '1', 'candidateBuild': '2', 'feedTamperRejectedBySigningTool': True,
           'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(),
           'source': 'synthetic-only', 'keychainRead': False, 'wechatOperated': False}
(root / 'prepared.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'ready': True, 'app': str(app), 'port': port}), flush=True)
try:
    server.serve_forever()
finally:
    server.server_close()
