# Fastlane Setup for SimpleSimulatorManager

This document describes how to set up and use Fastlane for building and signing the SimpleSimulatorManager macOS app for distribution outside the Mac App Store.

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
# Copy the template and edit with your values
cp .env.template .env

# Edit .env with your Apple Developer credentials
# DO NOT commit this file to git
```

Fill in your `.env` file with:
- `FASTLANE_USER`: Your Apple ID email
- `FASTLANE_TEAM_ID`: Your Apple Developer Team ID
- `MATCH_PASSWORD`: A secure password for encrypting certificates

### 3. Update Appfile

Edit `fastlane/Appfile` and replace:
- `your-apple-id@example.com` with your Apple ID
- `YOUR_TEAM_ID` with your Apple Developer Team ID

### 4. Create Certificates (First Time Only)

⚠️ **Important**: Only run this command once, and only if you don't already have Developer ID certificates.

```bash
fastlane create_certificates
```

This will:
- Create a new Developer ID certificate
- Store it in your signing repository
- Install it on your machine

## Building the App

### Quick Build

For a simple build and sign:

```bash
fastlane build
```

### Full Release Build

For a complete release with ZIP files:

```bash
fastlane release
```

This will create:
- `release/SimulatorManager.zip` - ZIP archive for GitHub releases

## Lanes Available

- `fastlane build` - Build and sign the app
- `fastlane setup_signing` - Download and install certificates
- `fastlane create_certificates` - Create new certificates (first time only)
- `fastlane release` - Build and prepare files for GitHub release

## Signing Repository

Your certificates are stored in: https://github.com/Heckscheibe/SimpleSimulatorManagerSigning

This repository contains:
- Developer ID certificates (encrypted)
- Provisioning profiles
- Match metadata

## Troubleshooting

### Certificate Issues

If you encounter certificate issues:

```bash
# Re-download certificates
fastlane setup_signing

# Or force update certificates
fastlane setup_signing --force
```

### Build Issues

1. Ensure your Xcode project builds successfully in Xcode first
2. Check that the scheme "SimulatorManager" exists and is shared
3. Verify your Apple Developer account is active

### Match Password

If you forget your match password:
1. You'll need to revoke and recreate all certificates
2. Run `fastlane create_certificates --force`

## Security Notes

- Never commit your `.env` file
- Keep your match password secure
- The signing repository is private and encrypted
- Only team members should have access to the signing repository

## GitHub Release Workflow

After running `fastlane release`:

1. Files will be in the `release/` directory
2. Create a new release on GitHub
3. Upload `SimulatorManager.dmg` and `SimulatorManager.zip`
4. Users can download and install the DMG directly

## Distribution Notes

Since this app is distributed outside the Mac App Store:
- It's signed with a Developer ID certificate
- Users may see a security warning on first launch
- Users should right-click → Open to bypass Gatekeeper
- No notarization is performed (as noted, sandbox is disabled)
