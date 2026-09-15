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

---

## Disk detection at defaults finds only the beam on `polycrystal_2D_WS2` — closed 2026-09-05

> Its Bragg disks are ~0.002 of the central beam; the shipped
> `minRelativeIntensity` 0.005 (py4DSTEM's own default) rejects every one.
> The scan warning said "spacing or thresholds" and could not name which.

**Closure.** Two pre-registered candidates, both settled the same evening.
(1) The warning names the knob: `DiskDetectionScanSummary` carries the run's
parameters and the median ≤ 1 text names Min relative intensity, its value,
its reference (the brightest peak — the central beam — at `relativeToPeak`
0) and both remedies; one test, failing first. (2) `relativeToPeak` 1 as the
default is REFUTED by measurement on six training cubes at the shipped
0.5 % (`det-experiment-20260905.log`;
`tools/bragg-spacing-probe/detection-threshold-probe.swift`):

| cube | peaks/position, ref 0 → ref 1 | at the 70 cap, ref 0 → 1 |
|---|---|---|
| WS₂ (disks at 0.16 % of the beam) | 1 → 45 | 0 → 344 of 16 384 |
| sim_Au | 16 (4 020 of 8 400 exactly one) → 36 | 0 → 3 918 |
| Si-SiGe experimental | 24 → 27 | 0 → 0 |
| SPED MgO | 66 → 70 | 2 901 → 12 357 of 12 426 |
| Si-SiGe calibrated | 22 → 36 | 0 → 2 |
| twisted bilayer graphene | 1 → 1 | — |

WS₂ needs ~13 peaks (six-fold shells at 18.9 px, found at 5e-4 relative to
the beam); 45 is the disks plus noise, because 0.5 % of a disk that is
0.16 % of the beam is 8 ppm of the beam. Wherever the second-brightest peak
is itself weak — vacuum-like positions in sim_Au, MgO's dense rings — the
reference collapses and the cap saturates. The right remedy for WS₂-type
data is a lower threshold per dataset, which the warning now says; a
noise-referenced threshold would be a design pass, not a default flip.

---

## Four entries archived 2026-09-07 (C1): closed, refuted, or decisions rather than defects

Each as it last stood in the live file. S17 and the sidebar drag crash lost
their code and their tests to the AppKit retirement (`d5786e2`) and survive
only as the constraint-loop rule; the width gate is a refuted approach, not a
defect; the cross-frame export is a recorded S10 decision. What each asked of
the owner — driving a divider — is C3 of `consolidation-plan.md`.

### (archived 2026-09-07) S17 sidebar intermittent — archived, its test is gone
`SidebarLayoutTests` and the `ContentView` column publisher the whole
observation log measured were deleted with the AppKit window (`d5786e2`), so
the log cannot be extended and the fault cannot recur in the same place. The
full record — 2 of 5, then 0 of 14, then 3 of 4, and the 810.5 pt against
786 pt it always failed at — is in [`archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md). What survives it is the rule in
the constraint-loop entry below. Kept live only as the name S17, which other
entries still cite.

### (archived 2026-09-07) Sidebar drag crash — mechanism found and removed 2026-09-03, owner's drive owed
Exception (owner, Xcode console): `NSGenericException: The window has been
marked as needing another Update Constraints in Window pass, but it has
already had more … passes than there are views in the window`, after a
sidebar drag; the sidebar at ~60pt with its content laid out at full width.
Reproduced on the demo fixture with real mouse events: column 92pt, content
305pt wide at x = −213. Mechanism, measured in-process: SwiftUI's
`NavigationSplitView` owned the sidebar's split item and rewrote its
minimum to 140 on every update, while the declared 250 constrained only the
content; a drag shrank the column under content that could not shrink and
the loop guard threw. Refuted on the way: the hard frame belt (crash
reproduced without it), the policy "never applying" (it applied and was
overwritten). Fix: the columns are AppKit's (`ColumnSplitController`, an
`NSSplitViewController` with sidebar/inspector items; hosted content with
`sizingOptions = []` so it never sizes the column). Live drive 2026-09-03:
drag past the minimum collapses, Show Tools reopens at the old width, a
560pt sidebar squeezes the inspector first, no exception.
**2026-09-04: the fix described above no longer exists.** `d5786e2` deleted the
AppKit shell, `ColumnSplitController` with it; the columns are a SwiftUI
`NavigationSplitView` now. So the drive this entry asks for cannot be performed
as written — dragging today exercises different code. What is worth carrying
forward is the MECHANISM, not the fix: a split rewriting a hosted child's
minimum under content that cannot shrink, which is the constraint-loop rule
below. Kept live rather than archived only because the owner has still never
driven a column divider on the rebuilt window.

### (archived 2026-09-07) A unit-level column-width gate is not possible — falsified 2026-09-04
`d5786e2` deleted both width-range gates, so nothing gates a column's width and
this repo keeps finding truncation defects there. **Refuted before it was
built.** A probe hosted `PrepareSettings` (250 pt), `WorkspaceSidebar` (190 pt)
and `WorkspaceInspector` (280 pt) in an `NSHostingView` and measured
`fittingSize.width` and the worst descendant-`NSView` overflow; then a
150-character section label — impossible in 250 pt — was injected and it re-ran.
**Both runs byte-identical**: `fittingWidth=1103.0 worstOverflow=0.0`. SwiftUI
draws `Text` into layers and makes no `NSView` per label, so only real controls
appear; the deleted gate had the same hole (`controls(_:)` collected
`NSControl`s). `fittingSize` is no substitute — 1103 pt for a form that fits,
0 pt for the sidebar `List`. Anything that catches a long label must rasterise
or drive the app. Owner: re-open only with a measurement that survives the
injected-label mutation.

### (archived 2026-09-07) Cross-frame recipe export refuses rather than composing
The other half of this entry is CLOSED and archived: `applySessionCalibration`
no longer adopts a saved calibration verbatim — it asks
`SessionCalibrationFramePolicy.decide` (`AppState.swift:2887`), added
2026-09-01, pinned by `SessionCalibrationFramePolicyTests` and
`SessionCalibrationTranslationTests`. What survives is not a wrong number but a
feature gap, so it moves out of the Science lane: `ResultExport.exportableRecipe`
REFUSES, with a reason in the export status line, when the recorded frame is not
the live view — a three-frame composition (recorded → source → exported) needs a
transform `ReplayFrameTransform` does not have. Recorded as an S10 decision, not
a defect. Owner: unclaimed.

### (archived 2026-09-07) Four Python scripts import py4DSTEM outside the lock (2026-09-07)
`tools/calibration-test/make_real_fixture.py`, `make_origin_maps_fixture.py`
and `tools/training-dataset-campaign/{parity_py4dstem,verify_py4dstem}.py`
import whatever `py4DSTEM` the interpreter has (0.14.17 in the env here)
instead of the lock `References/py4DSTEM-dev` (0.14.19) that every gated
`run.sh` puts on `PYTHONPATH`. The reference is the lock (`decisions.md`,
2026-09-07). Fix: export `PYTHONPATH` in their runners; regenerate no fixture
until a diff says it matters. Owner: C2 (a `run.sh` touch).
**Closed 2026-09-07 (C2):** each of the four inserts `References/py4DSTEM-dev`
at the head of `sys.path` when the lock is fetched, so the script and its
runner agree without a `PYTHONPATH` export. No fixture regenerated.

### (archived 2026-09-07) UI review (Fable, 2026-09-04) — labels that can misstate a number — fixed in code, drive owed
Nothing found was a wrong computed value; every finding was a LABEL on a
correct one. (a) axis order and (c) byte sizes fixed 2026-09-04; (b) pattern
statistics named for what is on screen, (d) comparison panels carry a
colorbar with range, units and a zero mark, (e) the cursor readout prints
four significant digits, (f) one staleness verdict (`TaskProductState`) on
the sidebar, the inspector and the maps computed from stale disks, plus the
two minors (no "px" under a physical sampling; no invented disk radius
without a kernel) — all 2026-09-05, six unit tests, **unverified on
screen**. Owner: the owner's drive (C3).

## Verification debt
**Closed 2026-09-07 (C3, agent drive):** (b), (d), (e) and the two minors seen on screen (`shots-c3/a1-launch.png`, `a4b-divider-back.png`); (f) staleness not yet provoked — carried in the C3 leftovers entry.

### (archived 2026-09-07) Sidecar contents moved to the LEFT sidebar — done in code, UNVERIFIED ON SCREEN (2026-09-04)
Moved 2026-09-04 (owner asked for it on release night).
`Section("Saved session sidecar")` is gone from `WorkspaceInspector`; its
filename row, Calibration, BraggVectors, the saved-result rows, Apply Saved
Controls and Change…/Ignore… render in `WorkspaceSidebar`'s
`Section("Session")`. Info keeps only the unreadable / does-not-fit sections.
Builds clean, no test names the moved identifiers. **The one judgement call,
the owner's to overrule:** Remove is each result row's context menu, not a
second visible row per result as Info had it — right-click is the
source-list idiom. Sidebar rows have no width, so one caption line survives
and the rest is on `.help`. No gate can see any of this; the context menu has
never been opened by anyone. Owner: the owner's drive (C3).
**Closed 2026-09-07 (C3, agent drive):** the rows and the reopen seen (`shots-c3/b3b-sidebar.png`, `b3d-reopened.png`); the Remove context menu stays in the C3 leftovers entry.

### (archived 2026-09-07) Status-bar elapsed / throughput / ETA — rebuilt, NOT yet driven (2026-09-04)
Owner: those three numbers belong beside the progress bar, not only in the
inspector's Performance tab. Built, reverted the same day for the crash
above, rebuilt in a reserved slot: `LayoutPolicy.operationMetricsWidth`, a
constant frame the text truncates inside, no `.fixedSize()`, held for the
whole operation so an appearing rate or ETA moves nothing.
`OperationMetricsFormat.line` composes it for both surfaces.
`StatusBarMetricsTests` pins what it says and measures the widest line the
formatter can produce against the constant in the same font; all four tests
were broken first. **What is left is the drive**: only a real dataset
exercises it — the demo cube finishes faster than the one-second tick.
Owner: the owner's drive (C3).
**Closed 2026-09-07 (C3, agent drive):** the slot holds elapsed and the progress bar (`shots-c3/a5-running.png`); the `%` wrap is its own presentation observation.

### (archived 2026-09-07) S1's crop restore is repaired in code and unverified on screen (2026-09-04)
Retitled 2026-09-04: **its three code claims are all false now.**
`recordedLoadSpecification` reads through `sessionSidecar.location(forSourcePath:)`,
which takes the security-scoped grant first (`SessionSidecarLocator.swift:144`),
and the `try?` is gone — a refused read and "no crop recorded" stay different
facts. What is open is the drive: F1.3h passed on a FULL-EXTENT sidecar, which
never enters the repaired branch, so a cropped save → quit → reopen has never
been driven. `SessionSidecarLocatorTests` cannot close it either — it adopts
an in-memory grant and never opens HDF5. Failure mode if still wrong: right
numbers, wrong region. Owner: the owner's drive (C3).
**Closed 2026-09-07 23:33 (owner):** a cropped `sim_Au` session reopened on scan 90×51 at (3, 15), the sidebar naming the view; the whole-file calibration was refused for it, as P2 says.

### (archived 2026-09-07) Presentation-contract residuals still open on screen (2026-09-04)
Rules 2 and 5 were wrong as written and are amended in `architecture.md`; the
finding and its evidence are archived ([`archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md)).
Two of the three "still open" items closed with the rebuild (no workspace
hero header; pane centring is `PaneSplit`'s business). What is left,
unverified: **~40 permanent caption `Text`s across the sidebars**, and
**nothing has been seen in light appearance**. Owner: the owner's drive (C3).
**Closed 2026-09-07 23:33 (owner):** four screenshots in light appearance, nothing unreadable; the ~40 caption Texts are C4's exposure slice.

### (archived 2026-09-07) The columns' material was diagnosed, and never checked in light (2026-09-03)
Gate D 2026-09-03 (archived, [`archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md)):
the hosted lists were painting over AppKit's column material;
`.scrollContentBackground(.hidden)` removed that, and the columns still render
flat because the OS's column material is within-window. The conclusion — the
columns look like Xcode 26's, flat on the window ground — was reached in dark
appearance only. Owner: the owner's drive (C3).
**Closed 2026-09-07 23:33 (owner):** the columns render flat on the window ground in light too.

---

## `all` is red: downsample_Si_SiGe_exp candidate counts drifted — closed 2026-09-09

### ~~`all` is red: downsample_Si_SiGe_exp candidate counts drifted +2/+2/+1~~ — **CLOSED 2026-09-09, the golden was stale**

> Reproducing observation, 2026-09-08, `scratchpad/v3-gate/all-20260908.log:1523`,
> `GATE_EXIT=1`: `FAIL: downsample_Si_SiGe_exp.h5 diskSampleCandidateCounts:
> [93, 118, 98] != [91, 116, 97]`. Cause NOT established — do not fix, and do
> not re-pin the golden. C7 and C4(b) named as the plausible suspects.

**Closure — Gate D, 2026-09-09.** Neither suspect, and neither was in the
entry's own list of what had landed: the 2026-09-05 science lane was missing
from it. The cause is `ba6360d` (2026-09-05, "Science lane: probe refusal…"),
which corrected `OriginCalibration.probeSize`'s median from `sorted[n/2]` to
numpy's even-count rule, matching py4DSTEM's `np.median(dr_dtheta)`
(`process/calibration/probe.py:54`, `N = 100`). Because
`sorted[n/2] >= (sorted[n/2-1] + sorted[n/2]) / 2` always, the old rule's
`2 * median` band was never wider than the correct one and systematically
truncated the trusted threshold set — here 74 → 75 on Si_SiGe and 86 → 87 on
bullseye, one index added and none removed. **The app is the correct side and
the pinned golden was three days stale.** `expected.json`'s Si_SiGe fields are
re-pinned to the measured values, `calibrationData_bullseyeProbe.h5` is now
pinned too, and **no code changed**. The commit announced the effect at the
time (`CHANGELOG.md` at `ba6360d`: "the probe radius can move by a fraction of
a pixel on some patterns"); measured, +0.0294 px and −0.0425 px.

**Evidence**, retained in the session scratchpad `drift/`: HEAD twice,
identical field for field (`e1-run{1,2}.log`) — deterministic; the bisect
`ba6360d^` **exit 0** / `ba6360d` **exit 1**, the two reports identical on
every field of all five cubes, so none of the 43 later commits contributes
anything; the causal control — reverting only the median line returns both
radii bit-for-bit and the gate to **exit 0**, revert `cmp`-verified; and an
independent numpy transcription of py4DSTEM's algorithm
(`e4-probe-truth-20260909.log`) giving 2.0076250 and 7.1286265 in float64,
matching HEAD to 1.3e-7 and 8e-7 where the goldens are ~7000× `compare.py`'s
tolerance away. Gate D's refuter reproduced every link independently and wrote
its own twin.

**What the refuter overturned, recorded because the first account was wrong.**
(1) *Scope*: **two of five cubes drifted, not one of four.**
`calibrationData_bullseyeProbe.h5` moved as well (radius 7.171119 →
7.1286273, candidates [192,205,187] → [196,207,193]) and was invisible
because it is unpinned — and the session's own `fulldiff.py` iterated over
`expected.json`, so it shared the gate's blind spot exactly. That is why the
cube is pinned now. (2) *"The final science output does not move" is refuted.*
The counts this golden pins are unchanged apart from those listed, but peak
POSITIONS move on both drifting cubes — ~0.005–0.02 px on all 36 Si_SiGe
peaks, and on bullseye position 0 one peak is substituted, (114.2198,
194.8632) → (140.6368, 196.8596), ~26 px away, while the count stayed 11 so
the harness saw nothing. `AcceptanceReport` carries no coordinates, so this
harness is structurally unable to see it. On a cube whose open item says the
0.5 % default keeps ~130 noise peaks per position, a swap between two
near-threshold noise peaks is expected rather than alarming — but the claim
could not stand. (3) The app's own pipeline was not measured at closure time:
`probeSize` runs on `meanDP` at `OriginCalibration.swift:513/570` and
`AppState.swift:4562`, never on this harness's max-of-three input.
**Measured 2026-09-09, and it does not move.** `origin-fit-diagnostics
probe-size` feeds the real `probeSize` with `meanDP` and prints the shipped
`app tiledRun probeRadius`; under both median rules it is identical on four
cubes — Si_SiGe 3.738, WS2 1.858, sim_Au 5.113, bullseye 6.843 px
(`drift/apppath-{new,old}median-20260909.log`, `apppath-bullseye-{new,old}.log`),
and bullseye's whole-scan `maxDP` 11.223 px matches too. On a smooth averaged
pattern no `dr` value falls between the old and the new median, so the trusted
set is unchanged; the drift lived only in the harness's spikier max-of-three
input. Caveat: printed at three decimals — the harness deltas were 0.029 and
0.042 px, 30-80x that resolution, so a real move would have shown — and only
the probe radius, not the full origin fit or Q-calibration.

**Also refuted, and it was the diagnosis's own reasoning:** that Si_SiGe was
selected for carrying the smallest probe radius. `polycrystal_2D_WS2` measures
1.8664341, smaller, and did not move. What selects a cube is whether one of its
100 `dr` values falls between the old and the new median — left unexplained
rather than patched over.

**Guard added:** `ProbeSizeTests.testProbeSizeUsesNumpysEvenCountMedianForTheTrustedBand`
pins the even-count rule on a soft-edged fixture where the two rules differ by
0.144 px, both values derived in numpy and retained before the test was
written. Broken first by a `sorted[n/2]` mutant — exit 65, and it is the ONLY
test that fails, so the six pre-existing `ProbeSizeTests` were blind to the
rule. Until 2026-09-09 nothing below `run-tests.sh all` pinned it at all.

## Closed at the v3.0.0 closeout, 2026-09-11

### The bundle's duplicate Info.plist — FIXED 2026-09-11
Fixed by one `membershipExceptions` entry (the app group is a folder-sync
group, which swept `Info.plist` into Copy Bundle Resources). **Verified in
the rebuilt bundle:** `Contents/Resources/Info.plist` gone, every generated
key still present, `LSMinimumSystemVersion` **14.0**, document types intact,
and the build warning at 0 occurrences. Commit `70642ba`. The original
entry, including what was and was not established before the fix, follows.

### D002 and D003 are CLOSED, and the register's count is now 111 (2026-09-09)
Both CRITICALs were taken through Gate D, refuted by an independent agent, and
fixed the same day. Evidence:
[`docs/archive/2026-09-09-review/d002-d003-gate-d.md`](archive/2026-09-09-review/d002-d003-gate-d.md).
Two hypotheses were **refuted** there and must not be re-walked: (a) that the
D003 overrun crashes `H5Reader` on open — it crashed one prebuilt binary 40/40
and a fresh build of the same sources survives 40/40, so the SIGTRAP is
allocator-layout luck, not a reproducible property; (b) that the ptychography
transpose result was proven by the demo cube — that cube is square with equal
row/column object sampling, so transpose was a geometric no-op there and the
finding was re-run on a non-square crop. Still unproven and stated as such:
that any real instrument writes a multi-element `units`/`name`.
### The app bundle ships a duplicate Info.plist (2026-09-11)
Every build warns *"The Copy Bundle Resources build phase contains this target's
Info.plist file"*, and **the duplicate is real — confirmed in the built bundle,
not inferred**: `Contents/Resources/Info.plist` is **1 497 bytes** (the raw
source file) beside the real merged `Contents/Info.plist` at **2 798 bytes**.
macOS reads the latter, so nothing malfunctions; what ships is a misleading
partial copy that anyone inspecting the app can read instead of the real one.
**Cause, established statically:** `Info.plist` is NOT listed in
`PBXResourcesBuildPhase` — the app group is a `PBXFileSystemSynchronizedRootGroup`,
so folder sync sweeps every file under `mac4DSTEM/` into the target, Info.plist
included. **The fix is one line:** add `Info.plist` to the existing
`membershipExceptions` of `300000000000000000000001`.
**Verification it must carry, because this is exactly what `a8b13c6` was for:**
rebuild and confirm the BUILT `Contents/Info.plist` still has every generated
key and `LSMinimumSystemVersion 14.0` — the macOS-14 floor is the whole point of
v2.5.1 and must survive. `package-test` passes either way and will not catch a
regression here. Owner: do it before the v3.0.0 artefact is built.
### UI polish: six papercuts, all verified live 2026-09-09
Presentation only, no Gate D. `gammaControl` prints "Gamma, 1.00" as one string
where slice 1 made every other slider two texts; ⌘R (`mac4DSTEMApp.swift:89`)
and ⌘↩ (`WorkspaceView.swift:229`) both run the primary action — harmless, the
owner chose to leave it; `TabView` (`WorkspaceInspector.swift:32`) unstyled;
log height is `@State` (`WorkspaceView.swift:25`) where eight siblings use
`@SceneStorage`. Fixed 2026-09-09, unverified on screen: the document types
(so `.h5` opens by double-click and the proxy icon returns), the doubled
sidecar name, Info's orphaned cost caption (moved to its button), and
`Size (f32)` → `Size as float32`. Still open from the drive: no glossary or `?`
anywhere for probe kernel, ACOM, R–Q rotation, Fit RMS — the student learns
WHICH button to press (disabled-state reasons are consistently plain English)
but never what the term means; owner decided 2026-09-09 NOT to add a glossary
layer before 3.0.0.
Triaged against the drive's findings, fix-now list lands before 3.0.0
(`decisions.md` 2026-09-09).


---

## The v3.0.0 archive failed on an x86_64 slice — closed 2026-09-11

### ~~The v3.0.0 archive failed on an x86_64 slice — RELEASE BLOCKER~~ — **CLOSED 2026-09-11**

> `tools/release/build-developer-id.sh` exit 65, 20 compile errors, all in
> `Core/ML/LearnedDiskDetector.swift`: `'Float16' is unavailable in macOS`.
> The archive compiled for Intel. `ARCHS = arm64` is present twice at project
> level (D064) and did not prevent it. Why the project-level `ARCHS` was not
> honoured was NOT established, nor that pinning it on the archive fixes it.

**Gate D, 2026-09-11.** Cause established, then the fix, then the fixture.

**Established, each reproducible.** The `archive` action is not implicated:
a plain `xcodebuild build -configuration Release -destination
'generic/platform=macOS'` — no archive, no credentials — reproduces it exactly
(exit 65). Every x86_64 build task in that log names `(in target 'DSTEMCore'
... at path .../Package.swift)`: the failing compiles belong to the **SwiftPM
package targets**, not the app target. That follows from the project file —
`Core/` and `Session/` are listed under the app target's
`membershipExceptions`, so only `DSTEMCore` and `DSTEMSession` ever compile
them — and `xcodebuild -showBuildSettings archive` prints `ARCHS = arm64` for
target `mac4DSTEM` and **no settings block at all** for the package targets.
Project-level settings do not reach them: adding `EXCLUDED_ARCHS = x86_64`
beside the existing `ARCHS` at project level still produced four x86_64 tasks
and exit 65, so there is no fix inside the project file. `ARCHS=arm64` on the
xcodebuild **command line** does reach them: exit 0, zero x86_64 tasks. The
full `archive` action, ad-hoc signed, then succeeded with zero x86_64 tasks and
`lipo -archs` on the archived product reporting `arm64` for the executable and
all three embedded libraries, at version 3.0.0 (6) and floor 14.0.

**Judgement, offered as judgement.** `Float16` is correct — it is the ANE
half-precision path and the app is Apple-Silicon-only by design, with
arm64-only embedded HDF5. The Intel slice is a target never supported, so the
fix is to stop building it, not to make it compile. Making `Float16` compile on
x86_64 would have turned a red build into a silently universal one.

**Fix.** `tools/lib/release-arch.sh` spells the pin, the release destination
and an arm64-only assertion once; `build-developer-id.sh` and
`tools/package-test/run.sh` both source it.

**Fixture, and why it could not be fooled the way the old one was.**
`package-test` built `-destination 'platform=macOS'`, the concrete machine,
which filters the architectures itself — structurally unable to see this, which
is how a green `all` and a broken archive coexisted. It now builds
`generic/platform=macOS` with the same pin, so it fails the way the archive
failed, and it asserts `lipo -archs` on the **built** executable and every
embedded dylib, so the tempting wrong fix above goes red too.

**Two traps paid writing the fixture, both caught by breaking it first.** The
bundle assertion ended on its dylib loop, so a universal executable printed
`FAIL` and returned 0 — found by running it against the real v2.5.1 bundle,
which is genuinely universal. And the accumulator was first called `status`,
which in zsh is a special parameter aliased to `$?`.

**What it exposed.** v2.5.1 shipped universal on 2026-09-04 with arm64-only
HDF5 — the live entry in `open-items.md`.


## Closed 2026-09-11 — the embedding's non-finite crash

### One non-finite detector pixel killed the process — FIXED
Found by Gate B at step 8 of the AI port, fixed the same session before the
engine was wired, so it never reached a user. The original entry, verbatim:

> ### One non-finite detector pixel kills the process — blocks wiring
> `Core/Analysis/DiffractionEmbedding.swift`, found by Gate B 2026-09-11 and
> reproduced independently. Chain, each link executed: a NaN or +Inf detector
> pixel → NaN binned entry → NaN covariance → **`dsyevd_` returns `info == 0`**
> at the shipped default (`binnedSize` 16 → `dims` 256; at `dims` 16 it returns 0
> components, so the apparent guard is dimension-dependent) → NaN basis →
> `totalVariance > 0` is false so `explainedVariance` publishes **0.0 for every
> component**, a plausible-looking "0 % explained" rather than an error → NaN
> coordinates → `kMeans` :629-646: `minDistances` start at `.infinity`,
> `dist < minDistances[i]` is false for NaN so they stay infinite, `total <= 0`
> does not catch it, and **`Double.random(in: 0..<.infinity)` traps**. Verified
> standalone: exit **133** (SIGTRAP) and under `-O` the process prints nothing at
> all — stdout never flushes, so it dies with no message. `-Inf` alone is safe
> (`embed`'s `max(buf, 0)` clamps it; NaN and +Inf are not clamped).
> `DPC.swift`, `DiskDetection.swift` and `FitOverlays.swift` all guard `.isFinite`
> on their inputs; this file guards only LAPACK's workspace query. **Do not wire
> diffraction grouping until this is fixed** — wiring is what makes it reachable.

**The fix, with Gate D.** Two guards, both pinned by fixtures that were broken
before they were trusted:
1. `compute()` refuses after forming the covariance —
   `guard totalVariance.isFinite, covariance.allSatisfy(\.isFinite)` — with the
   typed `EmbeddingError.invalidDataset` the caller already handles. Mutation
   `guard true`: `testNonFiniteDetectorValuesAreRefusedNotPublishedAndNever‐
   Trap` goes red, and informatively — it publishes a result instead of
   trapping, so the test catches "published instead of refused".
2. `kMeans` takes `if !total.isFinite || total <= 0`, so an infinite total falls
   into the deterministic-by-index branch instead of
   `Double.random(in: 0..<.infinity)`. Mutation back to `total <= 0`:
   `testKMeansNeverTrapsOnNonFiniteCoordinates` goes red.

`kMeans` was widened from `private` to `package` to make guard 2 testable at
all — the same reason and the same precedent as `symmetricEigenTop` in the same
file. `compute` refuses upstream, so guard 2 is unreachable through the public
path, and an unreachable guard with no fixture is one nobody can prove works.

**What did NOT change, checked rather than assumed:** `-Inf` was always safe
(`embed` clamps with `max(buf, 0)`) and still is — a separate fixture pins that
a `-Inf` pixel still produces a full result with finite, non-negative explained
variance, so the guard has not over-fired and turned working datasets into
refusals.

## The phase-mapping gate shares its in-plane frame with the code — closed 2026-09-14

### ~~The phase-mapping gate shares its in-plane frame with the code~~ — **CLOSED 2026-09-14**

**Verification debt.** `tools/phase-vector-matching` generates its synthetic
patterns through `ACOMOrientation.detectorBasis`, the same call
`PhaseReferenceLibrary.projectedVectors` makes — so a handedness flip there
(`simd_cross(e1, n)` for `simd_cross(n, e1)`) mirrors both sides and **all 27
checks stay green**, measured by Gate B 2026-09-12. This is the L3 trap. An
x/y swap or a y flip on the experimental side alone IS caught (P2 falls to
31.8 %); only the shared frame is blind. `tools/acom-convention-test` builds
its own frame from a seed and does cover it, but nothing links the two gates
except this entry. Remedy: generate Part B's peaks from a harness-built frame,
as acom-convention-test does — β″ [010] is a chiral net, so P2 would then pin
the handedness.

**Closure.** `tools/phase-vector-matching` now projects Part B's peaks through `harnessFrame`, a seeded right-handed pair built the way `acom-convention-test` builds its own, and A4 compares the two projections up to one rotation per zone. Under the handedness mutation named above, A4 (worst |Δq| 2.209 Å⁻¹) and P2 (32.4 % labelled β″) went red; the unmutated tree passes 27/27. The link between the two gates is now code in both.

## `Crystal.reflections` under-tiles oblique monoclinic cells — closed 2026-09-14

### ~~`Crystal.reflections` under-tiles oblique monoclinic cells~~ — **CLOSED 2026-09-14**

**Science, Gate D owed.** `numTile = ceil(kMax / kMin)` with kMin the shortest
of ten reciprocal test directions, but the true bound is `|h| ≤ kMax·a`. For a
b-unique monoclinic, kMin ≤ a* = 1/(a sin β), so the tiling can fall short and
reflections are **silently missing**. Measured by Gate B on a β″-shaped cell
(a = 15.16, b = 4.05, c = 6.74): β = 105.3° (the shipped β″) loses **0** at
either kMax; β = 110° loses 6 at kMax 1.6; β = 115° loses 48; β = 125° loses
198. Pre-existing `Crystal` code, but phase mapping is the first feature to
drive it with arbitrary imported cells — which its own header says is the case
it exists for. Not urgent: β″ itself is unaffected.

**Closure.** Gate D 2026-09-14: the diagnosis (the shortest reciprocal direction can be longer than 1/|aᵢ|, so `ceil(kMax/kMin)` is not a bound on the index) predicted that a superset check would find misses at β = 115° and 125° and none for fcc Al or the shipped β″; `testReflectionsCoverEveryLatticePointInsideKMaxOnObliqueCells` went red on the old code and green with the per-axis bound `ceil(kMax·|aᵢ|)`, which is exact because h = g·a₁. Al (282) and β″ (3458 at tolerance 1e-9) sets are unchanged. py4DSTEM carries the same bound; the fix is an inline `DEVIATION`. Red again under the reverted bound on 2026-09-14 (mutation run).

## The embedding suite says almost nothing about `coordinates` — closed 2026-09-14

### ~~The embedding suite says almost nothing about `coordinates`~~ — **CLOSED 2026-09-14**
Same Gate B. `coordinates` is the array BOTH exported quantities (cosine
similarity, k-means groups) are built from, and
`grep -n "\.coordinates" mac4DSTEMTests/DiffractionEmbeddingTests.swift`
returns exactly ONE line: an `allSatisfy(\.isFinite)` check. Two mutations
leave all 7 tests green while moving every exported number: dropping the
mean-centring in the projection (PC1 score moves 77 %; cosine similarity
-0.5946 → -0.0406) and reversing the projection column order (the column an
export labels "PC1" carries PC8). The k-means and cosine tests are invariant
under an additive offset, a column permutation and a uniform scale, which is
why both sail through. Fix: `testPublishedBasisAreEigenpairsOfTheMeanCentred‐
Covariance` already owns an independent `referenceBinnedVector` — assert
`coordinates[p*k+c] == dot(referenceBinnedVector(p) - mean, basis[c])` for
several (p, c). Proof obligation: BOTH mutations must go red, not just the
mean-centring one.

**Closure.** `testPublishedBasisAreEigenpairsOfTheMeanCentredCovariance` now asserts `coordinates[p·k + c] == (x_p − mean)·basis[c]` at every seventh position and every component against its own `referenceBinnedVector`. Both named mutations were run on 2026-09-14 and both turned it red (see `docs/status.md`).

## The grouping fallback name uses the requested k, the product the actual one — closed 2026-09-14

### ~~The grouping fallback name uses the requested k, the product the actual one~~ — **CLOSED 2026-09-14**
`Support/ResultMetadata.swift` names diffraction groups from
`lastRunSettings?.groups ?? settings.groups`; `AppState+DiffractionGroups`
publishes with `result.groupCount`, which `DiffractionEmbedding.compute`
clamps to the position count. The two differ only when k exceeded the scan,
and only if the fallback is reached with no published product — no such path
was found by reading, so this may be dead. Outside the 2026-09-14 audit's
scope; left for the session that touches that file.

**Closure.** `Support/ResultMetadata.swift` now names the fallback from `result?.groupCount` first, the same number the publish path uses, with the requested k only when no result exists. Compiled by the targeted runs of 2026-09-14; no test, because no path reaching the fallback with a stale result was found.

## Phase mapping has never been driven — closed 2026-09-14

### ~~Phase mapping has never been driven~~ — **CLOSED 2026-09-14**

**Verification debt.** The owner drove it on `060_STEM SI_…bin_4` (Xcode 27
build of `fc32140`). Seen and right: a phase from a CIF; Find Matrix Zone
Axis returning the ⟨110⟩ family tied at 38 % after "Scale to This Detector"
(the probe measured 39 %); the resolution line 0.44 · 0.44 · 0.22 px and its
warning; a run of β″ [001] against Al ⟨110⟩ giving matrix 2 099, β″ 27, not
indexed 106 774 with the hatch, the legend as the phase list, the Evidence line
following the cursor, and "unvalidated" in both places. **One defect, fixed
on the branch, unseen since:** the zone-axis field kept "0 0 1" after the fit
wrote [0 −1 1] into the slot (`f78122e`). **One observation, not fixed:**
before scaling, the fit returned a ⟨112⟩ family at 8 % — chance level at a
0.44 px tolerance (39 % × 0.19) — and the panel presented it like any other
answer; the zone-axis fit has no chance floor of its own. Still to see: ⌘5
landing on grouping; a phase from the built-in menu; remove-and-re-add
marking the run stale; the fixed field following the fit.

**Closure.** The owner drove the rest the same afternoon on the rebuilt `f78122e`: aluminium from the built-in menu, β″ from the CIF at [010], the fitted axis showing in the field, a run of β″ [010] against Al ⟨110⟩ (matrix 2 099, β″ 280 = 0.3 % against a 3.9 % chance level, not indexed 106 521), Show Match Distance, remove-and-re-add reading stale, and ⌘5 landing on grouping. What the drive found and did not fix is the chance-floor entry that replaces this one.

---

## A second matrix grain is labelled as a candidate phase — closed 2026-09-14

**Closure:** Fixed by `classify` step 5, the matrix challenge, with the rotation derived per position. Gated by Part E of `tools/phase-vector-matching`. Three remedies were refuted on the way and are recorded inside. What stays live is only the presentation residual.

### A second matrix grain is labelled as a candidate phase — FIXED 2026-09-14
**Science. Gate D done, Gate B done and two of its findings fixed.** With Al
[001] the matrix and β″ [010] + β″ [001] candidates, the demo cube's Al [011]
grain — 2 250 positions of pure aluminium — came back **100 % β″ [001]**,
because nothing asked whether the MATRIX explains the surviving vectors. β″
[001] covers 10 of the 16 [011]Al reflections at 0.0059 Å⁻¹; Al [011] covers
all 16 at 0.0000 and was never in the competition. Fix: `classify` step 5, the
matrix offered every low-index orientation with the in-plane rotation derived
at the position. Measured at shipped defaults (`tools/phase-map-probe --truth`,
`probe-rework-20260914.log`): grain B 100 % → **0 %**; end-on 96/96 and needles
108/108 unchanged; grain A matrix 99.0 %; indexed total exactly the 204 planted
precipitate positions. Gated by `tools/phase-vector-matching` Part E, whose C1a
reproduces the defect so C1b cannot be vacuous.
**Three refutations, all paid:** the first remedy took one rotation per axis
from `fitZoneAxis`, a whole-scan fit that carried [-1 1 0] at 100° where the
grain needs 130° and matched nothing. The second seeded rotations on the three
LONGEST vectors — backwards, because spurious maxima sit farther out than real
reflections: three of them took the catch rate 100 % → 0 %, now gated as C2.
The third required only "at least as many" matched vectors, which let a
49-axis search steal **26.5 % of three-vector precipitates** at 0.004 Å⁻¹ of
jitter; "strictly more" makes a fully explained precipitate impossible to erase
by construction, gated as C3 (0 of 500).
**Residual:** a `.matrix` verdict from the challenge is drawn the same grey as
one by exclusion, and the map's phase counts cannot separate them; the
evidence line now distinguishes them but nothing else does. The matrix fraction
on the demo cube moves 51 % → 74 % because of it.

---

## R–Q rotation reported "Measured" from pure shot noise — closed 2026-09-15

**Closure:** Fixed by a permutation null in `RotationCalibration.solve`: shuffle the scan positions, rerun the grid, refuse unless the real curve beats every shuffle. Neither the angle nor the coin-flip `transposeQR` is written on a refusal.

**REOPENED THE SAME DAY.** Gate B measured the null to be a test of whether the
field is spatially WHITE, not whether it carries a rotation: a rotation-free
field with any spatial correlation — which probe overlap alone produces — is
certified 60–80 % of the time, the verdict is seed-conditional, and four
mutations survive including one that deletes the guard entirely. The narrowed
item is live again in [`../open-items.md`](../open-items.md), "The rotation null
is a whiteness test, not a rotation test". This closure stands only for the
specific failure it names: pure shot noise.

### R–Q rotation reported "Measured" from pure shot noise — FIXED 2026-09-15
**Science, Gate D done, no fix. Diagnosis survived an independent refuter that
corrected two of its numbers.** On the demo cube, built with the axes aligned,
Measure R–Q Rotation reported **−67.5°** and the row read "Measured".
`RotationCalibration.solve` minimises the mean |curl| of the CoM field, which
is meaningful only for a near-phase object — its own header says so. The demo
cube is Bragg disks on a flat background and has no potential, so there is
nothing for the objective to find.
**Established, and it is stronger than "the curve is flat":**
- The measured CoM field IS Poisson shot noise. Predicted from the counts
  themselves: sd 0.01023/0.01020 px; measured 0.01046/0.00968 (ratio 1.02/0.95).
- **A theorem, not a fit.** Writing the rotated curl as
  `sinθ·div + cosθ·curl` of the unrotated field, over statistically independent
  scan positions var(div) = var(curl) and cov(div, curl) ≡ 0 for ANY
  per-position covariance, so `E[objective(θ)]` is exactly θ-independent. No
  mechanism can produce a preferred angle here, whatever the noise anisotropy.
- The winning curve's depth is `(max − min)/mean` = **0.0134**, which sits at
  the **40th percentile of a noise-only null** (300 realisations: mean 0.0161,
  p95 0.0299). Under that null the argmin is uniform over the half circle and
  the transpose flag is a **51.7 % coin flip** — and `transposeQR` is written
  with provenance `.measuredInApp` and consumed by strain, ACOM and DPC.
- The 0.1° refinement digit is **float32 round-off**: over −69…−67 the float32
  objective spans 1×10⁻⁵ relative, the accumulation floor of 9 604 `Float`
  adds. float64 picks −67.6, a sequential float32 sum −68.0, the app −67.5.
- The **divergence** variant, which the app also exposes, returns **−82.0° with
  transpose TRUE** on the same field. Two objectives, incompatible answers.
**Refuted along the way:** the per-position origin map cannot explain it (the
fitted plane's total variation across the scan is 3×10⁻⁵ px, and re-solving
with it subtracted is identical); no grain-boundary mechanism exists (the
recipe-mean field is 0.05 % of the variance, and the boundaries are
axis-aligned, so a step would pull toward 0°/90°); and **the quadrant spread of
151° proves little** — the noise-only null's p90 is 151.1°, and a genuine field
still scatters 65°, so split-half disagreement is a weak test in both
directions and must not headline this.
**FIXED 2026-09-15 with a permutation null, which is the one test that needs no
constant.** `solve` now shuffles the scan positions of the CoM field fifteen
times — carrying each position's (cx, cy) together, so only the spatial
arrangement is destroyed — reruns the same grid, and reports the winning
curve's depth against those fifteen. `carriesRotation` requires the real depth
to beat **every** shuffle; `refusalMessage` carries the sentence, so the
refusal and the test that produces it cannot drift. Deterministic by a fixed
seed: a refusal that flickers is worse than none. AppState writes neither the
angle nor `transposeQR` when it refuses, which was the sharper half — the flag
was a 51.7 % coin flip and strain, ACOM and DPC consume it.
**Measured on the demo cube with the shipped rule and seed:** real depth
0.01341 against shuffled depths 0.00854–0.02472, so it **refuses**, which is
correct. Three tests, three mutations, each red: the null deleted, the null
compared against the shuffles' mean instead of all of them, and the comparison
inverted (which refuses a planted 30° rotation and is the failure that would
matter most).
**What this does NOT claim, and the code says so too.** It cannot certify a
measurement. A thick or strongly diffracting specimen gives a deep, sharp,
reproducible minimum at an angle that need not be the detector rotation. It
catches one failure — no signal at all — which is the one that reached the
owner. **Unverified on screen.**

---

## ACOM omits py4DSTEM's `power_radial` — closed 2026-09-15

**Closure:** Measured and settled: py4DSTEM's own default is worse here (25.53° of excess orientation error against the port's 18.79°, summed over 8 axes) and breaks ⟨100⟩. The omission is kept, now as an explicit parameter with a `DEVIATION` note carrying the numbers.

### ACOM omits py4DSTEM's `power_radial` — MEASURED 2026-09-15, omission kept
**Was: "untested materiality — apparatus exists but the measurement has not
been made." It has now been made, and the omission is right.** py4DSTEM
multiplies each template spot by its shell radius to `power_radial`, default
**1.0** (`crystal_ACOM.py:32`, applied at :810/:818); this port omitted the
factor, which is 0. Measured over 136 planted patterns with
`tools/acom-groundtruth/orientation-accuracy.py`, as excess orientation error
beyond the bank's own sampling floor, summed over 8 zone axes:

| `power_radial` | 0 (shipped) | 0.5 | 1.0 (py4DSTEM) | 2.0 |
|---|---|---|---|---|
| total excess | **18.79°** | 20.45° | 25.53° | 29.09° |

Their default is worse, and it breaks ⟨100⟩, which this port recovers exactly
(0.00° → 2.20°). The factor now exists as a parameter defaulting to 0 with an
inline `DEVIATION` note carrying these numbers, so the choice is documented
rather than accidental — CLAUDE.md requires the note, and the note now cites a
measurement instead of an opinion. **Parity here would be parity with a worse
answer.** Nothing shipped changed: the default reproduces every previous run.

---

## The ellipse fit measures a 10 % ellipse on an isotropic detector — closed 2026-09-15

**Closure:** The refusal stands as the default; the flag the owner asked for landed behind an explicit "Fit Anyway" button (`decisions.md` 2026-09-15). `fit1D(acceptSparseCoverage:)` fits between 12 and 29 of 36 sectors, marks the result `sparseCoverage`, and refuses several rings in one annulus by a per-sector radius bound of 10 % about the fitted centre; `CalibrationSession.applyEllipseFit` stamps `CalibrationValueProvenance.fitAnyway`. Gated by `tools/ellipse-calibration-test` (anyway loop, a 6 % elliptic sparse ring recovered to 0.07 px, the off-centre seed check) and four `RotationSignificanceTests`. Gate B: five mutations, two caught by the fixture, one (seed centre) caught by a check added for it, one (unweighted mean) surviving and recorded, one provably equivalent; one confirmed blind spot recorded as the cost fixture `overlap_bins_2radii`. Residuals live in `../open-items.md`.

### The ellipse fit measures a 10 % ellipse on an isotropic detector — REFUSED 2026-09-14, flag owed
**Science, Gate D done by the owner's experiment; refusal landed on his
decision ("refuse it for now, add the flag later").** The fit reported
a = 43.68, b = 39.72 on a detector isotropic by construction, and everything
downstream followed. **Four statistics were measured and three refuted:**
- *Azimuthal contrast* (90th-percentile bin over median) — shipped, reverted,
  then refuted again by a new fixture: a LEGITIMATE six-azimuth ring whose fit
  is exactly right reads 81, against the defect's 2 777. No bar separates them.
- *The fit's own `normalizedResidual`* — inverted: the legitimate spotty ring
  reads 0.149 and the defect 0.082.
- *Radial multiplicity* on the fitted ellipse — blind, because the ellipse the
  defect produces threads the three radii so every sample sits on it (1.000).
**Why none of them works, and it is not a missing idea:** a three-grain
annulus and a legitimate six-azimuth ring occupy the same 12 of 36 bins and
differ in nothing a statistic can read — only in the answer. An ellipse has
five free parameters; spots at a dozen azimuths determine it no better than
the three radii they lie on. They are the same measurement.
**So the guard is a degeneracy bound**, not a separation: `fit1D`'s coverage
requirement goes from a third of the azimuthal bins to five sixths. Measured
across a fixture sweep now in `tools/ellipse-calibration-test` (7 new gated
checks, every pattern circular by construction so a reported a/b is a defect):
3 grains refused (it was reporting a/b 1.685), 6 grains refused (its answer
would have been right — the stated cost), 12 grains fitted isotropic, a
9-azimuth spotty single ring fitted isotropic, a nanocrystalline halo fitted
isotropic. Marked `DEVIATION`: py4DSTEM's `fit_ellipse_1D` has no guard at all
and answers degeneracy with `constrain_degenerate_ellipse` instead.
**OWED: THE FLAG, and this is what it has to answer** (owner, 2026-09-14:
"refuse it for now, add the flag later"). A sparse legitimate ring — one
radius, too few azimuths — is now refused outright, and he wants it fitted and
marked instead. The pieces:
- **Where the refusal is:** `EllipseCalibration.fit1D`, the
  `occupiedCount >= angularBinCount * 5 / 6` guard. A flag path fits anyway
  below that bound and marks the result; it does not weaken the bound for the
  multi-radius case, which must stay refused (`grains_3_one_annulus`).
- **What carries the mark:** `EllipseCalibrationFit` has no field for it, and
  `CalibrationValueProvenance` (`Core/Data/Calibration.swift:49`) is what the
  Prepare row's status word comes from. A fourth status beside Measured /
  Manual / From file is the smallest shape that reaches the user.
- **The decision a session may not make alone:** whether the flag REPLACES the
  refusal for a single-radius annulus, or sits behind an explicit "fit anyway"
  after one. The first is silent, the second is a click. Ask before building.
- **Gate:** Gate D applies. A flagged ellipse becomes usable downstream, so the
  change decides whether degenerate distortion reaches strain and ACOM —
  that moves a scientific number even though the fit itself is unchanged.
- **The fixture already exists:** `spotty_ring_6_azimuths` is the legitimate
  case (expect `refuse` today, expect flag-and-fit after), and
  `grains_3_one_annulus` is the control that must stay refused.

---

## The rotation null is a whiteness test — narrowed again 2026-09-15 night

**Closure of THIS entry only:** the shuffle null it describes was replaced the same night by a phase-randomised surrogate null (Gate D, `tools/rotation-null-probe` before/after). What the new null still cannot do is the live entry in [`../open-items.md`](../open-items.md). The text below is the morning's Gate B record, kept for its measurements — note that the probe later reproduced its claim but not its rates.

### The rotation null is a whiteness test, not a rotation test — Gate B 2026-09-15
**Science, live. The guard shipped, Gate B narrowed it, and "FIXED" was wrong.**
`RotationCalibration.solve`'s permutation null catches the failure that reached
the owner — a spatially WHITE centre-of-mass field reported as "Measured
−67.5°" — and refuses no genuine rotation (0 of 60 at every noise level through
sd 0.05, and the cost is invisible: 0.12 s at 100 × 100). What it does not do:
- **A rotation-free field with spatial structure is certified.** Box-smoothed
  noise at a correlation length of two scan pixels beats all fifteen shuffles
  60–80 % of the time, and **probe overlap alone produces that correlation** on
  ordinary data. A per-row descan drift and a specimen edge were each certified
  6 of 6 at 6–20× the shuffled depth, with arbitrary angles.
- **Passing implies nothing about accuracy.** A planted 30° at noise sd 0.03 is
  certified 60 of 60 while 9 are more than 5° out and one is 61° out.
- **The verdict is seed-conditional.** Fifteen shuffles with "beat every one" is
  a rank test at a 1-in-16 design rate; the unit suite's own noise fixture is
  certified under **50 of 200 seeds**, and the demo cube's refusal (depth
  0.01341 inside shuffled 0.00854–0.02472) is the same lottery. A real fix
  needs a statistic, not a rank.
**Gate B left four mutations alive. ALL FOUR ARE SETTLED (2026-09-15).**
Deleting the guard left the whole suite green, because every test lived in Core
and none constructed a session; the decision moved to
`CalibrationSession.applyRotation(_:)`, testable without a dataset, and
`AppState` shrank by three lines. `shuffleCount` 15 → 6 and taking the LOSING
transpose curve's depth are both pinned now, the second recomputed in the test
from the curves the result already carries. A refusal that also CLEARS — what
the old sentence wrongly claimed — is pinned too. The fourth was not a defect
but an unfounded claim: shuffling `cx` and `cy` independently barely moves the
certification rate (7 of 60 against 3 of 60), so the comment calling the
pairing load-bearing is corrected rather than pinned.
**Fixed the same day:** the refusal sentence claimed "the rotation is left as
Not set", which the code never establishes — it declines to write and never
clears, so an earlier fit, a session restore, a manual entry or a value from
the file survives while strain, ACOM and DPC keep consuming it. Now "not
updated", pinned by a test.
**Also owed:** the refusal is a 264-character sentence routed to `statusText`
alone, not an alert, and the diagnostics panel still says "the marker is the
chosen minimum" beside an angle that was deliberately not written
(`UI/WorkspaceInspector.swift:722`). **Unverified on screen.**
**The Gate B numbers above came from a scratch probe that was never checked
in. `tools/rotation-null-probe` (diagnostic, 2026-09-15 night) is the
instrument now, with its own generators, and it does NOT reproduce all of
them** (`rotation-probe-final-20260915.log`): white noise sd 0.010 at 40 × 40
certifies **10 of 200**, the 1-in-16 design rate, not 50; 3 × 3 box-smoothed
noise certifies **19 of 60 at 40 × 40 and 26 of 60 at 100 × 100** (32–43 %,
not 60–80 %); a per-row drift spanning 0.05 px over noise sd 0.010 is
certified **0 of 6** (depth 0.4–0.9× the shuffles), so the recorded 6 of 6 at
6–20× used a larger drift than the entry states; a 0.05 px specimen edge is
certified **6 of 6** at 1.4–2.1×; planted 30° at sd 0.03 is certified 60 of
60 with 8 over 5° and one 63.7° out; 0 of 60 real rotations refused. The
qualitative claim stands — structure without rotation is certified, and a
certified angle can be 60° out — and the rates in the bullets above are the
scratch probe's, superseded by the harness's where they differ.

---

## The zone-axis fit's chance floor does not mark the case it was built for — narrowed 2026-09-15 night

**Closure:** the case is marked now, by a second null (the sweep's own median) rather than by a threshold on the disc model; the Gate D record and residuals are the live entry in [`../open-items.md`](../open-items.md). The 2026-09-14 text follows.

### The zone-axis fit's chance floor does not mark the case it was built for — added 2026-09-14
**Known, scoped, partly addressed.** `ZoneAxisFit` now carries
`chanceMatchedVectors` from the same `chanceMatchFraction` the matcher's guard
uses, and the panel marks a row "at chance". **It does not mark the ⟨112⟩ at
8 % that motivated it.** Measured by Gate B at the app's default reference
settings: aluminium's ⟨112⟩ entries carry 12-16 reference vectors, not the 48
the cap allows, so the expectation is 0.37-1.3 % and 8 % clears five times it.
The mark fires only while each pattern's second-largest |u| stays under about
0.55-0.63 Å⁻¹, and Al {220} alone is at 0.699. Reproduced on an owner-like
sample: ⟨211⟩ explained 2.32 % against 0.369 % chance, ratio 6.29, no mark.
**A second measured limit:** the uniform-disc model is well calibrated on
vectors drawn uniformly over the disc (14 matched of 1 379 against 11.4
expected) and understates chance about sixfold for vectors confined to the
radii the references occupy (63 of 1 408 against 10.7) — which is what real
spurious peaks look like. Both numbers are asserted in
`ZoneAxisFitTests.testAFitOnRandomVectorsIsAtChanceAndAPlantedOneIsNot`, so a
reader reproduces them by running that class. What the change bought is the
number itself, reported instead of absent. The threshold that would catch the
owner's case is not established: Gate D owed.

