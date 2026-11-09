#!/usr/bin/env python3
"""End-to-end CLI image checks. Synthetic account tree only; no WeChat access."""
from pathlib import Path
import hashlib,json,os,struct,subprocess,tempfile
repo=Path(__file__).resolve().parents[1]
cli=repo/'Native/GreenBubbles/target/release/greenbubbles'
checks={}
with tempfile.TemporaryDirectory(prefix='gb-dat-e2e-') as tmp:
 root=Path(tmp);os.chmod(root,0o700)
 png=root/'original.png'
 subprocess.run(['/usr/bin/sips','-s','format','png','/Applications/we-sync.app/Contents/Resources/GreenBubbles.icns','--out',str(png)],check=True,stdout=subprocess.DEVNULL)
 original=png.read_bytes();aes_size=1024
 aes=subprocess.run(['/usr/bin/openssl','enc','-aes-128-ecb','-K',b'cfcd208495d565ef'.hex()],input=original[:aes_size],capture_output=True,check=True).stdout
 account=root/'account';folder=account/'msg/attach'/hashlib.md5(b'synthetic_friend').hexdigest()/'2026-10/Img';folder.mkdir(parents=True)
 def run(args):
  p=subprocess.run([str(cli),*args],stdin=subprocess.DEVNULL,capture_output=True)
  return p.returncode,json.loads(p.stdout or b'{}')
 for index,(name,key,tail,corrupt) in enumerate([('non-default-tail',0xa5,1024,False),('default-tail',0x37,1024,False),('short-tail',0xa5,4,False),('no-tail',0,0,False),('invalid-boundary',0xa5,1024,True)]):
  md5=f'{index:032x}'
  dat=b'\x07\x08V1\x08\x07'+struct.pack('<II',aes_size,999999999 if corrupt else tail)+b'\0'+aes+original[aes_size:len(original)-tail if tail else len(original)]+(bytes(x^key for x in original[-tail:]) if tail else b'')
  (folder/(md5+'_h.dat')).write_bytes(dat)
  args=[str(account),'--conversation','synthetic_friend','--md5',md5]
  code,ins=run(['attachment','inspect',*args]);assert code==0
  output=root/(name+'.png')
  code,receipt=run(['attachment','materialize',*args,'--attachment',ins['preferredAttachmentId'],'--output',str(output)])
  if corrupt:checks[name]=code!=0 and not output.exists()
  else:
   checks[name]=code==0 and output.read_bytes()==original and receipt['decodedSha256']==hashlib.sha256(original).hexdigest()
   decoded=subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-i',str(output),'-f','null','-'],capture_output=True)
   checks[name+'-pixels']=decoded.returncode==0
report={'source':'synthetic-only','checks':checks,'passed':all(checks.values())}
destination=repo.parent/'docs/acceptance/greenbubbles-explorer-2026-10-02/dat-e2e.json';destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(json.dumps(report,indent=2));print(json.dumps(report));raise SystemExit(0 if report['passed'] else 1)
