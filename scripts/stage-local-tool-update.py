#!/usr/bin/env python3
"""Stage a certificate-signed application/CLI update with exact digest migration.
Does not install, access credentials, or change TCC. Requires existing stable identity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--identity', required=True)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--migrate-signing-identity', action='store_true', help='Explicit migration to an Apple-issued signing identity; native permission acceptance required')
args = parser.parse_args()
if not re.fullmatch('[0-9a-fA-F]{40}', args.identity): parser.error('Exact certificate SHA-1 required')
source = Path('/Applications/WeSync.app')
target = args.output.resolve() / 'WeSync.app'
if target.exists(): parser.error('Use a new staging output directory')

def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def requirement(path):
    output = run('/usr/bin/codesign','-d','-r-',str(path))
    return next(line for line in (output.stderr+output.stdout).splitlines() if line.startswith('designated =>'))

run('/usr/bin/codesign','--verify','--deep','--strict',str(source))
old_requirement = requirement(source)
if 'certificate' not in old_requirement: raise RuntimeError('Stable certificate migration must be completed first')
run('/usr/bin/ditto',str(source),str(target))
mac = target/'Contents/MacOS'
previous = digest(source/'Contents/MacOS/greenbubbles')
shutil.copy2(root/'.build/release/greenbubbles-history',mac/'greenbubbles-history')
for name in ('greenbubbles','greenbubbles-sticker-query'):
    shutil.copy2(root/'Native/GreenBubbles/target/release/greenbubbles',mac/name)
    run('/usr/bin/codesign','--force','--sign',args.identity,'--identifier','me.greenbubbles.'+name,str(mac/name))
predecessors = {previous}
previous_manifest = source/'Contents/Resources/ToolUpdate.json'
if previous_manifest.exists():
    # Source's complete signature was verified before importing its sealed history.
    prior = json.loads(previous_manifest.read_text())
    predecessors.add(prior['previousSHA256'])
    predecessors.update(prior.get('previousSHA256s', []))
manifest = {'previousSHA256':previous,'previousSHA256s':sorted(predecessors),'currentSHA256':digest(mac/'greenbubbles')}
(target/'Contents/Resources/ToolUpdate.json').write_text(json.dumps(manifest)+'\n')
info_path = target/'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['CFBundleVersion'] = str(int(info['CFBundleVersion'])+1)
info['GBStickerQuerySHA256'] = digest(mac/'greenbubbles-sticker-query')
info_path.write_bytes(plistlib.dumps(info))
run('/usr/bin/codesign','--force','--sign',args.identity,'--preserve-metadata=entitlements,flags,runtime',str(target))
run('/usr/bin/codesign','--verify','--deep','--strict',str(target))
new_requirement = requirement(target)
if new_requirement != old_requirement:
    if not args.migrate_signing_identity: raise RuntimeError('App identity changed; do not install')
    run('/usr/bin/codesign','--verify','--strict','-R','=anchor apple generic',str(target))
    details = run('/usr/bin/codesign','-dvv',str(target)).stderr
    team = re.search(r'TeamIdentifier=([A-Z0-9]+)', details)
    if not team: raise RuntimeError('Signing migration requires a verified Apple team identity')
# Verify identity remains stable after a real resource/build update, without installation.
probe = args.output.resolve() / 'identity-probe.app'
run('/usr/bin/ditto', str(target), str(probe))
probe_info = probe/'Contents/Info.plist'
probe_values = plistlib.loads(probe_info.read_bytes())
probe_values['CFBundleVersion'] = info['CFBundleVersion'] + '.1'
probe_info.write_bytes(plistlib.dumps(probe_values))
run('/usr/bin/codesign','--force','--sign',args.identity,'--preserve-metadata=entitlements,flags,runtime',str(probe))
run('/usr/bin/codesign','--verify','--deep','--strict',str(probe))
if requirement(probe) != new_requirement: raise RuntimeError('Signing identity changed across a resource update')
if digest(mac/'greenbubbles-send') != digest(source/'Contents/MacOS/greenbubbles-send'): raise RuntimeError('Send helper unexpectedly changed')
print(json.dumps({'staged':str(target),'stableIdentity':True,'identityMigration':new_requirement != old_requirement,'exactToolMigration':True,'sendHelperUnchanged':True,'build':info['CFBundleVersion']}))
