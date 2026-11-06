# Releasing mac4DSTEM

The repository can build and audit an unsigned/ad-hoc Release without private
credentials. Public distribution additionally requires the release owner’s Apple
Developer Program membership, a **Developer ID Application** certificate, and
notary-service credentials. Those secrets do not belong in the repository.

## Release contract

- Bundle identifier: `com.mac4dstem.mac4DSTEM`
- Version/build: `MARKETING_VERSION` in `Config/Version.xcconfig` (release-please bumps it in each Release PR; `tools/release.sh` refuses a tag it does not match) / `CURRENT_PROJECT_VERSION` in the Xcode project. Every released version, with its evidence, is in the Releases table below and in `CHANGELOG.md`. A driven bug cuts a patch release, a landed science number a minor, a raised system floor or a rebuilt interface a major
- Minimum system: **macOS 26** (`MACOSX_DEPLOYMENT_TARGET = 26.0`,
  `Package.swift: .macOS(.v26)`; raised from 14 to 27 on 2026-09-22, lowered to 26 on 2026-10-28). Published as the
  requirement it is; development is on 27, CI builds and tests on 26. v3.0.0's artefact (floor 14) stays downloadable for
  older systems — the raise gates only releases after it
- **Apple Silicon only, and the artefact must prove it.** The three embedded
  HDF5 libraries are arm64-only and `Core/ML/LearnedDiskDetector.swift` uses
  `Float16`, which does not exist on x86_64 macOS. `ARCHS = arm64` at project
  level does **not** reach the SwiftPM package targets where every `Core/` and
  `Session/` source is compiled, so the pin travels on the xcodebuild command
  line — spelled once in `tools/lib/release-arch.sh`, which both
  `build-developer-id.sh` and `tools/harnesses/package-test/run.sh` source. Both assert
  `lipo -archs` = `arm64` on the built executable and every embedded dylib,
  because a setting can be dropped and a product cannot argue. v2.5.1 shipped
  universal against arm64-only HDF5 and is broken on Intel
- Hardened runtime and App Sandbox enabled
- User-selected read/write access plus app-scoped security bookmarks
- HDF5, sz, and aec libraries embedded and nested-signed. Their load commands
  carry no absolute path — `@rpath`, `@loader_path` and `/usr/lib` only, held
  by `run-tests.sh inventory` since 2026-09-09. "Free of Homebrew paths" was
  too strong: `libhdf5.dylib` still contains two Homebrew *strings*, the build
  stamp and HDF5's compiled-in default plugin search path
  `/opt/homebrew/Cellar/hdf5/2.1.1/lib/plugin`. Neither affects linking or
  signing; the second means that on a machine which happens to have that path,
  HDF5 would search it for filter plugins. `NOTICE` records the binaries' hashes

## Releases

