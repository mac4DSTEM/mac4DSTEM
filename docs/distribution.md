# Distribution and notarization

The project now produces a self-contained, hardened, sandboxed macOS app. The
target embeds `libhdf5.dylib`, `libsz.2.dylib`, and `libaec.0.dylib` in
`Contents/Frameworks`; Xcode signs each nested library with the app identity.

Run the credential-free release audit before archiving:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
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

Preferred workflow: Archive in Xcode, open Organizer, choose **Distribute App →
Developer ID → Upload**, review the notary log, then export the stapled result.
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
