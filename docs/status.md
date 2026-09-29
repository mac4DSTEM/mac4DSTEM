# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Raw Al-Mg-Si cube, stride 3, calibrated from its own lattice (2026-09-29; registered `f06dd1f`) | Every prediction held: Q 0.006577 Å⁻¹/px (−0.34 %; the file 1.74× off), ratio 1.0846, 20.8°, [001] 92.9 %, matrix 86.4 %. Found: GPU memory grows per tile in `detectAll` (probe killed at 1.6–2.1 GB; autoreleasepool per tile holds ≈ 500 MB) — **fixed overnight A1** (classical; harness `tiled-detection-memory-test`, 473 → 1 MB over 12 tiles); the probe's one-pixel match tolerance leaves 97 % not indexed on a 256² detector (the app ships 0.02 Å⁻¹ = 3 px there — unmeasured; corrected overnight D1). |
| Bragg disks restored from the session sidecar (2026-09-29; registered `3a4e4d5`) | The peaks the sidecar always wrote are read back and adopted automatically when load spec, detection step, shapes and provenance all match; the nil-kernel staleness hole closed. 16 tests, each broken first. Overnight A2: the detection controls (all 12 parameters, detector class, learned threshold) are seeded from the recorded step on adoption, so a kernel built later keeps the disks current; 9 more tests, 7 mutations red. Unit **941 / 0 / 2 = 943** (`unit-A123.log`). Unverified on screen. |
| The owner's 28 GB raw cube subsampled from the SSD (2026-09-29) | Opened memory-mapped on the physical exFAT SSD (footprint 3 MB); stride 3 at the full 256² detector → 110² × 256² float32, 3.17 GB on the SSD in 34 s, footprint ≤ 53 MB, **12 100 / 12 100 patterns bit-identical** to the raw. Record `archive/v4/ssd-subsample-2026-09-29.md`. Not yet analysed. |
| Stride 3/6/9 invariance, Thronsen A (2026-09-29; registered `33e370d`) | Labels identical at 100 % of kept positions; phase fractions within 0.33 pp (held). Object densities and lengths are grid- and minimum-size-dependent (T1 +24 % at stride 9, edge-on 12 → 38 objects; the truth map does the same): refuted as invariant. `tools/phase-map-probe --scan-stride/--pixel-nm/--min-size`. Record `archive/v4/stride-invariance-registration-2026-09-28.md`. |
| Areal density edge correction, Gate D (2026-09-28; registered `c2450e9`, ADR 045) | Miles–Lantuéjoul weights in `PrecipitateStatistics.density`. Synthetic foil: current rule 0.88–0.96 at d ≥ 100 (0.890 at Thronsen geometry), corrected passes all 18 cells after hypothesis M (margin plates escaped rejection) held; refuter NOT REFUTED, 4 fixes applied. New tests red on the old rule and on 3 mutations; 5 pinned values re-derived by hand. Unit **917 / 0 / 1 = 918** before the refuter's fixes (`unit-edge-20260928.log`). |
| T6 volumetric density, synthetic foil (2026-09-28; registered `e0f712b`, amended `dad913f`) | Run 1 as registered: every estimator FAILS (a 1, b 8, c 1 cells; naive 12). Diagnosed: the d 20 deficit is length read ~1 px long (D1/D2, oracle lengths 0.986–1.013). Refuter: holds, but Nie–Muddle (c) is exact only for one plate size (0.82–0.94 polydisperse) — not built; the shipped **areal** density read ≈ 11 % low from the edge rule — fixed, ADR 045. `tools/volumetric-density-test` (diagnostic). |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

Earlier gate rows — 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-29 night

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23. `main` carries 79 unpushed commits since `49759b9`: 2026-09-28's ADRs 039–044, and that night's crash fix, slab row, Object Table, areal edge correction (ADR 045), Bragg restore, stride test, SSD subsample writer, raw-cube calibration, "Rules serve the app". | Owner: push, then start the overnight session. |
| **Next — the overnight plan** | `archive/v4/overnight-plan-2026-09-29.md` (kickoff prompt §6): **A** the disk-detection memory fix (diagnosis held), Bragg-restore settings + drive, Object Table highlight; **B** every on-screen debt, driven; **C** consolidation; **D** YELLOW science, measure only. | The overnight session. |
| **Owner owed** | Thronsen's written confirmation (ADR 042); where precipitate analysis lives; morning review of "decided overnight — overrule on sight". | Owner. |
| **⚠ Don't run** | Detect All Disks with the **learned** detector on multi-GB cubes (its tiled loop is not pooled; classical fixed overnight A1). | — |
| Phase mapping | Unvalidated. T4 one metric short; D1 measured: the shipped max(0.02 Å⁻¹, 1 px) lies inside all four datasets' bands (raw 060 cube: matrix 84.4 % at the app's 0.02); `archive/v4/phase-tolerance-results-2026-09-29.md`. | Overnight D. |
| **Unverified on screen** | — (emptied overnight 2026-09-29 by two reviewed drives: `archive/v4/overnight-2026-09-29-shots/`). | — |
| Carried | R–Q residuals; the 28 GB `--parity` run; parallax/ptychography drive; C2's memory and criterion 4; the 2026-09-09 register's 11 Gate D candidates (triaged overnight); CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
