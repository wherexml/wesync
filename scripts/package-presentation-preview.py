#!/usr/bin/env python3
"""Package isolated offline acceptance app. Does not launch or read WeChat."""
from pathlib import Path
import plistlib,shutil,os,subprocess,sys
repo=Path(__file__).resolve().parents[1]
subprocess.run(['swift','build','--package-path',str(repo),'--product','greenbubbles-history'],check=True)
polish='--polish' in sys.argv
chinese='--chinese' in sys.argv
app_name='GreenBubbles Chinese Preview' if chinese else 'GreenBubbles Polish Preview' if polish else 'GreenBubbles Preview'
app_id='me.greenbubbles.ChinesePreview' if chinese else 'me.greenbubbles.PolishPreview' if polish else 'me.greenbubbles.PresentationPreview'
if '--dark-mode' in sys.argv:
 app_name='GreenBubbles Dark Mode Preview';app_id='me.greenbubbles.DarkModePreview'
app=repo/('.local-install/'+app_name+'.app');mac=app/'Contents/MacOS';res=app/'Contents/Resources';data=res/'offline-fixture'
mac.mkdir(parents=True,exist_ok=True);data.mkdir(parents=True,exist_ok=True);os.chmod(data,0o700)
(data/'session').mkdir(exist_ok=True)
(data/'session/session.db').write_bytes(b'Synthetic filesystem-notification fixture; not a real database')
shutil.copy2(repo/'.build/debug/greenbubbles-history',mac/'greenbubbles-history')
shutil.copy2(repo/'scripts/presentation-fixture/greenbubbles',mac/'greenbubbles')
shutil.copy2(repo/'Resources/Brand/GreenBubbles.icns',res/'GreenBubbles.icns')
shutil.copy2(repo/'Resources/Brand/GreenBubbles-black.png',res/'GreenBubbles-black.png')
subprocess.run(['/usr/bin/sips','-s','format','png',str(res/'GreenBubbles.icns'),'--out',str(data/'sample.png')],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['/usr/bin/sips','-Z','128',str(data/'sample.png')],check=True,stdout=subprocess.DEVNULL)
# Generate a real HEVC frame inside a minimal WXGF container, from the public app icon.
subprocess.run(['/opt/homebrew/bin/ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(data/'sample.png'),'-vf','scale=256:256,format=yuv420p','-frames:v','1','-c:v','libx265','-x265-params','log-level=error','-f','hevc',str(data/'sample.hevc')],check=True,stderr=subprocess.DEVNULL)
hevc=(data/'sample.hevc').read_bytes()
(data/'sample.wxgf').write_bytes(b'wxgf'+bytes([8])+bytes(3)+len(hevc).to_bytes(4,'big')+hevc)
with (app/'Contents/Info.plist').open('wb') as f:
 plistlib.dump({'CFBundleExecutable':'greenbubbles-history','CFBundleIdentifier':app_id,'CFBundleName':app_name,'CFBundleDisplayName':app_name,'CFBundleIconFile':'GreenBubbles','CFBundlePackageType':'APPL','CFBundleDevelopmentRegion':'zh_CN','CFBundleLocalizations':['zh_CN'],'CFBundleVersion':'1','CFBundleShortVersionString':'0.10.0-preview','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0','GBOfflineAcceptance':True},f)
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(app)],check=True)
print('Open preview app to execute offline acceptance:',app)
print('Artifacts:',data/'acceptance.json',data/'presentation.png')
