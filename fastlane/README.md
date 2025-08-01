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

### mac build

```sh
[bundle exec] fastlane mac build
```

Build and sign the app for distribution outside Mac App Store

### mac setup_signing

```sh
[bundle exec] fastlane mac setup_signing
```

Setup certificates and provisioning profiles

### mac create_certificates

```sh
[bundle exec] fastlane mac create_certificates
```

Create a new certificate (run this only once)

### mac release

```sh
[bundle exec] fastlane mac release
```

Build and prepare for GitHub release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
