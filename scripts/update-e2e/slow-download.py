#!/usr/bin/env python3
"""Serve a signed synthetic build slowly for native cancellation acceptance."""
from pathlib import Path
import argparse
import http.server
import json
import plistlib
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from sparkle_feed import signed_feed

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--identity', required=True)
args = parser.parse_args()
root = args.root.resolve()
candidate = root / 'cancel-candidate/we-sync Update Preview.app'
subprocess.run(['/usr/bin/ditto', str(root / 'we-sync Update Preview.app'), str(candidate)], check=True)
p = candidate / 'Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
assert info['CFBundleIdentifier'] in ['me.greenbubbles.UpdaterPreview','me.greenbubbles.PresentationPreview']
assert info.get('GBUpdatePreview') is True
info['CFBundleVersion'] = str(int(info['CFBundleVersion']) + 1)
p.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--sign', args.identity, str(candidate)], check=True, capture_output=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(candidate)], check=True)
archive = root / 'slow-update.zip'
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(candidate), str(archive)], check=True)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *unused):
        pass

    def do_GET(self):
        if self.path != '/slow-update.zip':
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(archive.stat().st_size))
        self.end_headers()
        try:
            with archive.open('rb') as stream:
                for block in iter(lambda: stream.read(16384), b''):
                    self.wfile.write(block)
                    self.wfile.flush()
                    time.sleep(2)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
assert server.server_port >= 10000
signed_feed(archive, f'http://127.0.0.1:{server.server_port}/slow-update.zip', '0.10.0', info['CFBundleVersion'],
            root / 'server/slow.xml', root / 'test-signing-material')
shutil.copy2(root / 'server/slow.xml', root / 'server/appcast.xml')
print(json.dumps({'ready': True, 'port': server.server_port, 'source': 'synthetic-only'}), flush=True)
server.serve_forever()
