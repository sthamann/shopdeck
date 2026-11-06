#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_CONFIGURATION="$(printf '%s' "${SHOPDECK_CONFIGURATION:-debug}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 "$TASK_ROOT/script/generate_widget_localizations.py"
# Xcode coordinated reads can stall in cloud synced Documents folders. Build a private local copy.
TASK_WIDGET_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/shopdeck-widgets.XXXXXX")"
trap 'rm -rf "$TASK_WIDGET_STAGE"' EXIT
python3 - "$TASK_ROOT" "$TASK_WIDGET_STAGE" <<'PY_STAGE'
import pathlib,shutil,sys
source,stage=map(pathlib.Path,sys.argv[1:])
shutil.copytree(source/'Widgets',stage/'Widgets',ignore=shutil.ignore_patterns('*.xcodeproj','.DS_Store'))
(stage/'Sources/ShopdeckCore').mkdir(parents=True)
shutil.copy2(source/'Sources/ShopdeckCore/WidgetSnapshot.swift',stage/'Sources/ShopdeckCore/WidgetSnapshot.swift')
PY_STAGE
cd "$TASK_WIDGET_STAGE/Widgets"
xcodegen generate --spec project.yml --quiet
TASK_VERSION="$(awk -F '"' '/public static let current/ { print $2 }' "$TASK_ROOT/Sources/ShopdeckCore/AppVersion.swift")"
TASK_BUILD="$(python3 -c 'import sys; a,b,c=map(int,sys.argv[1].split(".")); print(a*1000000+b*1000+c)' "$TASK_VERSION")"
xcodebuild -project ShopdeckWidgets.xcodeproj -target ShopdeckWidgets -configuration "$TASK_CONFIGURATION" -sdk macosx SYMROOT="$TASK_ROOT/work/widgets" CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$TASK_VERSION" CURRENT_PROJECT_VERSION="$TASK_BUILD" build > "$TASK_ROOT/work/widgets-build.log" 2>&1
TASK_APP="${1:-$TASK_ROOT/../Shopdeck.app}"
mkdir -p "$TASK_APP/Contents/PlugIns"
ditto "$TASK_ROOT/work/widgets/$TASK_CONFIGURATION/ShopdeckWidgets.appex" "$TASK_APP/Contents/PlugIns/ShopdeckWidgets.appex"
xattr -cr "$TASK_APP/Contents/PlugIns/ShopdeckWidgets.appex"
codesign --force --options runtime --sign "${SHOPDECK_SIGN_IDENTITY:--}" --entitlements "$TASK_ROOT/Widgets/Widget.entitlements" "$TASK_APP/Contents/PlugIns/ShopdeckWidgets.appex"
