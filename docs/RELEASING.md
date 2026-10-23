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
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → Team Keys: the key ID (role "Developer" is enough) |
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
