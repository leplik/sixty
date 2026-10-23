# Releasing

Releases are automatic. You merge pull requests with Conventional Commit titles; release-please does the rest.

```
merge to main ──▶ release-please updates the release PR (version + CHANGELOG)
merge the release PR ──▶ tag vX.Y.Z + GitHub Release
                     └─▶ build job: test → universal build → Developer ID signature
                                    → DMG → notarize → staple → upload DMG + ZIP
                                    → update Casks/sixty.rb in leplik/homebrew-tap
```

- `feat:` raises the minor version, `fix:` the patch version. Before 1.0.0, a breaking change also raises only the minor version.
- Installed copies update themselves within 12 hours: they read `releases/latest` and download `Sixty-<version>.zip`. Keep that asset name.
- The website deploys separately (`pages.yml`) when `site/**` changes on `main`.

## One-time setup

### GitHub repository

1. Settings → Pages → Source: **GitHub Actions**.
2. Settings → Actions → General → Workflow permissions: **Read and write**, and allow GitHub Actions to create pull requests (release-please needs it).

### Secrets (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | The "Developer ID Application" certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set for the `.p12` export |
| `APPLE_ID` | For notarization: the Apple ID of a team member (Developer role or higher). Used when there is no API key |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID: appleid.apple.com → Sign-In and Security → App-Specific Passwords |
| `ASC_KEY_ID` | Optional, instead of the Apple ID: App Store Connect → Users and Access → Integrations → Team Keys: the key ID. Only the Account Holder can enable API access for the team |
| `ASC_ISSUER_ID` | The issuer ID on the same page |
| `ASC_KEY_P8_BASE64` | The downloaded `AuthKey_<id>.p8`, then `base64 -i AuthKey_<id>.p8 \| pbcopy` |
| `HOMEBREW_TAP_DEPLOY_KEY` | Private half of an SSH deploy key with write access to `leplik/homebrew-tap` only. Create: `ssh-keygen -t ed25519 -N '' -f k`, `gh repo deploy-key add k.pub -R leplik/homebrew-tap --allow-write`, `gh secret set HOMEBREW_TAP_DEPLOY_KEY -R leplik/sixty < k`, delete `k` |

Never paste these values into a terminal command or a chat. Pipe them to the clipboard as shown.

### Homebrew tap

The tap `leplik/homebrew-tap` already exists and holds other casks. The release job writes only `Casks/sixty.rb` (from `packaging/sixty.rb`) and pushes with the deploy key.

## Local release build

```sh
SIGN_IDENTITY="Developer ID Application: SAAC sp. z o.o. (JVW2N74WL3)" UNIVERSAL=1 VERSION=0.1.0 scripts/build-app.sh
VERSION=0.1.0 scripts/package-release.sh   # notarizes only if ASC_* variables are set
```

## Mac App Store

App: "Sixty — Move Every Hour", Apple ID `6826310117`, bundle ID `pro.saac.sixty.mas`, SKU `sixty-mas`, team SAAC (`JVW2N74WL3`, provider public ID `a9ee9ba6-fcc9-451a-ac55-1e1734c8a244`). The App Store edition is built and uploaded from a Mac, not from CI.

Already set up (2026-10-23): certificates "Apple Distribution: SAAC sp. z o.o." and "3rd Party Mac Developer Installer: SAAC sp. z o.o." in the login keychain, App ID `pro.saac.sixty.mas`, profile "Sixty Mac App Store" (expires 2027-10-23), the app record with listing, screenshots, age rating, "Data Not Collected", free in all regions. Listing texts: `packaging/appstore/metadata/en/`; screenshots: `packaging/appstore/screenshots/en/` (`make media`).

Upload password: an app-specific password of `dev@saac.pro`, stored as the generic keychain item `SIXTY_ALTOOL`. `altool --store-password-in-keychain-item` fails on Xcode 26 ("Expected item argument is missing"), and `-p @keychain:` does not find items made by `security`, so the password goes through an environment variable:

```sh
security add-generic-password -U -s SIXTY_ALTOOL -a dev@saac.pro -w   # once; prompts for the password
```

Each version (raise `VERSION`; the build number is a timestamp):

```sh
APP_SIGN_IDENTITY="Apple Distribution: SAAC sp. z o.o. (JVW2N74WL3)" \
INSTALLER_IDENTITY="3rd Party Mac Developer Installer: SAAC sp. z o.o. (JVW2N74WL3)" \
PROFILE=~/Downloads/Sixty_Mac_App_Store.provisionprofile \
VERSION=0.1.1 scripts/build-appstore.sh

BV=$(plutil -extract CFBundleVersion raw build/appstore/Sixty.app/Contents/Info.plist)
ALTOOL_PW="$(security find-generic-password -s SIXTY_ALTOOL -a dev@saac.pro -w)" \
xcrun altool --upload-package build/appstore/Sixty-0.1.1.pkg --type macos \
  --apple-id 6826310117 --bundle-id pro.saac.sixty.mas \
  --bundle-version "$BV" --bundle-short-version-string 0.1.1 \
  --provider-public-id a9ee9ba6-fcc9-451a-ac55-1e1734c8a244 \
  -u dev@saac.pro -p @env:ALTOOL_PW
```

Then App Store Connect → the version page: set the same version number, pick the processed build, "Add for Review".

Traps:
- Error 91109 "com.apple.quarantine": a profile downloaded with a browser is quarantined. `build-appstore.sh` clears all extended attributes before signing.
- `plutil -insert` reads dots in a key as nesting; entitlement keys are escaped in the script.
- The App Store version number must equal the build's `CFBundleShortVersionString`.

Review notes: `packaging/appstore/metadata/en/review_notes.txt`.
