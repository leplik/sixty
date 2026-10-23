#!/usr/bin/env bash
# Builds build/Sixty.app.
#   VERSION        version string (default: version.txt)
#   BUILD_NUMBER   CFBundleVersion (default: 1)
#   UNIVERSAL=1    arm64 + x86_64 binary (release builds)
#   SIGN_IDENTITY  codesign identity (default: "-", ad-hoc, for local use)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat version.txt)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Sixty.app"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/Sixty"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Sixty"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN" "$APP/Contents/MacOS/Sixty"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/pro.saac.sixty.agent.plist "$APP/Contents/Library/LaunchAgents/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Library/LaunchAgents/pro.saac.sixty.agent.plist" > /dev/null

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER, identity $SIGN_IDENTITY)"
