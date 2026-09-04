# Closed items — 2026-09 archive

Moved here from [`docs/open-items.md`](../open-items.md) as each closes,
enforcing that file's rule that closed items do not stay there. The 2026-08
file is a single dated move and stays closed; this is its September
successor rather than a second section inside it. Entries appear as they
last stood in the live file, with a closure note. **History, not guidance.**

---

## Status line leaks a full filesystem path — closed 2026-09-04

### ~~Status line leaks a full filesystem path~~ — **CLOSED 2026-09-04**

> ~330 characters including the absolute path, rendered raw in
> `StatusFooterView` and `ProductWorkspaceViews`' header progress; the
> archived checklist's screenshots (public docs) have carried it since
> 2026-08-19. Worth truncating for display while keeping the log copy.
> Still open.

**Closure.** Both named views were deleted with the AppKit window
(`d5786e2`), but the leak was not theirs. It came from the readers: three
error descriptions interpolated the absolute path they were handed —
`H5Error.cannotOpenFile`, `DM4Error.cannotOpen`, `VendorRawError.cannotOpen`
— and `AppState.present(_:)` puts `error.localizedDescription` on both the
window-modal alert and the status line. Every other status-line assignment
already used `lastPathComponent` or `descriptor.fileName`; these three were
the last route.

Fixed by naming the file instead of the path (`displayFileName`, one helper
in `Core/Data/FourDDataSource.swift`), pinned by three tests in
`ErrorRoutingTests` that were broken first. Deliberately left alone:
`H5Error.libraryUnavailable`, whose detail is `dlopen` failures over
app-install paths — no user data, and the only diagnostic for a bundled-HDF5
load failure. `DM4Error` keeps the underlying error that the v2 S7 audit
added to distinguish EPERM from ENOENT from a short read; only the enclosing
path is gone.

---

## Sidecar restore doesn't check the calibration frame — closed 2026-09-04

### ~~Sidecar restore doesn't check the calibration frame against the view~~ — **CLOSED 2026-09-04**

> `applySessionCalibration` adopts a saved calibration verbatim; a sidecar
> saved at full extent and restored onto a reconfigured (cropped/binned)
> view leaves a source-frame calibration beside reduced pixels (S10 Gate B
> finding 2).

**Closure.** It asks now. `applySessionCalibration` calls
`SessionCalibrationFramePolicy.decide` (`mac4DSTEM/App/AppState.swift:2887`);
the policy is `mac4DSTEM/Session/SessionCalibrationFramePolicy.swift`, added
2026-09-01, and is pinned by `SessionCalibrationFramePolicyTests` and
`SessionCalibrationTranslationTests`. Evidence class, stated plainly: verified
by reading the tree on 2026-09-04. The restore path itself still has no test —
the policy and the translation are pinned as pure functions, and the call site
is review-pinned, which `StrainFrameTests` notes.

The entry's second half — `exportableRecipe` refusing rather than composing
across frames — is NOT closed. It was never a wrong number: the archive records
it as an S10 decision with the reason surfaced in the export status line. It
stays live under "Known, scoped, not blocking".
