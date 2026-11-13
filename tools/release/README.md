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

## Updates in the download: Sparkle (#122)

The website DMG updates itself with Sparkle 2 (mac4DSTEM > Check for Updates…, `App/SoftwareUpdate.swift`); the App Store
build has no updater, because the store updates it and refuses an app that updates itself. Decided 2026-11-11:

- **One switch.** `MACEM_STORE_BUILD` (NO unless the store script sets YES) picks `Info.plist` or `Info-Direct.plist`,
  `mac4DSTEM.entitlements` or `mac4DSTEM-Direct.entitlements`, and the `SPARKLE` compile condition. The store build links
  with `-dead_strip_dylibs` (the three HDF5 frameworks kept with `-needed_framework`, because FormatoKit opens them by path
  and dead-stripping dropped their load commands too) and its last build phase removes the framework Xcode embeds for the package, so the store app
  has no Sparkle code, load command, plist key or entitlement exception; `build-app-store.sh` checks all four.
  `SoftwareUpdateTests` holds each Direct file to be its store twin plus exactly the updater's keys: edit `Info.plist`
  and copy the change to `Info-Direct.plist`.
- **Sandboxed.** The installer launcher service (`SUEnableInstallerLauncherService`) with its mach-lookup exception;
  no downloader service, because the app already has `network.client`. No system profile; Sparkle asks the person on the
  second launch before it checks by itself (daily).
- **Feed on the website**, `https://mac4dstem.com/appcast/mac4dstem.xml`: one URL that outlives the GitHub organisation's
  name. `tools/release.sh` writes it (`tools/release/appcast.sh`, one item: the new DMG on the GitHub release, its EdDSA
  signature, the CHANGELOG section as plain text), and it is committed to the website as `appcast/mac4dstem.xml` in the
  PR that sets the download's version and size.
- **Build number = version** in the download (`CURRENT_PROJECT_VERSION` set from `Config/Version.xcconfig` by
  `build-developer-id.sh`), because Sparkle compares `sparkle:version` with `CFBundleVersion`; the store build keeps
  the project's build number.
- **Signing.** `build-developer-id.sh` signs Sparkle's helpers (Installer.xpc, Downloader.xpc, Autoupdate,
  Updater.app) and the framework with the Developer ID, inside out, then the app again keeping its entitlements, and
  checks each one before notarization.

**The key.** `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` (there after one `tools/release.sh` or any
build that resolves the packages into `build/SourcePackages`) makes the EdDSA pair, keeps the private half in the login
keychain and prints the public half, which goes under `SUPublicEDKey` in `mac4DSTEM/Info-Direct.plist` (it is public; it
may be committed and pasted). Back the private half up at once (Keys and backups, below). A lost key is not the end of
updates: Sparkle accepts an update with a new key when the new app meets the old app's designated requirement
(`SUUpdateValidator.m`: "Either DSA must be valid, or Apple Code Signing must be valid"), and ours is Xcode's default,
which names the team (`certificate leaf[subject.OU] = 3B8SMSSAX4`), not the certificate. So a new key needs a release
signed with a Developer ID of the same team, carrying the new public key, its feed entry signed with the new private
key. Never change the key and the team in one release. Until a real key is in, the updater stays off and
`build-developer-id.sh` refuses to build a download.

## Keys and backups (#285)

The release needs four secrets on Paul's Mac. None is in a repo, an issue, a chat, a log or a GitHub secret (the CI
workflows sign nothing; the only Actions secret is release-please's app key).

| Secret | Lives in | Used by | Made with |
|---|---|---|---|
| Developer ID Application: Paul Lobpreis (3B8SMSSAX4), certificate and private key | login keychain | `build-developer-id.sh`, `make-dmg.sh`, macEM `tools/release.sh` | Xcode > Settings > Apple Accounts, the Account Holder's Apple Account > Manage Certificates > + > Developer ID Application |
| notarytool profile `macem-notary` | login keychain | `notarize.sh`, macEM `tools/release.sh` | `xcrun notarytool store-credentials macem-notary --key ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"` |
| Sparkle EdDSA private key | login keychain | `appcast.sh` (`sign_update`) | `generate_keys` (above) |
| App Store Connect API key `.p8` | `~/.appstoreconnect/private_keys/`, `ASC_KEY_ID` and `ASC_ISSUER_ID` in `~/.zshrc` | store upload, the notary profile | App Store Connect > Users and Access > Integrations; Apple shows the file once |

The store's Apple Distribution and Mac Installer Distribution certificates need nothing kept: Xcode signed in to the team
creates them on the first `--store` run (`-allowProvisioningUpdates`).

**Only the Account Holder** (the Apple Account that enrolled the membership; App Store Connect > Users and Access names
it) can create a Developer ID certificate, in Xcode or on developer.apple.com. An Admin gets "This operation can only be
performed by the Account Holder". A team may hold five Developer ID Application certificates at once.

**Never revoke a Developer ID certificate that signed a published download.** Apple: an app signed with a revoked
certificate "can no longer be installed nor launch if it's already installed". A certificate whose key is lost is left
to expire; the apps it signed keep working.

**Backup, the same day a secret is made, in two places outside every repo** (13 Nov 2026 the login keychain was reset
and the only copies were lost):

1. Export the Developer ID identity: Keychain Access > login > My Certificates > the Developer ID entry > File >
   Export Items > Personal Information Exchange (.p12), with a strong password.
2. Export the Sparkle key: `generate_keys -x <file>` (the file is the key itself).
3. Copy the `.p8` from `~/.appstoreconnect/private_keys/`.
4. Put the three files in one encrypted disk image (Disk Utility > File > New Image > Blank Image, encryption AES-256),
   its password in the Passwords app. Keep one copy on the external disk and one in iCloud Drive; delete the loose
   exported files.

Restore on a new keychain: double-click the `.p12`; `generate_keys -f <file>`; copy the `.p8` back; store the notary
profile again (table above).

**Checks before a release needs them** (read-only, except the throwaway file in `$TMPDIR`). The first use of a new key
by `codesign` or `sign_update` asks for the login password once: choose Always Allow.

```sh
security find-identity -v -p codesigning     # lists "Developer ID Application: Paul Lobpreis (3B8SMSSAX4)"
xcrun notarytool history --keychain-profile macem-notary    # lists past submissions: the profile works
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -p   # equals SUPublicEDKey in Info-Direct.plist
cp /usr/bin/true "$TMPDIR/signtest"
codesign --force --sign "Developer ID Application: Paul Lobpreis (3B8SMSSAX4)" --options runtime --timestamp "$TMPDIR/signtest"
codesign -dvv "$TMPDIR/signtest"            # Authority=Developer ID Application …, a Timestamp line
build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update "$TMPDIR/signtest"   # prints sparkle:edSignature="…"
build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --verify "$TMPDIR/signtest" <the signature>
codesign -d -r- /Applications/mac4DSTEM.app   # a website install: the requirement names the team, not a certificate
```

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
store it from the App Store Connect API key as in Keys and backups; a 403 "required agreement is missing" means the Developer Program License Agreement
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
