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

One-time/maintenance: push the Developer ID certificate + profile to the match storage repo. Uses the App Store Connect API key, so no Apple ID/password login or 2FA prompt. NOTE: Apple blocks *creating* a brand-new Developer ID Application certificate via API key entirely (Account Holder only) — this lane can renew/re-push what's already in the certs repo, or push a profile fetched/created for an existing certificate, but a genuinely new certificate has to be created interactively and imported via `fastlane match import`. See FASTLANE_README.md for the full walkthrough.

### mac build

```sh
[bundle exec] fastlane mac build
```

Build and sign the macOS app for Developer ID distribution

### mac release

```sh
[bundle exec] fastlane mac release
```

Set the release version, build, notarize and zip the app, write the release notes with Claude, publish the GitHub release after confirmation, then bump the Homebrew cask

### mac release_notes

```sh
[bundle exec] fastlane mac release_notes
```

Write the GitHub release notes for a version: GitHub's generated pull request list grouped into features, improvements and bugfixes, each with a short summary written by Claude. Options: version, target (commit/branch, default HEAD), previous_tag (default latest release)

### mac github_release

```sh
[bundle exec] fastlane mac github_release
```

Create the GitHub release v<version> from release/SimulatorManager.zip after confirming version and notes. Reuses release/RELEASE_NOTES-<version>.md if present (regenerate:true to rewrite). Options: version, target, previous_tag, regenerate, dry_run. Returns whether it was published

### mac bump_homebrew_cask

```sh
[bundle exec] fastlane mac bump_homebrew_cask
```

Update and push the Homebrew cask (version + sha256) for a given release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