App tags carry a `v` (`v5.2.0`); the kits and MacEMUI use bare versions (`0.9.0`). Each release's notes and assets are on the
[GitHub releases page](https://github.com/mac4DSTEM/mac4DSTEM/releases) and in `CHANGELOG.md`; release-please opens the Release PR,
Paul merges it, the bot tags, and `tools/release.sh` builds the DMG from the tag (below).


## One run: `tools/release.sh`

`tools/release.sh` does the whole credentialed release in one run, on a Mac
with the certificate: it archives with `build-developer-id.sh`, notarizes and
staples the app with `notarize.sh`, builds the DMG with `make-dmg.sh`, then
notarizes and staples the DMG. It needs a clean working tree, the
**Developer ID Application** certificate in the login keychain
(`DEVELOPER_ID_APPLICATION` overrides the name), a `notarytool` keychain
profile (default `macem-notary`, `NOTARY_PROFILE` overrides it) and `dmgbuild`
in `build/dmg-venv`. Each run writes a new folder
`build/release/<date-time>/` holding the archive, `mac4DSTEM-<version>.dmg`
and a byte-identical `mac4DSTEM.dmg` for the
`releases/latest/download/mac4DSTEM.dmg` link, and prints the DMG's SHA-256
and size. It pushes and uploads nothing. The sections below describe the
same steps one at a time.

## App Store package: `tools/release.sh --store`

One tag, two builds (decision of 2026-11-04). From the same checked-out release tag, `tools/release.sh --store` runs
`tools/release/build-app-store.sh`: a Release archive with automatic signing under team 3B8SMSSAX4 and
`MACEM_STORE_BUILD=YES` (the switch that leaves the Sparkle updater out), then `xcodebuild -exportArchive` with
`ExportOptions-AppStore.plist` (`method = app-store-connect`, `destination = export`). It checks the product: installer
signature, sandbox on, no `get-task-allow`, a privacy manifest in every bundle, the export-compliance key, arm64 only, no
Sparkle. Output: `build/release/<stamp>/store/mac4DSTEM.pkg`.

- First run: Xcode must be signed in to the team's Apple ID; `-allowProvisioningUpdates` lets it create the Apple
  Distribution and Mac Installer Distribution certificates and the App Store profiles (app, two Quick Look extensions,
  HDF5 helper).
- Validate and upload need an App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, the `.p8` in
  `~/.appstoreconnect/private_keys/`. With the key, `--store` validates; `--store --upload` validates and uploads.
  Without it the run stops after the checks.
- A second upload of the same version needs a new build number: `STORE_BUILD_NUMBER=2 tools/release.sh --store --upload`.

### The App Store submission, as it ran for 5.2.0 (2026-11-06)

Two channels from one tag: the notarized DMG on the GitHub release and mac4dstem.com, and the Mac App Store. Both are
built in the same checkout of the release tag, so they carry the same source and version.

App Store Connect record: bundle ID `com.mac4dstem.mac4DSTEM`, Apple ID 6831377995, SKU `mac4dstem-macos`; free in all
territories; Education, secondary Productivity; age rating 4+; App Privacy "Data Not Collected"; manual release after
approval. The listing texts and every other field are in `docs/app-store/`.

1. Merge the Release PR; release-please tags `vX.Y.Z` and writes the GitHub release.
2. Check out the tag in its own worktree and run `tools/release.sh`; verify the DMG (`xcrun stapler validate`,
   `spctl -a -t open --context context:primary-signature -v`, the version, SHA-256) and attach
   `mac4DSTEM-X.Y.Z.dmg` and `mac4DSTEM.dmg` to the GitHub release.
3. In the same worktree run `tools/release.sh --store --upload`. The release owner starts the first run, since it
   creates the distribution certificates on the account. The upload needs an App Store Connect team API key (role
   App Manager); the account must have API access enabled under Users and Access > Integrations first. The key file
   stays in `~/.appstoreconnect/private_keys/`; the key, its ID and the issuer ID never go into the repository, an
   issue or a log.
4. Wait until Apple has processed the build (`xcrun altool --build-status --delivery-id <uuid> --wait`, with the
   delivery UUID the upload printed), then select it on the version page. The build declares no non-exempt encryption,
   so no export-compliance question follows.
5. Fill the version page from `docs/app-store/`, add the screenshots and App Previews, set each preview's poster
   frame once Apple has processed it, then Add for Review and Submit for Review.
6. After approval, release the version by hand in App Store Connect.

5.2.0: tag `v5.2.0`; DMG 17 740 505 bytes, SHA-256 `488a2ca60fac99ab3323655a6ad2fada679614b29e9bcb978d5c5457e515c797`;
store build 5.2.0 (10), uploaded and submitted on 2026-11-06.

Lessons: `altool --validate-app` took 12 minutes, so run it in the background; App Store Connect refuses screenshots
with an alpha channel and previews without an audio track; nothing on the command line waits for preview processing.
Not done before submitting: a drive of the store build itself (checked instead: the source at the tag, and sandbox
entitlements equal to the DMG build's).

## Before using credentials

Run the complete gate from the repository root:

```sh
tools/run-tests.sh all
```

This includes XCTest, the scientific/source-locked harnesses, and an ad-hoc
hardened Release package audit. The `real-data-acceptance` step needs the
gitignored `References/training_dataset` acquisitions: without them it cannot
run, which is why CI does not.

### Lessons that still apply

- `build-developer-id.sh` starts with `rm -rf "$ARCHIVE"` on `build/release/mac4DSTEM.xcarchive`: copy the archive before a second run.
- `make-dmg.sh` also requires `DEVELOPER_ID_APPLICATION` (it signs the mounted image): export it once and run every release script in the same shell.
- **The GitHub release carries the DMG twice** — `mac4DSTEM-<version>.dmg` and a byte-identical
  `mac4DSTEM.dmg`: mac4dstem.com links `releases/latest/download/mac4DSTEM.dmg`, so the release must be
  marked latest and carry that exact asset name, and the website is pushed only after it is published.

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

Store credentials once with `xcrun notarytool store-credentials` (the scripts default to the profile name `macem-notary`;
an Apple ID with an app-specific password works; a 403 "required agreement is missing" means the Developer Program License Agreement
awaits acceptance at developer.apple.com/account), then:

```sh
export NOTARY_PROFILE=macem-notary
tools/release/notarize.sh \
  build/release/mac4DSTEM.xcarchive/Products/Applications/mac4DSTEM.app
```

The script submits with `notarytool --wait`, staples and validates the ticket,
runs Gatekeeper assessment, and produces `mac4DSTEM-<version>.zip`. Preserve the archive,
notary submission ID/log, commit hash, and final SHA-256 together as release
provenance: a release is written to `build/release/`; keep it outside the repository once
published, since it cannot be regenerated. Test the ZIP on a clean account before publishing. The floor is
macOS 27, so a clean-account test on a macOS 27 Mac covers the floor with no
VM gap.

## The disk image users actually download

`tools/release/make-dmg.sh` was missing from this document until 2026-08-28,
which meant the one artefact users actually download had no written procedure.

```sh
tools/release/make-dmg.sh \
  build/release/mac4DSTEM.xcarchive/Products/Applications/mac4DSTEM.app
```

**Order matters, and getting it wrong produces a download that fails on first
launch with no network.** Take a *stapled* app, build the DMG from it, then run
`notarize.sh` **again on the DMG**: the image is signed by `make-dmg.sh` but not
notarized there. Stapling the app alone is not enough — Gatekeeper assesses the
thing the user actually opened, which is the image.

The window layout is written straight into the image's `.DS_Store` by
`dmgbuild`, deliberately not by driving the Finder with AppleScript: the
AppleScript recipe is the common one and it does not survive automation, since
it needs an Automation grant and a live Finder.

Apple’s required process is Developer ID signing with hardened runtime, a secure
timestamp, notarization, and ticket stapling; `altool` is no longer supported.

## Distribution and notarization

*(merged from `distribution.md`, 2026-09-02)*

The project now produces a self-contained, hardened, sandboxed macOS app. The
target carries libhdf5, libsz and libaec as FormatoKit's frameworks `FormatoLibHDF5`, `FormatoLibSZ` and `FormatoLibAEC`
(`Contents/Frameworks/<Name>.framework`, arm64; the repo and the project embed none of their own since 2026-10-15). Since FormatoKit 0.4.0
Xcode embeds them and signs them with the app's identity (ad hoc in the audit, Developer ID in the archive), so Hardened Runtime accepts them.

Run the credential-free release audit before archiving:

```sh
tools/harnesses/package-test/run.sh
```

This clean-builds an ad-hoc Release app, verifies the nested code signatures,
relative HDF5 dependency closure, sandbox/read-write/bookmark entitlements and
absence of `get-task-allow`, then opens a checked-in HDF5 fixture using only the
library inside the app bundle. It does not claim Developer ID signing or Apple
notarization.

## Credentialed release

The release owner must supply:

- an Apple Developer Program team and stable production bundle identifier;
- a **Developer ID Application** certificate in the signing keychain;
- a `notarytool` keychain profile (or equivalent App Store Connect API key);
- final version/build numbers and a ZIP, DMG, or PKG distribution container.

Preferred workflow: `tools/release/build-developer-id.sh`, then
`tools/release/notarize.sh`. **Do not archive from Xcode's Organizer.** It has
no way to carry the command-line architecture pin, so it builds the SwiftPM
package targets for `ARCHS_STANDARD` and produces exactly the universal binary
v2.5.1 shipped — or, since `Float16` arrived, simply fails to compile. The
Organizer route was this document's recommendation until 2026-09-11 and is the
most likely explanation for how v2.5.1 became universal.
For automation, export a Developer ID-signed archive, create a notarization ZIP
with `ditto -c -k --keepParent`, submit it with
`xcrun notarytool submit --keychain-profile PROFILE --wait`, and staple the
accepted ticket to the app or DMG with `xcrun stapler staple`.

Apple requires Developer ID signing, Hardened Runtime, a secure timestamp, and
no `get-task-allow` entitlement for notarization. See Apple’s
[notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Sandboxed file access

Dataset and export URLs come from system Open/Save panels. A session sidecar’s
first save also uses a Save panel, defaulted beside the source dataset, and the
app stores an app-scoped security bookmark for later atomic updates and reopen.
This explicit grant is necessary because selecting a source file does not grant
blanket access to every sibling in its directory.
