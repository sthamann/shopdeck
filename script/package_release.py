#!/usr/bin/env python3
"""Archive a built Shopdeck milestone without build caches or private workspace data."""
import argparse, pathlib, re, zipfile, shutil, os, stat
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
with zipfile.ZipFile(app_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
    for p in sorted((out/'Shopdeck.app').rglob('*')):
        if p.is_symlink():
            info=zipfile.ZipInfo(str(p.relative_to(out)));info.create_system=3;info.external_attr=(stat.S_IFLNK | 0o777)<<16;archive.writestr(info,os.readlink(p))
        elif p.is_file(): archive.write(p, p.relative_to(out))
with zipfile.ZipFile(source_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ['.build','work','dist','.swiftpm','.git']]
        for name in files:
            if name == '.DS_Store': continue
            path = pathlib.Path(folder)/name
            archive.write(path, pathlib.Path('Shopdeck')/path.relative_to(root))
shutil.copyfile(app_zip, out/'Shopdeck-macOS.zip')
shutil.copyfile(source_zip, out/'Shopdeck-Quellcode.zip')
print(f'Archived Shopdeck {version}: {release.name}')
