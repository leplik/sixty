#!/usr/bin/env bash
# Writes Casks/sixty.rb in the tap repo for the new version and pushes it. Touches no other cask.
# Needs VERSION and HOMEBREW_TAP_DEPLOY_KEY: the private half of a deploy key with write access
# to the tap repo only (least privilege: no personal token in CI).
set -euo pipefail
cd "$(dirname "$0")/.."

TAP_REPO="${TAP_REPO:-leplik/homebrew-tap}"
DMG="build/Sixty-$VERSION.dmg"
SHA256="$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/deploy_key"
printf '%s\n' "$HOMEBREW_TAP_DEPLOY_KEY" > "$KEY"
chmod 600 "$KEY"
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

git clone --depth 1 "git@github.com:${TAP_REPO}.git" "$WORK/tap"
mkdir -p "$WORK/tap/Casks"
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$SHA256/" packaging/sixty.rb > "$WORK/tap/Casks/sixty.rb"

cd "$WORK/tap"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Casks/sixty.rb
if git diff --cached --quiet; then
  echo "Cask already up to date."
  exit 0
fi
git commit -m "sixty $VERSION"
git push
