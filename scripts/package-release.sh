#!/usr/bin/env bash
# Packs build/Sixty.app into Sixty-<version>.dmg and .zip.
# If ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8_BASE64 are set, it notarizes the DMG
# and staples the ticket to the DMG and to the app (one notarization covers both).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat version.txt)}"
APP="build/Sixty.app"
DMG="build/Sixty-$VERSION.dmg"
ZIP="build/Sixty-$VERSION.zip"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Sixty" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${ASC_KEY_ID:-}" ]]; then
  KEY="$STAGE/AuthKey.p8"
  echo "$ASC_KEY_P8_BASE64" | base64 --decode > "$KEY"
  RESULT="$(xcrun notarytool submit "$DMG" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --output-format json)"
  echo "$RESULT"
  if [[ "$(echo "$RESULT" | jq -r .status)" != "Accepted" ]]; then
    xcrun notarytool log "$(echo "$RESULT" | jq -r .id)" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
else
  echo "ASC_KEY_ID is not set: skipping notarization."
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$DMG" "$ZIP"
