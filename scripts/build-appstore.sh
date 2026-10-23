#!/usr/bin/env bash
# Builds the Mac App Store edition: build/appstore/Sixty.app and, if signing identities are given, a signed .pkg.
#   VERSION              version string (default: version.txt)
#   BUILD_NUMBER         CFBundleVersion; must grow with every upload (default: date +%Y%m%d%H%M)
#   APP_SIGN_IDENTITY    "Apple Distribution: …" (default: "-", ad-hoc, for a local sandbox test)
#   INSTALLER_IDENTITY   "3rd Party Mac Developer Installer: …" or "Mac Installer Distribution: …"
#   PROFILE              path to the Mac App Store provisioning profile for pro.saac.sixty.mas
#   TEAM_ID              team of the profile (default: JVW2N74WL3)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat version.txt)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
TEAM_ID="${TEAM_ID:-JVW2N74WL3}"
BUNDLE_ID="pro.saac.sixty.mas"
OUT="build/appstore"
APP="$OUT/Sixty.app"

# A separate build folder, so the GitHub edition's build is never mixed with this one.
swift build -c release --arch arm64 --arch x86_64 --scratch-path .build-appstore -Xswiftc -DAPP_STORE
BIN=".build-appstore/apple/Products/Release/Sixty"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sixty"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# No Contents/Library/LaunchAgents: the App Store edition uses a normal login item.

ENTITLEMENTS="$OUT/Sixty.entitlements"
cp Resources/Sixty-AppStore.entitlements "$ENTITLEMENTS"
if [[ -n "${PROFILE:-}" ]]; then
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  # plutil reads dots as nesting, so they are escaped.
  plutil -insert 'com\.apple\.application-identifier' -string "$TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
  plutil -insert 'com\.apple\.developer\.team-identifier' -string "$TEAM_ID" "$ENTITLEMENTS"
fi
plutil -lint "$APP/Contents/Info.plist" "$ENTITLEMENTS" > /dev/null

codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$APP_SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$OUT/Sixty-$VERSION.pkg"
  echo "Built $OUT/Sixty-$VERSION.pkg"
fi
echo "Built $APP (version $VERSION, build $BUILD_NUMBER, identity $APP_SIGN_IDENTITY)"
