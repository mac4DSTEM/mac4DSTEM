# Releasing mac4DSTEM v1

The repository can build and audit an unsigned/ad-hoc Release without private
credentials. Public distribution additionally requires the release owner’s Apple
Developer Program membership, a **Developer ID Application** certificate, and
notary-service credentials. Those secrets do not belong in the repository.

## Release contract

- Bundle identifier: `com.paullobpreis.mac4DSTEM`
- Version/build: `1.0` / `1`
- Minimum system: macOS 14
- Hardened runtime and App Sandbox enabled
- User-selected read/write access plus app-scoped security bookmarks
- HDF5, sz, and aec libraries embedded, nested-signed, and free of Homebrew paths

## Before using credentials

Run the complete gate from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/run-tests.sh all
```

This includes XCTest, scientific/source-locked harnesses, the checked-in real-data
goldens and time budget, and an ad-hoc hardened Release package audit.

## Developer ID archive

Install the certificate in the login keychain, then use its full name:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
tools/release/build-developer-id.sh
```

The command archives with a secure timestamp, validates nested signatures and
entitlements, and writes `build/release/mac4DSTEM.xcarchive`. Do not distribute the
pre-notarization ZIP.

## Notarize and staple

Store credentials once with `xcrun notarytool store-credentials`, then:

```sh
export NOTARY_PROFILE=mac4dstem-notary
tools/release/notarize.sh \
  build/release/mac4DSTEM.xcarchive/Products/Applications/mac4DSTEM.app
```

The script submits with `notarytool --wait`, staples and validates the ticket,
runs Gatekeeper assessment, and produces `mac4DSTEM-1.0.zip`. Preserve the archive,
notary submission ID/log, commit hash, and final SHA-256 together as release
provenance. Test the ZIP on a clean macOS 14+ account before publishing.

Apple’s required process is Developer ID signing with hardened runtime, a secure
timestamp, notarization, and ticket stapling; `altool` is no longer supported.
