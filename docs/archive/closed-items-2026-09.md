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

