# Fastlane Setup for SimpleSimulatorManager

This document describes the current Fastlane workflow for building and signing the SimpleSimulatorManager macOS app for Developer ID distribution outside the Mac App Store.

## Prerequisites

1. **Apple Developer Account**: You need a paid Apple Developer account
2. **Developer ID Certificate**: For signing apps distributed outside the Mac App Store, managed via [fastlane match](https://docs.fastlane.tools/actions/match/)
3. **Access to the certificates repo**: [Heckscheibe/simplesimulatormanager-certificates](https://github.com/Heckscheibe/simplesimulatormanager-certificates) (private) — this is where match stores the encrypted certificate and provisioning profile; you need read access via git (SSH) plus the shared `MATCH_PASSWORD` to decrypt them
4. **Ruby**: the version pinned in [.ruby-version](.ruby-version) (currently 4.0.6). macOS's pre-installed Ruby is not sufficient — see [Install Ruby](#1-install-ruby) below
5. **Xcode Command Line Tools**: Install with `xcode-select --install`
6. **GitHub CLI** (`brew install gh`, then `gh auth login`) with push access to this repo: the release lane creates the GitHub release with your own login, so no token goes into `.env`
7. **Claude Code** (`claude` on your `PATH`, signed in): the release lane uses `claude -p` to write the release notes. Set `CLAUDE_CLI` to use a different binary and `RELEASE_NOTES_MODEL` to pick a model

## Initial Setup

### 1. Install Ruby

The Ruby version is pinned in `.ruby-version` at the repository root. Every version
manager (rbenv, rvm, mise, asdf, chruby) reads that file, so the right interpreter is
selected automatically once it is installed:

```bash
# rbenv
rbenv install "$(cat .ruby-version)"

# rvm
rvm install "$(cat .ruby-version)"

# mise
mise install ruby@"$(cat .ruby-version)"
```

Homebrew's `ruby` formula also works if it happens to be on the pinned version, but it
is not version-managed — you have to put `$(brew --prefix ruby)/bin` on your `PATH`
yourself, and it moves whenever the formula updates.

Confirm the right Ruby is active before continuing:

```bash
ruby -v   # must match .ruby-version
```

Do not use the Ruby that ships with macOS, and do not `sudo gem install` anything: the
system Ruby is deprecated by Apple and installing gems into it needs root and breaks on
OS updates.

### 2. Install Dependencies

Bundler ships with the pinned Ruby, so there is nothing to install first:

```bash
bundle install
```

### 3. Configure Environment Variables

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

### 4. Signing Assets (via match)

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
- create `release/SimulatorManager-<version>.zip` from the stapled app bundle with `ditto` (see
  [Sparkle appcast](#sparkle-appcast-and-the-eddsa-key)), and check that the app extracted from it still
  passes `codesign --verify --deep --strict` and `spctl -a -vvv -t install`
- write the release notes (see [GitHub Release Workflow](#github-release-workflow))
- ask you to confirm the version and notes, then create the GitHub release and upload the ZIP
- only after the release was published: regenerate the signed `appcast.xml` and push it to `develop`, and bump and push the Homebrew cask

The checks that can fail cheaply — `gh` login, `claude` on the `PATH`, `v<version>` not yet existing — run before the build starts.

## Lanes Available

- `fastlane mac build` - Build and sign the macOS app for Developer ID distribution
- `fastlane mac release` - Set the release version, build the app, notarize it, create the versioned ZIP, write the release notes, publish the GitHub release after confirmation, then publish the signed appcast and bump the Homebrew cask
- `fastlane mac release_notes` - Write `release/RELEASE_NOTES-<version>.md` only (options: `version`, `target`, `previous_tag`)
- `fastlane mac github_release` - Confirm and publish the GitHub release for an already built `release/SimulatorManager-<version>.zip` (options: `version`, `target`, `previous_tag`, `regenerate:true`, `dry_run:true`)
- `fastlane mac generate_appcast version:X.Y.Z` - Add `release/SimulatorManager-X.Y.Z.zip` to the archive and regenerate `release/appcast.xml` (also run by `release`)
- `fastlane mac publish_appcast version:X.Y.Z` - Commit `release/appcast.xml` to `develop`, where the app looks for it; asks you to confirm the GitHub release is live unless called by `release`
- `fastlane mac update_signing_assets` - One-time/maintenance: push the Developer ID certificate/profile via match to the certs repo (needs push access to [simplesimulatormanager-certificates](https://github.com/Heckscheibe/simplesimulatormanager-certificates)); can't create a brand-new certificate — see below

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

`bundle exec fastlane mac release` publishes the GitHub release itself, after the build and before the appcast is published and the Homebrew cask is bumped (both point at the release asset, so the asset has to exist first).

**Release notes.** They keep the style of GitHub's auto-generated notes. The `* <PR title> by @<author> in <PR url>` lines and the `Full Changelog` link come verbatim from GitHub's `generate-notes` API for the range *latest release → target commit*. Claude reads each PR's title, body and labels and returns a category and a user-facing summary of at most three sentences; the lane groups the entries under **Features**, **Improvements** and **Bugfixes** (in that order, empty groups omitted) and indents the summary under its entry. Claude gets no tools and the PR text is passed as data. The result is saved as `release/RELEASE_NOTES-<version>.md`; the lane warns about a missing summary or one over three sentences.

**Confirmation.** Before anything is uploaded the lane prints the repository, the tag `v<version>` and the commit it will point at, the ZIP and its size, and the full notes, then asks:

1. *Publish* — creates the release `<version>` (tag `v<version>`, marked latest) and uploads `SimulatorManager-<version>.zip`
2. *Edit release notes* — opens the file in `$VISUAL`/`$EDITOR` (default: TextEdit; use `code --wait` style commands for editors that return immediately), then shows the prompt again
3. *Cancel* — uploads nothing and leaves the Homebrew cask and the appcast untouched

**The tag points at `HEAD`** (override with `target:<branch-or-sha>`), which must be pushed. The release lane bumps the version in the working tree without committing it, so the lane warns when the tree is dirty: commit and push the bump first if the tagged commit should contain it.

**Resuming.** If you cancel or the upload fails, nothing else has changed. Run `bundle exec fastlane mac github_release version:X.Y.Z` (reuses the saved notes, `regenerate:true` rewrites them; `dry_run:true` shows the `gh release create` command without running it), then `bundle exec fastlane mac generate_appcast version:X.Y.Z`, `bump_homebrew_cask version:X.Y.Z` and `publish_appcast version:X.Y.Z`.

## Sparkle appcast and the EdDSA key

The app updates itself from `appcast.xml`, served from
`https://raw.githubusercontent.com/Heckscheibe/SimpleSimulatorManager/develop/appcast.xml`
(`SUFeedURL` in `SimulatorManager/Info.plist`). It lives at the root of **`develop`**, the default
branch, so every release adds an `Appcast for X.Y.Z` commit there. `publish_appcast` makes that commit
through a temporary worktree of `origin/develop`, so the checkout you release from can be on any branch.
If `develop` rejects the push (a protected branch), push `release/appcast.xml` there by hand or re-run
`fastlane mac publish_appcast version:X.Y.Z`. `raw.githubusercontent.com` caches for a few minutes, so a
fresh feed can take that long to show up. Until the first Sparkle release has published one, the feed
URL returns 404 and "Check for Updates" reports a download error.

What `release` does for it:

1. Copies the ZIP into the archive directory (`../simulator-manager-releases` next to this checkout;
   override with `APPCAST_ARCHIVE_PATH`). `generate_appcast` needs the earlier ZIPs to produce a correct
   feed, so **keep this directory** — it is outside the repo on purpose.
2. Writes `SimulatorManager-<version>.html` beside it: the release notes shown in the update window,
   converted from `release/RELEASE_NOTES-<version>.md`. Point `RELEASE_NOTES_FILE` at an HTML file to
   write them by hand; without any notes file the commit subjects since the last tag are listed.
3. Runs Sparkle's `generate_appcast --maximum-deltas 0` (no delta assets to upload). It signs each
   entry and takes `sparkle:version` from `CFBundleVersion` (the **build** number),
   `sparkle:shortVersionString` from `CFBundleShortVersionString` and
   `sparkle:minimumSystemVersion` from `LSMinimumSystemVersion`. The tool comes from the Sparkle
   package Xcode already resolved; set `SPARKLE_BIN` to use another copy.

The ZIP is made with `ditto -c -k --sequesterRsrc --keepParent`, not fastlane's `zip` action: that
one resolves symlinks instead of storing them, which breaks `Sparkle.framework/Versions/Current`
and with it the code signature.

### The EdDSA key

Updates are signed with an EdDSA key pair made by Sparkle's `generate_keys`. The **private key lives
in the maintainer's login Keychain** (item "Private key for signing Sparkle updates"); the public key
is `SUPublicEDKey` in `Info.plist`. Releases are cut locally, so the key never leaves that Mac.

- Never commit the private key. If you export it (`generate_keys -x <file>`), keep that file outside
  the repo — `*.sparkle-private-key` is git-ignored as a backstop.
- Back it up (for example into a password manager) with `generate_keys -x`, and restore it on a new
  Mac with `generate_keys -f <file>`.
- **If the key is lost it cannot be recovered.** A new key pair means new `SUPublicEDKey`, and no
  installed copy will accept an update signed with it: every existing install has to be updated by
  hand once (download from Releases, or `brew reinstall`). Later updates then work again.

## Distribution Notes

Since this app is distributed outside the Mac App Store:

- It's signed with a Developer ID certificate
- The release ZIP contains a stapled notarized app bundle
- Gatekeeper should accept the app without the old notarization warning, assuming signing credentials remain valid

### Embedded MCP server

The app bundle carries a second executable, the MCP server, at
`Simulator Manager.app/Contents/Helpers/simple-simulator-mcp`. It is built by the
`simple-simulator-mcp` command line tool target and copied in by the app target's
"Embed MCP Server" phase with Code Sign On Copy, so it is signed with the same Developer ID identity
and notarized as part of the app. The target uses hardened runtime and no entitlements, so it needs
no provisioning profile of its own. `SKIP_INSTALL = YES` keeps it out of the archive's top level,
leaving the app as the only exported product, and the `export_options` in the `build` lane only map
the app's identifier.

After a release build, check the helper:

```bash
codesign -dv --verbose=4 "build/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp"
```

The output should show `Authority=Developer ID Application: …`, `flags=0x10000(runtime)` and
`Identifier=com.nicolashiller.SimpleSimulatorManager.mcp`. If the export ever complains about a
missing provisioning profile for the helper, add its bundle identifier to `export_options` rather than
giving it entitlements.

The Homebrew cask exposes the helper on the `PATH` with a `binary` stanza pointing at
`#{appdir}/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp`.
