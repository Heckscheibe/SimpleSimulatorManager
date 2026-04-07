# Fastlane Setup for SimpleSimulatorManager

This document describes the current Fastlane workflow for building and signing the SimpleSimulatorManager macOS app for Developer ID distribution outside the Mac App Store.

## Prerequisites

1. **Apple Developer Account**: You need a paid Apple Developer account
2. **Developer ID Certificate**: For signing apps distributed outside the Mac App Store
3. **Ruby**: Fastlane requires Ruby (usually pre-installed on macOS)
4. **Xcode Command Line Tools**: Install with `xcode-select --install`

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

- `CODESIGNING_IDENTITY`: Your Developer ID Application signing identity
- `PROVISIONING_PROFILE_NAME`: The provisioning profile name for `com.nicolashiller.SimpleSimulatorManager`
- `APP_STORE_CONNECT_API_KEY_KEY_ID`: App Store Connect API key identifier
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`: App Store Connect API issuer identifier
- `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`: Absolute path to the `.p8` private key file used for notarization

Use this template for your `.env` file:

```bash
# Fastlane signing configuration
CODESIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
PROVISIONING_PROFILE_NAME="SimpleSimulatorManager Developer ID"

# Required notarization authentication
APP_STORE_CONNECT_API_KEY_KEY_ID="ABC123XYZ"
APP_STORE_CONNECT_API_KEY_ISSUER_ID="00000000-0000-0000-0000-000000000000"
APP_STORE_CONNECT_API_KEY_KEY_FILEPATH="/absolute/path/to/AuthKey_ABC123XYZ.p8"
```

### 3. Install Signing Assets

Before running Fastlane, make sure these assets are already available on your machine:

- A valid Developer ID Application certificate in your keychain
- A provisioning profile matching `com.nicolashiller.SimpleSimulatorManager`
- App Store Connect API key credentials, including the `.p8` private key file

The current repository does not define certificate management lanes such as `setup_signing` or `create_certificates`. Signing assets must be prepared outside this Fastlane configuration.

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

## Troubleshooting

### Certificate Issues

If you encounter certificate issues:

1. Verify that your Developer ID certificate is installed in Keychain Access.
2. Verify that the provisioning profile name in `.env` matches the profile used for `com.nicolashiller.SimpleSimulatorManager`.
3. Confirm that `CODESIGNING_IDENTITY` exactly matches the identity shown by the system.

### Build Issues

1. Ensure your Xcode project builds successfully in Xcode first
2. Check that the scheme "SimulatorManager" exists and is shared
3. Verify that your `.env` file is present in the repository root
4. Verify that your signing certificate and provisioning profile are installed locally
5. Verify that the placeholder values in `.env` have been replaced with your real signing details

### Notarization Issues

If notarization fails:

1. Verify `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`
2. Confirm that the `.p8` key file exists at the configured path
3. Check that the API key has access to the developer account used for notarization
4. Check the fastlane output for the notarization log, which is printed on failure and on successful runs with warnings

## Security Notes

- Never commit your `.env` file
- Keep your signing identity details private
- Limit access to signing certificates and provisioning profiles

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
