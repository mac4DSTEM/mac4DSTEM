# Closed items — 2026-09 archive

Moved here from [`docs/open-items.md`](../open-items.md) as each closes,
enforcing that file's rule that closed items do not stay there. The 2026-08
file is a single dated move and stays closed; this is its September
successor rather than a second section inside it. Entries appear as they
last stood in the live file, with a closure note. **History, not guidance.**

---

## Datacube discovery accepts rank-3 non-cubes — closed 2026-09-05

### ~~Datacube discovery accepts rank-3 non-cubes~~ — **CLOSED 2026-09-05**

> `describe` promoted every rank-3 dataset to `[1, d0, d1, d2]`, making
> `is4D` tautological. A shallow `/data` sibling could therefore win over a
> genuine deep cube and load the wrong pixels and calibration.

**Closure.** `DatasetDescriptor.storedRank` preserves the on-disk rank;
discovery now prefers stored rank 4 and rejects known stack/map labels from
emdfile/py4DSTEM and this app's RGBA writer. Legacy v0.12 string labels are
recognized only in the pinned `diffractionslices` context. A file-root
sidecar marker is honored before canonical-path probes, while marked subtrees
remain excluded. Calibration follows the selected descriptor, including the
rank-3 `(N, Qy, Qx)` axis mapping.

The independent Gate B mutation review confirmed the mechanism and found no
remaining scoped refutation. The 27-fixture discovery harness, 463/0/1 unit
gate, and 43-harness scientific gate passed on 2026-09-05. An unlabelled rank-3
fallback remains intentional: it opens as one scan row when no better signal
exists; no detector-size magic floor was added.

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

---

## Scan-fastest DM4 tile reads traverse the mapping out of storage order — closed 2026-09-05

> The 2026-09-05 Gate B measured `Si-SiGe.dm4` at 4.17 s for one scan row and
> 17.01 s for a full tile, warm: the strided read visited detector pixels
> pattern by pattern, a 1.2 MB stride per pixel.

**Closure.** `DM4Reader.scanFastestGather` is a blocked transpose (32
detector columns × 32 scan positions per block) for tiles, and a storage-order
sweep for fewer positions than a block. Same file, same machine, probe
compiled with `-O` (`scratchpad/dm4-probe-20260905.log`): pattern 0.044 s,
row 0.06 s, full tile 0.94 s, checksum of pattern (ry 1, rx 2) unchanged at
5877300012132 and equal to ncempy's under the same axis model. Pinned by
`tools/dm4-robustness-test` (`testScanFastestBlockedGather`: 45 positions,
70 columns, cropped and binned, against the analytic storage formula); four
mutants — strides swapped, the blocked path reading one position for all,
the sweep ignoring the crop offset, the units contradiction ignored — each
failed the harness before the tests were trusted.

---

## ACOM bundle exports no origin provenance — closed 2026-09-05

> The strain bundle snapshots `origin_reference` and the excluded fraction at
> compute time; `ACOMRunSemantics` had no equivalent, so reading live
> calibration at export time (what Gate B found wrong on 2026-08-28) was the
> only option, and the exporter deliberately wrote no origin keys at all.

**Closure.** `ACOMRunSemantics.originProvenance` is captured in `runACOM`
from `originFitProvenance` at the moment the vectors are re-centred, and
`provenance` merges it (the snapshot wins over any same-named material key).
The orientation bundle now carries `origin_reference`,
`origin_reference_is_measured`, the fit residual and the excluded fraction as
they stood when the map was computed. Pinned by `ProductWorkflowTests`.
Refuter note (2026-09-05, pre-existing, not fixed): a calibration change made
while the detached match is running is not detected by the post-run guard,
which checks model and scale only; the snapshot stays right for the map, the
live calibration then differs with no staleness flag.

## Selected-area diffraction's mask-to-tile correspondence is unpinned — closed 2026-09-05

> Gate B demonstrated (2026-08-27) that replacing the per-tile mask slice
> with row 0's mask stays green on every harness: the fixture had two scan
> rows and a region covering both, so every row's slice equalled row 0's.

**Closure.** `tools/virtual-detector-test` gained
`selected_area_diffraction_partial_rows`: a four-row cube, a region over rows
1–2 only, one-row AND two-row tiles, compared against a CPU sum of the
analytic cube rather than the resident Metal path (which shares `makeMask`).
The row-0 mutation was re-applied on 2026-09-05: the old case stayed green
and the new one failed (`scratchpad/virtual-detector-mutant-20260905.log`).
The Gate B refuter then broke the first cut of this case: with values linear
in scan index, reversing the mask rows inside a tile summed rows {0,3} for
{1,2} and 1+2+10+11 = 4+5+7+8 — 22/22 green. Values are now `2^scan` (every
subset sums uniquely) and the region 1 × 2 (an x/y swap cannot cancel);
the reversal fails (`virtual-detector-mut-i-20260905.log`) and the refuter's
swap fails the new case alone (`var-B-mut-ix.log`). Ten mutations in all.

---

## The plane origin fit sits 0.26 px off the beam on `polycrystal_2D_WS2` — closed 2026-09-05

> Gate B refuter, 2026-09-05: fitted origin (63.996, 63.996) against the mean
> pattern's beam centre of mass (63.74, 63.74); the first-shell radius ran
> 18.51 → 19.20 px around the ring. Every radius-based number downstream
> carried it until a symmetric set cancelled it.

**Closure.** Gate D the same day (`q-calibration-design.md` §9): the
per-position measurement, not the fit — one centre of mass in a 1.2 r window
around a block-binned coarse centre truncated the beam. `measureOrigin` now
iterates the window on its own estimate in max(r · rscale, r + 1.5 px);
WS₂ reads 63.738 at the shipped rscale. Pinned by `origin_measurement_truth`
at 0.02 px (the old kernel failed it by 0.42 px) and by the two-spec
harness's P4 equivariance check, tightened from 0.65 px to 0.001 px.
