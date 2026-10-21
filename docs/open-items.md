# Open items

Triaged 2026-10-21 (clean slate after the kit switches, pins SpectroKit 0.7.1, FormatoKit 0.7.0, DiffractoKit 0.7.1,
CuboKit 0.6.0, ImagoKit 0.4.0). Three lists: **Kit asks** (the kit ships it, the app re-pins), **App work** (the app's own
defects and debts), **Drop** (done, obsolete or retired, one line each). Status is `docs/status.md`; the full pre-triage
text is in git history and `../_archive/mac4DSTEM/docs/archive/`. Each item <= 4 lines. Kit-side copies that wait for an ask
carry a `// delete at <Kit> <version>` marker in the code (`git grep "delete at"`).

## Kit asks

### CuboKit (next: 0.7)
- **Ptychography engine, Float path with cancel and progress.** The kit's Double engine is 4.2x slower and twice the memory, so
  `SingleslicePtychography` stays (agreement 3.4e-6, `PtychographyKitSwitchTests`). A measuring thread owns the numbers.
- **Parallax alignment, a faster Double FFT or Float shifter.** Kit 2.71 s against 0.58 s (about 5x) on 121 images at 160x160, so
  `ParallaxAlignment` and `MatrixDFTCorrelation` stay.
- **Hot-pixel filter.** `HotPixelFilter.filter()` accumulates the mean in Float32, the app's Double mean stays beside the kit's
  `mask` / `replacing` (numpy is float32; the 060 cube matches py4DSTEM exactly, margin unmeasured).
- **Disk detection options:** keep the integer position on a non-finite refinement; pointer/stride `fillNonFinite`; a
  smoothed-surface entry. **Strain:** a `LatticeStrain` diagnostics entry for the `initialBasis` path.
- **Embedding:** sklearn `svd_flip` signs (the kit's provisional sign, largest entry positive, flips saved embeddings; CHANGELOG).
- **Origin:** `SyntheticProbe.make` with a centre parameter (the app's probe is pixel-centred, the kit's half-pixel for odd
  sides, which changes sim_Au counts), a mask hook for the measured sigmoid kernel; a GPU form of `OriginMeasurement` (the app's `measureOrigin` kernel is Metal, the kit's is CPU); per-position origins (C3).

### FormatoKit (next: 0.8)
- **Single-pattern HDF5 read, 0.5 ms.** The kit opens the file per call: a one-pattern read of Au_sim.h5 went 49 us -> 540 us
  (tile and row reads equal). Ask: a handle-holding slab read; the app's `HDF5LegacyProbe` shim stays until then.
- **Link walk with object identity** (`descendants` lists aliases twice and throws at a cycle); h5py bool-enum attributes.
- **Sidecar writes:** `SessionSidecarWriting` and the app's HDF5 writer binding onto `HDF5WriteSession` (needs a sidecar-parity
  run, about 35 GB); `write(vectors:)` is too wide for 0.5's append writer.
