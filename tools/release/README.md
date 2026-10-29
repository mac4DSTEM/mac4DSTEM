# Releasing mac4DSTEM

The repository can build and audit an unsigned/ad-hoc Release without private
credentials. Public distribution additionally requires the release owner’s Apple
Developer Program membership, a **Developer ID Application** certificate, and
notary-service credentials. Those secrets do not belong in the repository.

## Release contract

- Bundle identifier: `com.mac4dstem.mac4DSTEM`
- Version/build: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Xcode project. Every released version, with its evidence, is in the Releases table below and in `CHANGELOG.md`. A driven bug cuts a patch release, a landed science number a minor, a raised system floor or a rebuilt interface a major
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

App tags carry a `v` (`v5.0.1`); the kits and MacEMUI use bare versions (`0.9.0`). From v5.0.0 on, each release's notes
and assets are on the [GitHub releases page](https://github.com/mac4DSTEM/mac4DSTEM/releases) and its entry in
`CHANGELOG.md`; the table keeps the earlier releases' build evidence.

| Version | State | Evidence |
|---|---|---|
| v5.0.1 | released 2026-10-23 (tag `v5.0.1` on `63106e4`) | GitHub release, `CHANGELOG.md` |
| v5.0.0 | released 2026-10-23 (tag `v5.0.0` on `b86bbe0`) | GitHub release, `CHANGELOG.md` |
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | named 2026-09-02, never built, superseded by v2.5.0; never tagged on GitHub | `CHANGELOG.md` |
| v4.5.0 | **released 2026-10-05** (GitHub release 12:50 UTC, marked Latest; tag `v4.5.0` on `6432f2dd`; assets `mac4DSTEM-4.5.0.dmg` and `mac4DSTEM.dmg`, both digest `sha256:2b779090…53b4d6`; `releases/latest/download/mac4DSTEM.dmg` downloaded and hashed identical; mac4dstem.com deployed `eea3358` 12:52 UTC) — version/build 4.5.0 / 8, the v4.1 plateau released as it stands; the unpublished 4.1.0 / 8 cut renamed. Built from `6432f2dd` with `Developer ID Application: Paul Lobpreis (3B8SMSSAX4)` by Xcode 27.0 (27A266a); app notarization `e9720976-f35d-4abe-9e88-8cea02f04232`, DMG `193f2b56-9cd8-426c-905f-8562df224978`, both Accepted and stapled, Gatekeeper "Notarized Developer ID"; DMG SHA-256 `2b7790901f5f8016b4a8e9fc3ea96f7b9e8e8ff8696debc94537e703b153b4d6` (post-staple; pre-staple `f13b8a19…aa63`), 6 059 725 bytes; the mounted app 4.5.0 (8), `LSMinimumSystemVersion` 27.0, arm64 alone with its three dylibs, LICENSE and NOTICE present, launched (alive 15 s, no crash report; no analysis run in it). Gate: `run-tests.sh all` exit 0 on `6432f2dd` (`all-v45b-20261005.log`: unit 1675/0/3 = 1678, 54 sections, zero FAIL lines). Superseded: the `286a45ed` build (notarized, never distributed; a Swift 6 isolation warning fixed in `6432f2dd`). Not done: a clean-account launch. | `CHANGELOG.md` |
| v4.0.0 | **released 2026-09-23**, version/build 4.0.0 / 7 — the macOS 27 floor (a major), the rebuilt interface and the v3.1 calibration foundation. Built from `1b76c98` with `Developer ID Application: Paul Lobpreis (3B8SMSSAX4)` by Xcode-beta against the macOS 27 SDK; app notarization `baa5506e-8208-4811-b05e-459e338b4ee0`, DMG `57b226d3-e6ea-47e0-8572-e41195d716b5`, both Accepted and stapled, Gatekeeper "Notarized Developer ID"; DMG SHA-256 `9948a5d028dcb470a4f060ddd6188d21b1825ae6c3acfa1f4699de8a3999a117` (post-staple; pre-staple `53e55aaa…`), 5 415 560 bytes; the mounted app 4.0.0 (7), `LSMinimumSystemVersion` 27.0, arm64 alone with its three dylibs. Gate: `run-tests.sh all` exit 0 on `1b76c98` (`all-v4-20260922.log`, 50 harnesses, zero FAIL lines, unit 860/0/1 = 861). Not done: a clean-account launch. | `CHANGELOG.md` |
| v3.0.0 | **released 2026-09-11**, version/build 3.0.0 / 6 — the learned disk detector, the flat/file probe kernel, and the first build that is arm64 alone. Built from `3c4b82c` with `Developer ID Application: Paul Lobpreis (3B8SMSSAX4)`; app notarization `e9a64b93-c63f-462f-a423-fa2ef56eeb31`, DMG `5205d722-712c-4c5a-bbbc-35d117dbb0f7`, both **Accepted** and stapled, `spctl` accepted on both, `source=Notarized Developer ID`. DMG SHA-256 `cf2259a3016db7d32f9805db724b358cf23b153bab2d547839dcd9e9bd651b89`, **5 030 916 bytes** — *smaller* than v2.5.1's 6 157 051 because the Intel slice is gone. Verified by mounting the image: the app inside is `arm64` alone across the executable and all three embedded dylibs, 3.0.0 (6), `LSMinimumSystemVersion 14.0`, `LICENSE` and `NOTICE` both present, stapled ticket validates. **Record the post-staple hash, not the one `make-dmg.sh` prints** — stapling rewrites the image, and the pre-staple hash was `95b53779…fb1e`. Gated on `all` exit 0 (46 harnesses, 573/0/2 = 575) and `inventory` exit 0 on the same tree. Known limitations are stated in `CHANGELOG.md` rather than left to be found | `CHANGELOG.md` |
| v2.5.1 | released 2026-09-04, version/build 2.5.1 / 5 — macOS floor down to 14 and the sidecar-reader fix. Artefact built from `a9a0437`; app notarization `fb693c50`, DMG `f3d05e79`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `30282206…31af`, 6 157 051 bytes; the app inside the image declares `LSMinimumSystemVersion 14.0`, verified by mounting it. First release able to claim `run-tests.sh all` exit 0 (458/0/0, 44 harnesses). v2.5.0's artefact cannot launch below macOS 26, so this is the build that reaches older systems | `CHANGELOG.md` |
| v2.5.0 | released 2026-09-04, version/build 2.5 / 4 — the first shipped build of the SwiftUI rebuild. Gated on `unit` (457/0/0) + `package-test`, both exit 0; **`run-tests.sh all` was attempted and exited 1** on a pre-existing sidecar defect, and the notes say so. Artefact: built from `3c0a3eb`, app notarization `af7cc0f4`, DMG notarization `f4aa1d12`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `d55821a1…4c75`, 6 074 038 bytes. Build 3 (`df80e8e`) is superseded, kept as `mac4DSTEM-2.5-build3-superseded.dmg` | `CHANGELOG.md` |

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

## Before using credentials

Run the complete gate from the repository root:

```sh
tools/run-tests.sh all
```

This includes XCTest, the scientific/source-locked harnesses, and an ad-hoc
hardened Release package audit. The `real-data-acceptance` step needs the
gitignored `References/training_dataset` acquisitions: without them it cannot
run, which is why CI does not.

### v4.0.0 release lessons — 2026-09-23

- **Rename or copy the archive before re-running `build-developer-id.sh`.**
  The script starts with `rm -rf "$ARCHIVE"` on
  `build/release/mac4DSTEM.xcarchive`: a second run for any reason (a
  DMG rebuild, a notarization retry from scratch) destroys the archive the
  first run produced with no warning.
- **`DEVELOPER_ID_APPLICATION` is not just `build-developer-id.sh`'s** — `make-dmg.sh` also
  requires it (it signs the mounted image), so export it once and run every
  release script in the same shell; a fresh terminal for the DMG step fails
  on the same unset-variable guard.
- **Pushing `main`, tagging the release and pushing the tag are three
  separate steps, done by hand after the gate, the archive and notarization**
  (GitHub Desktop does not push tags).
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
