# Releasing mac4DSTEM

The repository can build and audit an unsigned/ad-hoc Release without private
credentials. Public distribution additionally requires the release owner’s Apple
Developer Program membership, a **Developer ID Application** certificate, and
notary-service credentials. Those secrets do not belong in the repository.

## Release contract

- Bundle identifier: `com.mac4dstem.mac4DSTEM`
- Version/build: `3.0.0` / `6`, shipped 2026-09-11. Previously `2.5.1` / `5` (2026-09-04; v2.5.0 was `2.5` / `4` the same day, build 3 its superseded 2026-09-03 artefact). A driven bug cuts v3.0.x, a landed science number v3.1.0 (`docs/decisions/007-versioning-and-release-naming.md`). v2.0.0 was named 2026-09-02, never built, superseded by v2.5.0
- Minimum system: **macOS 27** (`MACOSX_DEPLOYMENT_TARGET = 27.0`,
  `Package.swift: .macOS("27.0")`, raised from 14 on 2026-09-22 —
  `decisions.md` 008). Published as the requirement it is; development and
  testing are on 27. v3.0.0's artefact (floor 14) stays downloadable for
  older systems — the raise gates only releases after it
- **Apple Silicon only, and the artefact must prove it.** The three embedded
  HDF5 libraries are arm64-only and `Core/ML/LearnedDiskDetector.swift` uses
  `Float16`, which does not exist on x86_64 macOS. `ARCHS = arm64` at project
  level does **not** reach the SwiftPM package targets where every `Core/` and
  `Session/` source is compiled, so the pin travels on the xcodebuild command
  line — spelled once in `tools/lib/release-arch.sh`, which both
  `build-developer-id.sh` and `tools/package-test/run.sh` source. Both assert
  `lipo -archs` = `arm64` on the built executable and every embedded dylib,
  because a setting can be dropped and a product cannot argue. v2.5.1 shipped
  universal against arm64-only HDF5 and is broken on Intel (`docs/open-items.md`)
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

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | named 2026-09-02, never built, superseded by v2.5.0; a local tag exists on this machine and was never pushed, and none will be (C0 (4), `decisions.md` 2026-09-07) | `CHANGELOG.md` |
| v3.0.0 | **released 2026-09-11**, version/build 3.0.0 / 6 — the learned disk detector, the flat/file probe kernel, and the first build that is arm64 alone. Built from `3c4b82c` with `Developer ID Application: Paul Lobpreis (3B8SMSSAX4)`; app notarization `e9a64b93-c63f-462f-a423-fa2ef56eeb31`, DMG `5205d722-712c-4c5a-bbbc-35d117dbb0f7`, both **Accepted** and stapled, `spctl` accepted on both, `source=Notarized Developer ID`. DMG SHA-256 `cf2259a3016db7d32f9805db724b358cf23b153bab2d547839dcd9e9bd651b89`, **5 030 916 bytes** — *smaller* than v2.5.1's 6 157 051 because the Intel slice is gone. Verified by mounting the image: the app inside is `arm64` alone across the executable and all three embedded dylibs, 3.0.0 (6), `LSMinimumSystemVersion 14.0`, `LICENSE` and `NOTICE` both present, stapled ticket validates. **Record the post-staple hash, not the one `make-dmg.sh` prints** — stapling rewrites the image, and the pre-staple hash was `95b53779…fb1e`. Gated on `all` exit 0 (46 harnesses, 573/0/2 = 575) and `inventory` exit 0 on the same tree. Known limitations are stated in `CHANGELOG.md` rather than left to be found | `CHANGELOG.md` |
| v2.5.1 | released 2026-09-04, version/build 2.5.1 / 5 — macOS floor down to 14 and the sidecar-reader fix. Artefact built from `a9a0437`; app notarization `fb693c50`, DMG `f3d05e79`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `30282206…31af`, 6 157 051 bytes; the app inside the image declares `LSMinimumSystemVersion 14.0`, verified by mounting it. First release able to claim `run-tests.sh all` exit 0 (458/0/0, 44 harnesses). v2.5.0's artefact cannot launch below macOS 26, so this is the build that reaches older systems | `CHANGELOG.md` |
| v2.5.0 | released 2026-09-04, version/build 2.5 / 4 — the first shipped build of the SwiftUI rebuild. Gated on `unit` (457/0/0) + `package-test`, both exit 0; **`run-tests.sh all` was attempted and exited 1** on a pre-existing sidecar defect (`open-items.md`), and the notes say so. Artefact: built from `3c0a3eb`, app notarization `af7cc0f4`, DMG notarization `f4aa1d12`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `d55821a1…4c75`, 6 074 038 bytes. Build 3 (`df80e8e`) is superseded, kept as `mac4DSTEM-2.5-build3-superseded.dmg` | `CHANGELOG.md` |

