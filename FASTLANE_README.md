# Fastlane Setup for SimpleSimulatorManager

This document describes the current Fastlane workflow for building and signing the SimpleSimulatorManager macOS app for Developer ID distribution outside the Mac App Store.

## Prerequisites

1. **Apple Developer Account**: You need a paid Apple Developer account
2. **Developer ID Certificate**: For signing apps distributed outside the Mac App Store, managed via [fastlane match](https://docs.fastlane.tools/actions/match/)
3. **Access to the certificates repo**: [Heckscheibe/simplesimulatormanager-certificates](https://github.com/Heckscheibe/simplesimulatormanager-certificates) (private) — this is where match stores the encrypted certificate and provisioning profile; you need read access via git (SSH) plus the shared `MATCH_PASSWORD` to decrypt them
4. **Ruby**: Fastlane requires Ruby (usually pre-installed on macOS)
5. **Xcode Command Line Tools**: Install with `xcode-select --install`

## Initial Setup

### 1. Install Dependencies

```bash
# Install bundler if you don't have it
sudo gem install bundler

# Install fastlane and dependencies
bundle install
```

### 2. Configure Environment Variables

```bash
# Create a .env file in the repository root
# DO NOT commit this file to git
```

The current Fastfile reads these values from the environment:

- `MATCH_PASSWORD`: Decrypts the certificate/profile stored in the [simplesimulatormanager-certificates](https://github.com/Heckscheibe/simplesimulatormanager-certificates) repo. Ask a maintainer for this — it's a shared secret, not something you generate yourself
- `APP_STORE_CONNECT_API_KEY_KEY_ID`: App Store Connect API key identifier
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`: App Store Connect API issuer identifier
- `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`: Absolute path to the `.p8` private key file — used for both notarization and to authenticate `match` against the Apple Developer Portal (no Apple ID/password login, no 2FA prompt)

Use this template for your `.env` file:

```bash
# Fastlane signing configuration (decrypts the match storage repo)
MATCH_PASSWORD="ask-a-maintainer-for-this"

# Required App Store Connect authentication (notarization + match)
APP_STORE_CONNECT_API_KEY_KEY_ID="ABC123XYZ"
APP_STORE_CONNECT_API_KEY_ISSUER_ID="00000000-0000-0000-0000-000000000000"
APP_STORE_CONNECT_API_KEY_KEY_FILEPATH="/absolute/path/to/AuthKey_ABC123XYZ.p8"
```

### 3. Signing Assets (via match)

Certificate and provisioning profile management is handled by [fastlane match](https://docs.fastlane.tools/actions/match/) — no manual Keychain Access setup, no per-machine provisioning profile installs.

- **Building** (`fastlane mac build` / `fastlane mac release`) automatically fetches and decrypts the Developer ID certificate and provisioning profile from the certs repo and installs them into your local keychain. You only need `MATCH_PASSWORD` and SSH access to the certs repo — nothing needs to be pre-installed.
- **Rotating or (re-)creating** the certificate/profile — e.g. after the cert expires, or when setting up match for the first time — is a separate, occasional maintenance lane:

  ```bash
  bundle exec fastlane mac update_signing_assets
  ```

  This authenticates with the App Store Connect API key (same as notarization), so it doesn't prompt for an Apple ID login. Note: **creating** a brand-new Developer ID Application certificate via API key is blocked by Apple ("only the Account Holder can perform this operation") — that's an Apple Developer Portal restriction, not something this project can work around. If you ever need a genuinely new certificate rather than a renewal, an Account Holder has to create it via `fastlane cert` (or the web UI) while logged in interactively, then `fastlane match import` it into the certs repo. Apple has also been seen rejecting **provisioning profile** creation via API key on some accounts/roles ("check with your Team Admins") — if `update_signing_assets` hits that, either grant the API key Admin access in App Store Connect → Users and Access → Integrations, or download the existing profile from [developer.apple.com/account/resources/profiles/list](https://developer.apple.com/account/resources/profiles/list) and bring it in with `fastlane match import` instead of letting match generate a new one.
- Only maintainers with push access to the certs repo can run `update_signing_assets`; everyone else only ever needs read-only `match` fetches, which happen automatically as part of `build`.

## Building the App

### Quick Build

For a simple build and sign:

```bash
bundle exec fastlane mac build
```

### Full Release Build

For a complete release with ZIP files:

```bash
bundle exec fastlane mac release
```

This will:

- build and sign the app
- notarize and staple the app with Apple
- create `release/SimulatorManager.zip` from the stapled app bundle

## Lanes Available

- `fastlane mac build` - Build and sign the macOS app for Developer ID distribution
- `fastlane mac release` - Set the release version, build the app, notarize it, create the ZIP, and open the release folder
- `fastlane mac update_signing_assets` - One-time/maintenance: fetch or create the Developer ID certificate/profile via match and push them to the certs repo (needs push access to [simplesimulatormanager-certificates](https://github.com/Heckscheibe/simplesimulatormanager-certificates))

## Troubleshooting

### Certificate/match Issues

If you encounter signing issues:

1. Verify `MATCH_PASSWORD` is set correctly in `.env` — a wrong password fails to decrypt the certs repo with a clear error.
2. Verify you have SSH access to `git@github.com:Heckscheibe/simplesimulatormanager-certificates.git` (`git ls-remote` that URL to check).
3. If `fastlane mac build` reports match didn't return a certificate/profile, someone with access needs to run `fastlane mac update_signing_assets` first to populate the certs repo.
4. Don't try to install the Developer ID certificate or provisioning profile manually into Keychain Access / `~/Library/MobileDevice/Provisioning Profiles/` — match handles that automatically on every build.

### Build Issues

1. Ensure your Xcode project builds successfully in Xcode first
2. Check that the scheme "SimulatorManager" exists and is shared
3. Verify that your `.env` file is present in the repository root
4. Verify that `MATCH_PASSWORD` and the App Store Connect API key values in `.env` are correct (see Certificate/match Issues above)
5. Verify that the placeholder values in `.env` have been replaced with your real signing details

### Notarization Issues

If notarization fails:

1. Verify `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`
2. Confirm that the `.p8` key file exists at the configured path
3. Check that the API key has access to the developer account used for notarization
4. Check the fastlane output for the notarization log, which is printed on failure and on successful runs with warnings

## Security Notes

- Never commit your `.env` file
- Never commit `MATCH_PASSWORD`, exported `.p12`/`.cer`/provisioning profile files, or the App Store Connect `.p8` key to this repo — the certs repo (`simplesimulatormanager-certificates`) is the only place encrypted signing assets should live
- Limit access to the certs repo and to `MATCH_PASSWORD` to people who need to build releases

## GitHub Release Workflow

After running `bundle exec fastlane mac release`:

1. Files will be in the `release/` directory
2. Create a new release on GitHub
3. Upload `SimulatorManager.zip`
4. Users can download the ZIP and move the app into their Applications folder

## Distribution Notes

Since this app is distributed outside the Mac App Store:

- It's signed with a Developer ID certificate
- The release ZIP contains a stapled notarized app bundle
- Gatekeeper should accept the app without the old notarization warning, assuming signing credentials remain valid
