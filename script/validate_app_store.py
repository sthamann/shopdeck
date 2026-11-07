#!/usr/bin/env python3
"""Check a real Mac App Store candidate; never upload or submit anything."""
from pathlib import Path
import argparse, json, plistlib, subprocess, sys
parser=argparse.ArgumentParser()
parser.add_argument('app',type=Path)
parser.add_argument('--unsigned',action='store_true')
parser.add_argument('--submission',action='store_true')
parser.add_argument('--development-archive',action='store_true')
args=parser.parse_args();root=Path(__file__).resolve().parent.parent;errors=[]
def check(condition,message):
 if not condition:errors.append(message)
app=args.app
if not (app/'Contents/Info.plist').is_file():parser.error('App bundle missing')
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
check(info.get('CFBundleIdentifier')=='app.shopdeck.mac','Unexpected app identifier')
check(info.get('LSApplicationCategoryType')=='public.app-category.business','Business category missing')
check(bool(info.get('NSHumanReadableCopyright')),'Copyright missing')
check(not any(k.startswith('SU') for k in info),'Sparkle update keys must not appear in the Store bundle')
check(not list(app.rglob('Sparkle.framework')),'Sparkle must not be embedded')
manifest=app/'Contents/Resources/PrivacyInfo.xcprivacy';check(manifest.is_file(),'Privacy manifest missing')
if manifest.is_file():
 d=plistlib.loads(manifest.read_bytes());check(d.get('NSPrivacyTracking') is False,'Tracking declaration must match the app')
check((app/'Contents/PlugIns/ShopdeckWidgets.appex').is_dir(),'Widget extension missing')
check((app/'Contents/Resources/Localizations.tsv').is_file(),'Six language translation table missing')
for name in ('shopdeck-keychain','shopdeck-mcp'):check((app/'Contents/Helpers'/name).is_file(),f'{name} not embedded')
if not args.unsigned:
 check(subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True).returncode==0,'Signature verification failed')
 for bundle,kind in [(app,'app'),(app/'Contents/PlugIns/ShopdeckWidgets.appex','widget')]:
  result=subprocess.run(['codesign','-d','--entitlements',':-',str(bundle)],capture_output=True)
  try:ent=plistlib.loads(result.stdout)
  except Exception:ent={}
  check(ent.get('com.apple.security.app-sandbox') is True,f'{kind} sandbox missing')
  if not args.development_archive:check(not ent.get('com.apple.security.get-task-allow') and not ent.get('get-task-allow'),f'{kind} contains a development entitlement')
  profile=bundle/'Contents/embedded.provisionprofile'
  if not args.development_archive:check(profile.is_file(),f'{kind} distribution profile missing')
  if profile.is_file():
   result=subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True)
   try:
    p=plistlib.loads(result.stdout);e=p['Entitlements'];identifier=e.get('com.apple.application-identifier') or e.get('application-identifier');expected='YXRJR897BM.'+plistlib.loads((bundle/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
    check(identifier==expected,f'{kind} profile identifier mismatch');check('ProvisionsAllDevices' not in p,f'{kind} uses a Developer ID profile')
    if not args.development_archive:check('ProvisionedDevices' not in p,f'{kind} profile is not an App Store profile')
   except Exception:check(False,f'{kind} profile cannot be decoded')
if args.submission:
 readiness=json.loads((root/'AppStore/release-readiness.json').read_text());check(readiness.get('ready_for_review') is True,'Store runtime and product scope have not been accepted for review')
 for name,passed in readiness['checks'].items():check(passed is True,f'Unresolved submission item: {name}')
for message in errors:print('FAIL:',message,file=sys.stderr)
if errors:sys.exit(1)
print('Bundle checks passed'+(' (unsigned engineering build only)' if args.unsigned else ''))
if not args.submission:print('Not a submission approval. Run with --submission after verifying AppStore/release-readiness.json.')
