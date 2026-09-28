# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Raw Al-Mg-Si cube, stride 3, calibrated from its own lattice (2026-09-29; registered `f06dd1f`) | Every prediction held: Q 0.006577 Å⁻¹/px (−0.34 %; the file 1.74× off), ratio 1.0846, 20.8°, [001] 92.9 %, matrix 86.4 %. Found: GPU memory grows per tile in `detectAll` (probe killed at 1.6–2.1 GB; autoreleasepool per tile holds ≈ 500 MB) — **Gate D owed, not in the app on big cubes yet**; the px-based match tolerance leaves 97 % not indexed on a 256² detector. |
| Bragg disks restored from the session sidecar (2026-09-29; registered `3a4e4d5`) | The peaks the sidecar always wrote are read back and adopted automatically when load spec, detection step, shapes and provenance all match; the nil-kernel staleness hole closed. 16 tests, each broken first. Unit **932 / 0 / 2 = 934** (`unit-bragg-restore-manual.log`). Open: seed the detection controls from the step; unverified on screen. |
| The owner's 28 GB raw cube subsampled from the SSD (2026-09-29) | Opened memory-mapped on the physical exFAT SSD (footprint 3 MB); stride 3 at the full 256² detector → 110² × 256² float32, 3.17 GB on the SSD in 34 s, footprint ≤ 53 MB, **12 100 / 12 100 patterns bit-identical** to the raw. Record `archive/v4/ssd-subsample-2026-09-29.md`. Not yet analysed. |
| Stride 3/6/9 invariance, Thronsen A (2026-09-29; registered `33e370d`) | Labels identical at 100 % of kept positions; phase fractions within 0.33 pp (held). Object densities and lengths are grid- and minimum-size-dependent (T1 +24 % at stride 9, edge-on 12 → 38 objects; the truth map does the same): refuted as invariant. `tools/phase-map-probe --scan-stride/--pixel-nm/--min-size`. Record `archive/v4/stride-invariance-registration-2026-09-28.md`. |
| Areal density edge correction, Gate D (2026-09-28; registered `c2450e9`, ADR 045) | Miles–Lantuéjoul weights in `PrecipitateStatistics.density`. Synthetic foil: current rule 0.88–0.96 at d ≥ 100 (0.890 at Thronsen geometry), corrected passes all 18 cells after hypothesis M (margin plates escaped rejection) held; refuter NOT REFUTED, 4 fixes applied. New tests red on the old rule and on 3 mutations; 5 pinned values re-derived by hand. Unit **917 / 0 / 1 = 918** before the refuter's fixes (`unit-edge-20260928.log`). |
| T6 volumetric density, synthetic foil (2026-09-28; registered `e0f712b`, amended `dad913f`) | Run 1 as registered: every estimator FAILS (a 1, b 8, c 1 cells; naive 12). Diagnosed: the d 20 deficit is length read ~1 px long (D1/D2, oracle lengths 0.986–1.013). Refuter: holds, but Nie–Muddle (c) is exact only for one plate size (0.82–0.94 polydisperse) — not built; the shipped **areal** density read ≈ 11 % low from the edge rule — fixed, ADR 045. `tools/volumetric-density-test` (diagnostic). |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

Earlier gate rows — 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-28 evening

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23 (4.0.0 / 7, macOS 27+). `main` carries the day's work unpushed: fixes and ADRs 039–044, A2 truth, C2 spike, B1, A3a, the paper notes, the phase-slot change (`f633216`, `9b483cb`). | Owner: push; next cut. |
| **Next — `ROADMAP.md` (revised 2026-09-28 evening)** | Order: **1** ~~the 915-pt launch crash~~ fixed (sidebar max 270); **2** precipitate polish: ~~the per-phase slab field~~ (landed, seen), the polishing pass, then thickness → density; **3** the owner's own Al-Mg-Si scans subsampled in real space; **4** where precipitate analysis lives (owner's call); **5** on-device training in the Disks section. | Owner: the areal edge correction (Gate D) and whether to pursue volumetric density through a polydisperse bar; then the rest of the polish. |
| **Owner owed** | Thronsen's written confirmation (ADR 042); where precipitate analysis lives. | Owner. |
| Phase mapping | Unvalidated. T4 one metric short (edge-on speckle 7 > 5; 3 of them edge calls, 4 real). The owner's in-app run is close; recipe: θ′ twice ([100], [001]), T1's own relationship, minimum size 10. | Polish (roadmap 2). |
| **Unverified on screen** | The Bragg restore (`"Disks restored from the session"` on opening Thronsen A). Earlier row emptied: Driven 2026-09-28 night on a scratch build of `04af66e` + the slab row (a Sonnet driver, every shot reviewed; owner's go): sidebar max 270 pt; Settings › Analysis has one toggle, no engine picker; θ′ added twice with its status and same-axis refusal; R–Q on `Particle_1…bin8.h5` shows +78.6° transposed (py4DSTEM +80.0° T: sign checked, magnitude not — origin fit RMS 18 px); the slab rows (grey 0,050, typed 0,300, cleared). | — |
| Carried | R–Q residuals; the 28 GB DM4 parity run and parallax/ptychography drive on the stronger Mac; C2's memory and criterion 4; the 119-defect triage; CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
