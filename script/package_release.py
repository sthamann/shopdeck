#!/usr/bin/env python3
"""Archive a built Shopdeck milestone without build caches or private workspace data."""
import argparse, pathlib, re, zipfile, shutil, os, stat, subprocess
parser = argparse.ArgumentParser()
parser.add_argument('stage')
parser.add_argument('label')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
out = root.parent
version = re.search(r'current = "([^"]+)"', (root/'Sources/ShopdeckCore/AppVersion.swift').read_text()).group(1)
release = out/'staende'/f'{args.stage}-{args.label}'
release.mkdir(parents=True, exist_ok=True)
app_zip = release/f'Shopdeck-{version}-macOS.zip'
source_zip = release/f'Shopdeck-{version}-Quellcode.zip'
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(out/'Shopdeck.app'),str(app_zip)],check=True)
with zipfile.ZipFile(source_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
    if (root/'.git').exists():
        paths=[root/os.fsdecode(p) for p in subprocess.check_output(['git','-C',str(root),'ls-files','-z']).split(b'\0') if p]
    else:
        excluded={'.build','work','dist','.swiftpm','.git','.codebase-memory','xcuserdata'}
        paths=[p for p in root.rglob('*') if p.is_file() and not any(part in excluded or part.endswith('.xcodeproj') for part in p.relative_to(root).parts) and p.suffix not in ['.key','.p12','.p8'] and not p.name.startswith('.env')]
    for path in sorted(paths):
        if path.is_file():archive.write(path,pathlib.Path('Shopdeck')/path.relative_to(root))
shutil.copyfile(app_zip, out/'Shopdeck-macOS.zip')
shutil.copyfile(source_zip, out/'Shopdeck-Quellcode.zip')
print(f'Archived Shopdeck {version}: {release.name}')
