# Releasing — dated readiness narratives (moved 2026-09-23)

Verbatim sections moved out of `docs/releasing.md` when it was brought
current for HEAD after the v4.0.0 release (2026-09-23). Superseded by the
v4.0.0 row in `docs/releasing.md` § Releases; kept here for the archive
rehearsal/`package-test` discovery that is still true of the procedure.

## "v3.1.0 readiness — 2026-09-19"

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
