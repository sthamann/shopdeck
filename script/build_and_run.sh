#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
TASK_IDENTITY="${SHOPDECK_SIGN_IDENTITY:--}"
TASK_CONFIGURATION="${SHOPDECK_CONFIGURATION:-debug}"
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/work/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/work/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
TASK_APP="${SHOPDECK_APP_OUTPUT:-$TASK_ROOT/../Shopdeck.app}"
python3 - "$TASK_APP/Contents/MacOS/Shopdeck" <<'PY_STOP'
import sys,subprocess,os,signal,unicodedata
from pathlib import Path
target=unicodedata.normalize('NFC',str(Path(sys.argv[1]).resolve()))
for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines():
 fields=line.strip().split(maxsplit=1)
 if len(fields)==2:
  command=unicodedata.normalize('NFC',fields[1])
  if command==target or command.startswith(target+' '): os.kill(int(fields[0]),signal.SIGTERM)
PY_STOP
swift build -c "$TASK_CONFIGURATION" --disable-sandbox
TASK_BIN="$(swift build -c "$TASK_CONFIGURATION" --disable-sandbox --show-bin-path)"
TASK_APP="${SHOPDECK_APP_OUTPUT:-$TASK_ROOT/../Shopdeck.app}"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Helpers" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN/Shopdeck" "$TASK_APP/Contents/MacOS/Shopdeck"
cp "$TASK_BIN/shopdeck-mcp" "$TASK_APP/Contents/Helpers/shopdeck-mcp"
cp "$TASK_BIN/shopdeck-keychain" "$TASK_APP/Contents/Helpers/shopdeck-keychain"
mkdir -p "$TASK_APP/Contents/Frameworks"
ditto "$TASK_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$TASK_APP/Contents/Frameworks/Sparkle.framework"
for TASK_RESOURCE in "$TASK_BIN"/*.bundle; do
  [ -d "$TASK_RESOURCE" ] || continue
  ditto "$TASK_RESOURCE" "$TASK_APP/Contents/Resources/$(basename "$TASK_RESOURCE")"
done
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Shopdeck</string>
<key>CFBundleIdentifier</key><string>app.shopdeck.mac</string>
<key>CFBundleName</key><string>Shopdeck</string>
<key>CFBundleDisplayName</key><string>Shopdeck</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>app.shopdeck.mac</string><key>CFBundleURLSchemes</key><array><string>shopdeck</string></array></dict></array>
<key>CFBundleDevelopmentRegion</key><string>de</string>
<key>CFBundleLocalizations</key><array><string>de</string><string>en</string><string>nl</string><string>es</string><string>fr</string><string>it</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
TASK_VERSION="$(awk -F '"' '/public static let current/ { print $2 }' "$TASK_ROOT/Sources/ShopdeckCore/AppVersion.swift")"
TASK_BUILD="$(python3 -c 'import sys; a,b,c=map(int,sys.argv[1].split(".")); print(a*1000000+b*1000+c)' "$TASK_VERSION")"
plutil -replace CFBundleVersion -string "$TASK_BUILD" "$TASK_APP/Contents/Info.plist"
plutil -insert SUFeedURL -string "${SHOPDECK_UPDATE_FEED_URL:-https://github.com/sthamann/shopdeck/releases/latest/download/appcast.xml}" "$TASK_APP/Contents/Info.plist"
if [ -f "$TASK_ROOT/Assets/UpdatePublicKey.txt" ]; then plutil -insert SUPublicEDKey -string "$(cat "$TASK_ROOT/Assets/UpdatePublicKey.txt")" "$TASK_APP/Contents/Info.plist"; fi
plutil -insert SUEnableAutomaticChecks -bool YES "$TASK_APP/Contents/Info.plist"
plutil -insert UTExportedTypeDeclarations -json '[{"UTTypeIdentifier":"app.shopdeck.sidebar-reference","UTTypeConformsTo":["public.data"],"UTTypeDescription":"Shopdeck sidebar item"}]' "$TASK_APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$TASK_VERSION" "$TASK_APP/Contents/Info.plist"
if [ -f "$TASK_ROOT/Assets/AppIcon.icns" ]; then cp "$TASK_ROOT/Assets/AppIcon.icns" "$TASK_APP/Contents/Resources/AppIcon.icns"; fi
rm -f "$TASK_APP/Contents/Resources/Sparkle-LICENSE.txt"
install -m 644 "$TASK_ROOT/Assets/Sparkle-LICENSE.txt" "$TASK_APP/Contents/Resources/Sparkle-LICENSE.txt"
install -m 644 "$TASK_ROOT/Assets/ThirdPartyNotices.txt" "$TASK_APP/Contents/Resources/ThirdPartyNotices.txt"
if [ "${SHOPDECK_SKIP_WIDGETS:-0}" != "1" ]; then "$TASK_ROOT/script/build_widgets.sh" "$TASK_APP"; fi
xattr -cr "$TASK_APP"
codesign --force --options runtime --sign "$TASK_IDENTITY" --identifier app.shopdeck.keychain "$TASK_APP/Contents/Helpers/shopdeck-keychain"
codesign --force --options runtime --sign "$TASK_IDENTITY" --identifier app.shopdeck.mcp "$TASK_APP/Contents/Helpers/shopdeck-mcp"
TASK_FRAMEWORK="$TASK_APP/Contents/Frameworks/Sparkle.framework"
for TASK_NESTED in "$TASK_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" "$TASK_FRAMEWORK/Versions/B/XPCServices/Installer.xpc" "$TASK_FRAMEWORK/Versions/B/Updater.app" "$TASK_FRAMEWORK/Versions/B/Autoupdate"; do
 [ ! -e "$TASK_NESTED" ] || codesign --force --sign "$TASK_IDENTITY" --options runtime "$TASK_NESTED"
done
codesign --force --sign "$TASK_IDENTITY" --options runtime "$TASK_FRAMEWORK"
codesign --force --options runtime --sign "$TASK_IDENTITY" --identifier app.shopdeck.mac --entitlements "$TASK_ROOT/Widgets/App.entitlements" "$TASK_APP"
xattr -cr "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
case "$MODE" in
 --build-only) ;;
 --verify) open -n "$TASK_APP"; sleep 2; pgrep -x Shopdeck >/dev/null ;;
 --demo) open -n "$TASK_APP" --args --demo ;;
 --debug) lldb -- "$TASK_APP/Contents/MacOS/Shopdeck" ;;
 --logs) open -n "$TASK_APP"; /usr/bin/log stream --info --style compact --predicate 'process == "Shopdeck"' ;;
 --telemetry) open -n "$TASK_APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.shopdeck.mac"' ;;
 run) open -n "$TASK_APP" ;;
 *) echo "Usage: $0 [--build-only|--verify|--demo|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
