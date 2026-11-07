#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:---build}"
case "$TASK_MODE" in --build|--archive|--export) ;; *) echo 'Usage: script/build_app_store.sh [--build|--archive|--export]' >&2; exit 2;; esac
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TASK_BUILD_DIR="${SHOPDECK_STORE_BUILD_DIR:-/private/tmp/Shopdeck-AppStore-build}"
mkdir -p "$TASK_BUILD_DIR"
if [ "$TASK_MODE" = --export ]; then
  python3 "$TASK_ROOT/script/validate_app_store.py" "$TASK_BUILD_DIR/Shopdeck.xcarchive/Products/Applications/Shopdeck.app" --development-archive --submission
  xcodebuild -exportArchive -archivePath "$TASK_BUILD_DIR/Shopdeck.xcarchive" -exportPath "$TASK_BUILD_DIR/Export" -exportOptionsPlist "$TASK_ROOT/AppStore/ExportOptions.plist"
  exit
fi
TASK_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/shopdeck-store-source.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
python3 - "$TASK_ROOT" "$TASK_STAGE" <<'PY'
from pathlib import Path
import shutil,sys,re
source,stage=map(Path,sys.argv[1:])
for name in ('Sources','Widgets','Assets','AppStore'):
 shutil.copytree(source/name,stage/name,ignore=shutil.ignore_patterns('*.xcodeproj','.DS_Store','metadata'))
spec=stage/'AppStore/project.yml';text=spec.read_text();version=re.search(r'current = "([^"]+)"',(source/'Sources/ShopdeckCore/AppVersion.swift').read_text()).group(1)
a,b,c=map(int,version.split('.'));text=re.sub(r"MARKETING_VERSION: '[^']+'",f"MARKETING_VERSION: '{version}'",text);text=re.sub(r"CURRENT_PROJECT_VERSION: '[^']+'",f"CURRENT_PROJECT_VERSION: '{a*1000000+b*1000+c}'",text);spec.write_text(text)
PY
python3 "$TASK_ROOT/script/generate_widget_localizations.py"
cp -R "$TASK_ROOT/Widgets/Resources/." "$TASK_STAGE/Widgets/Resources/"
xcodegen generate --spec "$TASK_STAGE/AppStore/project.yml" --quiet
TASK_ARGS=(-project "$TASK_STAGE/AppStore/ShopdeckStore.xcodeproj" -scheme ShopdeckStore -sdk macosx -derivedDataPath "$TASK_BUILD_DIR/DerivedData")
if [ "${SHOPDECK_STORE_MANAGE_PROFILES:-0}" = "1" ]; then TASK_ARGS+=(-allowProvisioningUpdates); fi
if [ "$TASK_MODE" = --archive ]; then
  xcodebuild "${TASK_ARGS[@]}" -configuration Release -archivePath "$TASK_BUILD_DIR/Shopdeck.xcarchive" archive > "$TASK_BUILD_DIR/archive.log" 2>&1
  python3 "$TASK_ROOT/script/validate_app_store.py" "$TASK_BUILD_DIR/Shopdeck.xcarchive/Products/Applications/Shopdeck.app" --development-archive
else
  xcodebuild "${TASK_ARGS[@]}" -configuration Debug CODE_SIGNING_ALLOWED=NO build > "$TASK_BUILD_DIR/build.log" 2>&1
  python3 "$TASK_ROOT/script/validate_app_store.py" "$TASK_BUILD_DIR/DerivedData/Build/Products/Debug/Shopdeck.app" --unsigned
fi
printf 'Store engineering build: %s\n' "$TASK_BUILD_DIR"
