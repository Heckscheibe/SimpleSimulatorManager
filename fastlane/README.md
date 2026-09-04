fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac update_signing_assets

```sh
[bundle exec] fastlane mac update_signing_assets
```

One-time/maintenance: fetch or create the Developer ID profile via match and push it (plus the certificate) to the match storage repo. Uses the App Store Connect API key, so no Apple ID/password login or 2FA prompt.

### mac build

```sh
[bundle exec] fastlane mac build
```

Build and sign the macOS app for Developer ID distribution

### mac release

```sh
[bundle exec] fastlane mac release
```

Set the release version, build the app, create the ZIP, and open the release folder

### mac bump_homebrew_cask

```sh
[bundle exec] fastlane mac bump_homebrew_cask
```

Update and push the Homebrew cask (version + sha256) for a given release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