The release night of 2026-09-04 (plan, two self-corrections, artefact provenance) is [`archive/v2/release-2026-09-04.md`](archive/v2/release-2026-09-04.md).

## Before using credentials

Run the complete gate from the repository root:

```sh
tools/run-tests.sh all
```

This includes XCTest, the scientific/source-locked harnesses, and an ad-hoc
hardened Release package audit. The `real-data-acceptance` step needs the
gitignored `References/training_dataset` acquisitions: without them it cannot
run, which is why CI does not.

### v3.1.0 readiness — 2026-09-19

The last `all` attempt was clean until it correctly refused before unit/package: `Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5`, `downsample_Si_SiGe_exp.h5`, and `calibrationData_bullseyeProbe.h5` were missing from `tools/real-data-acceptance/expected.json`. **They were never off this disk: the 09-17 run executed in a worktree whose gitignored `References/` lacked them (birth times July/August 2026, checked 2026-09-21).** `all` ran green on the main checkout 2026-09-21 (`all-v310-20260921.log`, exit 0, `docs/status.md` § Last gates): all five pinned cubes measured and matched. Do not waive/shrink the set. Next: silence the `App/AppState+Promote.swift:26` warning and bump 3.0.0 / 6 → 3.1.0 / 7 (owner's number), re-run `all` on the bumped tree, rehearse the archive, then the credentialed cut.

**A green `all` did NOT mean the archive builds, and now it does — 2026-09-11.**
The gate's `package-test` built `-destination 'platform=macOS'`, the concrete
machine, while `build-developer-id.sh` builds `generic/platform=macOS`; the
archive compiled an x86_64 slice and failed an hour after `all` went green, on
19 diagnostics of which 7 are `'Float16' is unavailable in macOS` and the rest
downstream of them (counted from the log; the entry that first recorded this
said "20, all Float16" and was wrong on both halves). `package-test` now builds the same generic destination with
the same pin, so the gate covers the archive's configuration. Run the archive
early anyway — it is local, reversible, needs no notary credentials, and is
still the step most likely to fail:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: … (TEAMID)'
tools/release/build-developer-id.sh
```

Failing it early costs nothing; failing it after notarization costs a
submission.

**Rehearse the archive without a certificate first.** Until 2026-09-11 the
`archive` action's first exercise of the day was a credentialed release, which
is how a broken archive was discovered with the certificate already in hand.
This needs no secrets and takes the same path:

```sh
. tools/lib/release-arch.sh
xcodebuild archive -project mac4DSTEM.xcodeproj -scheme mac4DSTEM \
  -configuration Release -destination "$MAC4DSTEM_RELEASE_DESTINATION" \
  -archivePath /tmp/rehearsal.xcarchive "$MAC4DSTEM_ARCH_PIN" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= archive
assert_mac4dstem_bundle_arm64_only \
  /tmp/rehearsal.xcarchive/Products/Applications/mac4DSTEM.app
```

A single word `arm64` from `lipo` on the Mach-Os inside the `.xcarchive` is the
proof that the artefact is Apple-Silicon-only. `-showBuildSettings` printing
`ARCHS = arm64` is **not** proof and never was: that setting was already true
while the archive was building Intel.

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
runs Gatekeeper assessment, and produces `mac4DSTEM-<version>.zip`. Preserve the archive,
notary submission ID/log, commit hash, and final SHA-256 together as release
provenance. Test the ZIP on a clean account before publishing. The floor is
macOS 27, matching this machine, so a clean-account test here covers the
floor with no VM gap.

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
target embeds `libhdf5.dylib`, `libsz.2.dylib`, and `libaec.0.dylib` in
`Contents/Frameworks`; Xcode signs each nested library with the app identity.

Run the credential-free release audit before archiving:

```sh
tools/package-test/run.sh
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