- **DM4:** lazy 4D gather (the kit's `DM4Datacube` was 7.6x slower on a float32 whole-scan tile and always maps non-local volumes),
  DM3 / declared length 0, rank-3 scan-shaped objects, more than four dimensions. `DM4Reader` stays.
- **MIB / EMPAD:** header-less MIB; an EMPAD precedence option (`scan_resolution` against `pix_x/pix_y`).
- **Velox:** live/real times (`/Data/SpectrumImage`) are not read; allocation from file sizes is unbounded for `markersPerFrame` and
  the per-column loops of `readFrameTransformations` / `readFrameDetectorTimes`; GMS EDS geometry (`Stage tilt`, multi-segment list)
  and beam energy are not read, so GMS absorption is refused (also SpectroKit).

### DiffractoKit
- **Q calibration:** a linear-scale-from-reference-ring helper (the app's `KnownCrystalQCalibration` has no camera length L; the
  kit's `RingCalibration.q` needs it). The pre-cut list peaks about 800 MB for a 30 A cell at kMax 2.5.
- **Phase matching:** `minimumVectors` = 2 makes "matrix" by exclusion and the cross-phase winner ignores completeness
  (`completenessAwareCrossPhaseRanking` off, byte-identical on the demo cube). Diagnose before any edit (`/diagnose`).
- **ACOM mirror:** `inPlaneAngle` of a mirrored win is angle + pi, published raw in `acom_in_plane` with no per-pixel flag; and
  `selectOrientation` compares forward and mirrored in-plane bins (secondScore/reliability only). Zone axis misses up to 12.8
  degrees beyond the bank sampling; off-grid self-recovery fails 37-43 of 200 at 1.4 degrees; the mirror pass costs about 7/144 trials.
- **CIF symmetry:** a list shorter than the IT group is refused, but a group named by H-M alone is unchecked, a partial list in a
  primitive-looking cell passes, a primitive C-monoclinic cell with beta = 90.00 is falsely refused.

### SpectroKit
- **Public initialiser for `LineConflict`** (`autoid-velox-check --replay` is off without it); 18 app test files reach `package`
  API through `@testable import` (a Debug-only build); `SpectrumImageMetadata.sameScanAs4DCube` keeps its 4D name (rename moves a golden).
- **Fit on real Al alloys:** the continuum absorbs the Al K alpha high-side misfit; a weak Mg K alpha reads about 300 counts low and
  Si 8.7 % low (the owner's pure-Al spectrum is the remedy); sigma is 5-12 % small on weak lines; unlisted strong lines (Ge, Cu, Ga)
  hold Ti at 0; the order-5 upper segment is stiff. Fix F2/F3 refuted, needs a new registration.
- **Auto ID:** proposes Eu/Hf/Ho on Al pools, misses Mg in 37 of 38 Al-Mg-Si files; the beside-K drop and R2 were refuted; a Lu M alpha
  proposal sits on the Al K notch; sum-peak phantoms still absorb pile-up; a line-case `rankDeficient` (La K alpha = Cd K alpha + Tl L alpha) remains.
- **Quantification:** at% needs a K line per element; live-time normalisation is not applied; the refined axis is poor below about 10^4
  counts; `Data Order Swapped` = 1 on an EDS SI is refused; the detector resolution is assumed 130 eV at Mn K alpha; a negative live time should count as corrupt.

## App work

Ordered as the ROADMAP takes them.
1. **Notarisation (the Developer ID archive itself was verified 2026-10-20).** An ad-hoc Release build (Hardened Runtime) does not launch (library validation: FormatoLibHDF5 and the app
   share no Team ID); Develop does. Run the archive, notarisation and the Hardened Runtime load as the release proof.
2. **Number density N_V with thickness** (study item). v2 refuted as registered 2026-10-15 (P1' failed by one cell, P4' by two); nothing
   landed (ADR 050). Needs a new registration; thickness comes typed +- sigma until SpectroKit EELS t/lambda lands.
3. **Phase mapping object bar (ADR 040):** FAIL on theta-prime edge-on raw spurious 7 > 5; T1 edges called Al (204) mostly where the truth
   draws the edge; no global or narrow guard shipped. Ships badged unvalidated; the matrix verdict is by exclusion (see DiffractoKit).
4. **Known-crystal Q reads the (200) ring as (111) on an Al [001] majority** (Q 12.5-13.5 % low, shell ratio 1.37-1.43 vs 1.155); only
   "Shell ratio unchecked" ships. The fix (ring-sequence assignment) needs a design pass; 2H-WS2 selects (0002), no l-filter; the caveat is not persisted.
5. **Origin fit holes:** which statistic gates `originFitIsSane`; the trimmed fit is blind to clustered contamination >= 50 %; the coarse block
   seed lands 0.5-2.8 px off on noisy cubes (`windowSensitivityPixels` is not surfaced); the ellipse fit leaves a ring outside its annulus
   (Au_ref) and `fit1D` ends `didNotConverge` in 54 of 150 contiguous arcs (a refusal, never a wrong fit).
6. **Rotation calibration:** a test that fails on the old Float refinement, and the Al-Mg-Si angle against py4DSTEM's float64 -82.6 degrees; the
   rotation null loses power at the highest noise ("measured -67.5" recurs about 1 in 30); the ptychography rotation branch is unchecked.
7. **Lineage and replay residuals:** Clear Calibration makes no calibration node; a Q edit deletes the ACOM map instead of marking it stale;
   a sidecar-restored map has no task-row verdict; replay contracts live in three places (`ProductWorkflow.currentReplaySignature`,
   `ReplayRecordFrameMap.role`, `ReplayPlanner.parse`); strain, ACOM and DPC steps publish under the current mode's keys; `learned_model_sha256`
   is read live at record time; parallax/ptychography are not in the replay record; a user analysis mid-replay steals Cancel.
8. **Session file shared by stem:** `scan.dm4` and `scan.h5` map to one `scan.mac4dstem.h5`, so opening one adopts the other's calibration
   (a 2x-binned conversion: Q off by 2). An identity check is built and archived, not shipped; a schema-5 sidecar's stored disks are refused.
9. **room-switch defects:** after an ACOM preview Imaging shows the ACOM map; Strain "No Result Yet" after an Orientation visit;
   the ptychography pane titled "Parallax aligned BF" before a run; stored Bragg disks restore at a same-size crop's positions (D3 b).
10. **Crash after Compute Strain:** an AppKit layout exception (`_layoutSubtreeWithOldSize`) once after a label export and Detect All; not
    reproduced. Also: ⌘O / Preprocess Raw Data… opens a second window; ⌘6 with no spectrum image opens an empty room; a hidden window
    tab's `.onDisappear` is unverified; shrinking the window to its floor collapses the sidebar for good.
11. **Spectroscopy room, owner's drive owed:** shell glass, the 18-column table, EDX products for an EMD opened alone, per-line fitting; the
    cube's kV is captured once at attach; the weak-line sentence; a locked GMS axis shows a trivial +-0.0 % statement; below 0.2 keV the Expert field resets silently.
12. **HDF5 and DM4 robustness:** `hdf5-exit-race-test` aborted with status 70 in 1 of 200 runs under heavy load (cause open; 1200 reruns
    clean); quit waits for an HDF5 call in flight (30 s from a slow drive, unbounded on a stalled volume); a DM4 on a disconnected disk refuses every later read
    until reopened; HDF5 runs under one lock with thread-safety resting on a 2026-08-19 `nm` inspection.
13. **Test-run traps:** `KitSwitchFreezeTests` preset digests pass in the full suite and fail when the class runs alone (run-context
    dependence); `sources.manifest`'s `kit_module` links every `*.o` in `.build/<kit>-tools`, so delete that folder after a pin change;
    the learned detector refuses a Mac with no Neural Engine and re-runs a 0.3 s check per live preview.
14. **Number-field and presentation nits:** typing exactly the shown text of a finer stored value is a no-op; the ACOM Q read-out decimal point; `ACOMSession.estimatedDuration` is ~2x optimistic under the x2 CPU pass (AppState.swift:616,625).
    Annulus with inner 0 excludes the centre pixel (py4DSTEM convention unchecked); region circle radius takes centres up to 1/2 px outside the ring (R 5: 97 px vs 81);
    `QuantitativeBadge` ignores the origin gate outside ACOM; on-screen `Colorbar` takes the nearest LUT entry; no colourbar in figures.
15. **Data and export:** a strided or detector-cropped export carries no replay recipe; the bin's float32 sum order is not numpy's (<= 1.14e-4);
    a session voltage above 1000 kV reopens divided by 1000; scan-fastest DM4 detector pair order unverified against GMS (owner: leave it);
    `DatasetPreviewBuilder.stride` and the "Streamed" figures count post-bin bytes; the phase-contrast budget does not sum held products.
16. **Accessibility and SwiftUI:** re-read the VoiceOver values fixed 2026-10-13 on screen; the detector panes' crop is drag-only; the lineage focus
    ring; `RoomAccessibilityText.steppedZoom` is used only by its test; Swift 6 mode (64 diagnostics, about 3.5-6 sessions, the owner schedules it);
    ⌘R's readiness predicate and the toolbar's `primaryActionEnabled` are two copies; rename `residentMemoryMB` to `appMemoryMiB`.
17. **Refactors parked:** `ResultExport` and `BraggVectorEMDWriter` splits (the latter's file split landed; the dataset-kind split remains);
    a shared harness `fail` helper (second-lane review); the >1000-line harness mains; five `median` bodies stay separate (ADR 015, do not merge).
18. **Harness gaps:** `compare.py` peak positions pinned on this Mac's GPU only, 4 datasets UNPINNED, `if not actual:` unkillable, the runner aborts at
    the first red harness; some tests still assert numerics exactly where a written tolerance is owed (D12); `sidecar-parity` and `indexing-parity` harnesses do not exist.
19. **Owed on screen:** the four failure paths to the status strip, the disk-centre label round trip, the Train Model… drive (owner's build), the
    sandbox warning when no grant, Reduce Transparency on the glass shell. No automated visual baseline exists.
20. **Learned detector and training:** the #18 training campaign cannot reproduce the app's Si_SiGe strain; learned detector above 256 px
    unchanged, below 256 px with an off-centre probe still scales by the crop maximum; the inter-labeller check on 370 centres; bullseye
    detection accepts noise; twisted bilayer graphene finds only the beam; T1 [0 -4 1] has 252 not-indexed positions (detection noise).
21. **Smaller trust items:** an unmarked pre-2026-09-28 export keeps its R-Q reading (`Si-SiGe_calibrated.h5` is one); ACOM Euler angles differ from
    py4DSTEM/orix by a frame rotation (relabel or convert, then a second-lane review); a file ellipse with a non-positive semi-axis is dropped silently, not refused by name.

## Drop

- Switched 2026-10-21 onto the pinned kits: `fitOriginTrimmed` is `OriginFit.fitTrimmed` (CuboKit 0.6.0; `kept` and both residuals are the kit's); the preset crystals are `CrystalPresets`; the Metal ACOM backend is `ACOMMatcher.matchAll(backend: .metal)` (the kit's selection and preview expansion, `MetalACOMMatcher` and its shader gone); the virtual image, mean/max and centre-of-mass Metal one-shots and their four shaders are gone (CuboKit's reducers). Stays: the selected-area sum (`virtualDiffraction`; the kit's `VirtualDiffraction.pattern` is CPU-only) and the per-position origin kernel (`measureOrigin`).
- Learned detector training and refine stay in the app, not ready for a kit (Paul, 2026-10-21 12:29; ADR 071).
- Kit asks after session 5, "Done and ticked" list (Float32 detection, fillNonFinite, HotPixelFilter.Replacer, ptycho probe, parallax correction/depth/position, streamed PCA, strain diagnostics, ACOM, Materials Project, DM4/DM3, HDF5 chunk/float16/bool, MIB, EMPAD): done in session 5.
- "Kept in the app on purpose" (lineage and marks, header-less MIB, rank-3 reshape): restated in the kit asks above.
- Release-build signing and FormatoKit 0.4.0 HDF5 frameworks: Developer ID archive was done 2026-10-20; the open proof is App work 1.
- Phase 2 plan per kit (CuboKit, FormatoKit, DiffractoKit, SpectroKit lists, C3 locations, QCalibration compare): executed or restated as kit asks; plan retired.
- CuboKit "Rules serve the app" bullet (FriedelOrigin, BeamstopMask, negative radius, 0.08 s resident image): switched 2026-10-16; a resident-cube image cost was CuboKit 0.2.1's, gone.
- DiffractoKit pinned 0.5.0 note, replay scale guard constant, ParallaxAlignment-not-ImagoKit note: history; the facts live in the code and the kit-ask lines.
- Probe radius from the max pattern: done 2026-10-20 (CHANGELOG).
- Tiled GPU memory (gated flat; two untracked residuals), origin validity mask disclosure, 2026-09-09 register residuals other than item 7: observations, no live defect.
- ACOM mirror residual (ii) sub-bin deposit; Q1b healthy-cube table; NiCu_COPL: measured records, no rule proposed.
- Number density v2 patches and logs, ellipse two-start record, annulus guard g: refuted records in the archive; the live item is App work 2 and 5.
- UI audit 2026-10-14 leftovers: rooms redriven since; the live pieces are in App work 14, 16.
- Velox `.emd` as one-row cube, Velox parity diagnostic: fixed in v5.0 / tool archived to `../_archive/mac4DSTEM/tools/velox-parity`.
- Region mouse-wheel zoom: closed by the owner 2026-10-07 (no AppKit).
- R3 Quantify drive notes, WP3c, A2, A4 and drive 5/9/13 narratives: landed and recorded in ADRs 056-062; live gaps are in Kit asks, SpectroKit.
- Lane F-B (b)(c), F-C (3), review lane F pinning note, S4/S5 wording residuals: fixed 2026-10-01/16 or merged into App work above.
- Scan-fastest DM4 pair, HDF5 at quit, Velox allocation caps: kept above in one line each; the long write-ups are history.
- Acceptance-harness S19 and ANE return detail: kept in App work 18 and 13; ADR 040 pause note retired.
- New-Mac bring-up (28 GB parity, parallax cost, py4DSTEM graphene comparison, C5 training run): done 2026-09-30 to 10-01, recorded in `../_archive/mac4DSTEM/docs/archive/v4/`.
- Accessibility `EXC_BAD_ACCESS` 2026-09-08: never recurred; `disk.advancedDisclosure` shared identifier left as is.
- Swift 6 cost lanes, Apple-docs checks (liquid glass, deprecation sweep, Core ML vs CoreAI), `.fixedSize()` audit: decided or measured; the schedule is App work 16.
- Minor tooling (free-space.sh constants, velox-parity venv, Dependabot torch 2.13 block): the tools are archived; the torch pin stays 2.11.0.
- Process items (registrations, Gate B/D wording, lane G gate work, drive block, dead-code pass): retired 2026-10-15 or done 2026-10-21.
