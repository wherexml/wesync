#!/usr/bin/env python3
"""Package isolated offline acceptance app. Does not launch or read WeChat."""
from pathlib import Path
import argparse,plistlib,shutil,os,re,subprocess,sys
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--identity',required=True,help='Existing Apple Development certificate SHA-1; never ad-hoc')
parser.add_argument('--polish',action='store_true')
parser.add_argument('--chinese',action='store_true')
parser.add_argument('--dark-mode',action='store_true')
parser.add_argument('--setup',action='store_true')
args=parser.parse_args()
if not re.fullmatch(r'[0-9A-Fa-f]{40}',args.identity):
 parser.error('Use the existing Apple Development certificate fingerprint; ad-hoc signing is forbidden.')
repo=Path(__file__).resolve().parents[1]
subprocess.run(['swift','build','--package-path',str(repo),'--product','greenbubbles-history'],check=True)
polish='--polish' in sys.argv
chinese='--chinese' in sys.argv
app_name='GreenBubbles Chinese Preview' if chinese else 'GreenBubbles Polish Preview' if polish else 'GreenBubbles Preview'
app_id='me.greenbubbles.ChinesePreview' if chinese else 'me.greenbubbles.PolishPreview' if polish else 'me.greenbubbles.PresentationPreview'
if '--dark-mode' in sys.argv:
 app_name='GreenBubbles Dark Mode Preview';app_id='me.greenbubbles.DarkModePreview'
if args.setup:
 app_name='we-sync Setup Preview';app_id='me.greenbubbles.SetupPreview'
app=repo/('.local-install/'+app_name+'.app');mac=app/'Contents/MacOS';res=app/'Contents/Resources';data=res/'offline-fixture'
mac.mkdir(parents=True,exist_ok=True);data.mkdir(parents=True,exist_ok=True);os.chmod(data,0o700)
(data/'session').mkdir(exist_ok=True)
(data/'session/session.db').write_bytes(b'Synthetic filesystem-notification fixture; not a real database')
shutil.copy2(repo/'.build/debug/greenbubbles-history',mac/'greenbubbles-history')
shutil.copy2(repo/'scripts/presentation-fixture/greenbubbles',mac/'greenbubbles')
shutil.copy2(repo/'Resources/Brand/GreenBubbles.icns',res/'GreenBubbles.icns')
shutil.copy2(repo/'Resources/Brand/GreenBubbles-black.png',res/'GreenBubbles-black.png')
if args.setup:
 fixture=app.parent/'setup-guide-fixture'
 for relative in ('session/session.db', 'contact/contact.db'):
  path=fixture/relative
  path.parent.mkdir(parents=True,exist_ok=True)
  if path.exists(): path.chmod(0o600)
  path.write_bytes(b'Synthetic permission fixture; not a real database')
  path.chmod(0o000 if relative.startswith('session/') else 0o600)
subprocess.run(['/usr/bin/sips','-s','format','png',str(res/'GreenBubbles.icns'),'--out',str(data/'sample.png')],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['/usr/bin/sips','-Z','128',str(data/'sample.png')],check=True,stdout=subprocess.DEVNULL)
# Generate a real HEVC frame inside a minimal WXGF container, from the public app icon.
subprocess.run(['/opt/homebrew/bin/ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(data/'sample.png'),'-vf','scale=256:256,format=yuv420p','-frames:v','1','-c:v','libx265','-x265-params','log-level=error','-f','hevc',str(data/'sample.hevc')],check=True,stderr=subprocess.DEVNULL)
hevc=(data/'sample.hevc').read_bytes()
(data/'sample.wxgf').write_bytes(b'wxgf'+bytes([8])+bytes(3)+len(hevc).to_bytes(4,'big')+hevc)
with (app/'Contents/Info.plist').open('wb') as f:
 plistlib.dump({'CFBundleExecutable':'greenbubbles-history','CFBundleIdentifier':app_id,'CFBundleName':app_name,'CFBundleDisplayName':app_name,'CFBundleIconFile':'GreenBubbles','CFBundlePackageType':'APPL','CFBundleDevelopmentRegion':'zh_CN','CFBundleLocalizations':['zh_CN'],'CFBundleVersion':'1','CFBundleShortVersionString':'0.10.0-preview','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0',('GBSetupAcceptance' if args.setup else 'GBOfflineAcceptance'):True},f)
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign',args.identity,str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
signature=subprocess.run(['/usr/bin/codesign','-dv','--verbose=2',str(app)],check=True,capture_output=True,text=True)
if 'Authority=Apple Development:' not in signature.stderr or 'TeamIdentifier=not set' in signature.stderr:
 raise RuntimeError('Preview must retain a legitimate Apple Development identity.')
print('Open preview app to execute offline acceptance:',app)
if args.setup:
 print('Permission fixture:',fixture/'session/session.db')
else:
 print('Artifacts:',data/'acceptance.json',data/'presentation.png')
