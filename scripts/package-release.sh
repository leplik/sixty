#!/usr/bin/env bash
# Packs build/Sixty.app into Sixty-<version>.dmg and .zip, then notarizes the DMG and staples the ticket
# to the DMG and to the app (one notarization covers both). Credentials, first match wins:
#   ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_P8_BASE64     App Store Connect API key
#   APPLE_ID + APPLE_APP_PASSWORD (+ TEAM_ID)          Apple ID with an app-specific password
# Without credentials it skips notarization, unless REQUIRE_NOTARIZATION=1 (release builds), then it fails.
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

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  KEY="$STAGE/AuthKey.p8"
  echo "$ASC_KEY_P8_BASE64" | base64 --decode > "$KEY"
  AUTH=(--key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  AUTH=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "${TEAM_ID:-JVW2N74WL3}")
fi

if [[ ${#AUTH[@]} -gt 0 ]]; then
  RESULT="$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --output-format json)"
  echo "$RESULT"
  if [[ "$(echo "$RESULT" | jq -r .status)" != "Accepted" ]]; then
    xcrun notarytool log "$(echo "$RESULT" | jq -r .id)" "${AUTH[@]}" || true
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
elif [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  echo "No notarization credentials (APPLE_ID + APPLE_APP_PASSWORD or ASC_KEY_*): refusing to ship an un-notarized release." >&2
  exit 1
else
  echo "No notarization credentials: skipping notarization."
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$DMG" "$ZIP"
