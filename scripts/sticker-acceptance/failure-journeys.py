#!/usr/bin/env python3
"""Production loader subprocess journeys; live fixture stays in ignored private storage."""
import copy,json,subprocess,sys,xml.etree.ElementTree as ET
from pathlib import Path
repo=Path(__file__).resolve().parents[2]
root=repo/'.tmp/sticker-acceptance'
base=json.loads(Path(sys.argv[1]).read_text())
checks={}

def run(name,attributes=None,raw=None,expected=True,kind=None,offline=False,cache='failure-cache'):
    message=copy.deepcopy(base)
    if raw is None:
        elem=ET.fromstring(message['content']['Emoji'])
        emoji=elem.find('emoji')
        for key,value in (attributes or {}).items():emoji.set(key,value)
        raw=ET.tostring(elem,encoding='unicode')
    message['content']['Emoji']=raw
    path=root/(name+'.json');path.write_text(json.dumps(message));path.chmod(0o600)
    report=root/(name+'-result.json')
    command=[str(root/'runner'),str(path),str(root/cache),str(report)]
    if offline:command.append('--cache-only')
    result=subprocess.run(command,capture_output=True,timeout=50)
    data=json.loads(report.read_text())
    checks[name]=(result.returncode==0)==expected and data['passed']==expected and (not kind or data.get('resource')==kind)
    return data

run('encrypted-fallback',{'cdnurl':''},kind='encrypted',cache='encrypted-journey-cache')
run('encrypted-cache-restart',{'cdnurl':''},kind='encrypted',offline=True,cache='encrypted-journey-cache')
run('thumbnail-fallback',{'cdnurl':'','encrypturl':''},kind='thumbnail')
run('malformed',raw='<msg><emoji',expected=False)
run('entity-rejected',raw='<!DOCTYPE msg [<!ENTITY x SYSTEM "file:///etc/hosts">]><msg><emoji cdnurl="&x;"/></msg>',expected=False)
run('host-rejected',{'cdnurl':'https://example.com/sticker','encrypturl':'','thumburl':''},expected=False)
run('userinfo-rejected',{'cdnurl':'https://user@emoji.qpic.cn/sticker','encrypturl':'','thumburl':''},expected=False)
run('invalid-key',{'cdnurl':'','aeskey':'invalid','thumburl':''},expected=False)
run('wrong-digest',{'md5':'0'*32,'encrypturl':'','thumburl':''},expected=False)
run('cache-warm',kind='original',cache='corrupt-cache')
for file in (root/'corrupt-cache').iterdir():file.write_bytes(b'not-an-image')
run('corrupt-cache-rejected',expected=False,offline=True,cache='corrupt-cache')
run('corrupt-cache-recovers',kind='original',cache='corrupt-cache')
report={'passed':all(checks.values()),'checks':checks,'source':'bounded-real-sticker-with-controlled-failure-variants','installedApp':'NOT_RUN'}
(repo/'docs/acceptance/sticker-recovery/failure-journeys.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
sys.exit(0 if report['passed'] else 1)
