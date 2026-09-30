# Status history — gate rows retired 2026-09-29 night (verbatim)

Moved out of `docs/status.md`'s "Last gates" table by the overnight closeout; each row as it stood at `e1b24e1`.

| Gate | Result |
|---|---|
| The owner's 28 GB raw cube subsampled from the SSD (2026-09-29) | Opened memory-mapped on the physical exFAT SSD (footprint 3 MB); stride 3 at the full 256² detector → 110² × 256² float32, 3.17 GB on the SSD in 34 s, footprint ≤ 53 MB, **12 100 / 12 100 patterns bit-identical** to the raw. Record `archive/v4/ssd-subsample-2026-09-29.md`. Not yet analysed. |
| Stride 3/6/9 invariance, Thronsen A (2026-09-29; registered `33e370d`) | Labels identical at 100 % of kept positions; phase fractions within 0.33 pp (held). Object densities and lengths are grid- and minimum-size-dependent (T1 +24 % at stride 9, edge-on 12 → 38 objects; the truth map does the same): refuted as invariant. `tools/phase-map-probe --scan-stride/--pixel-nm/--min-size`. Record `archive/v4/stride-invariance-registration-2026-09-28.md`. |
| Areal density edge correction, Gate D (2026-09-28; registered `c2450e9`, ADR 045) | Miles–Lantuéjoul weights in `PrecipitateStatistics.density`. Synthetic foil: current rule 0.88–0.96 at d ≥ 100 (0.890 at Thronsen geometry), corrected passes all 18 cells after hypothesis M (margin plates escaped rejection) held; refuter NOT REFUTED, 4 fixes applied. New tests red on the old rule and on 3 mutations; 5 pinned values re-derived by hand. Unit **917 / 0 / 1 = 918** before the refuter's fixes (`unit-edge-20260928.log`). |
| T6 volumetric density, synthetic foil (2026-09-28; registered `e0f712b`, amended `dad913f`) | Run 1 as registered: every estimator FAILS (a 1, b 8, c 1 cells; naive 12). Diagnosed: the d 20 deficit is length read ~1 px long (D1/D2, oracle lengths 0.986–1.013). Refuter: holds, but Nie–Muddle (c) is exact only for one plate size (0.82–0.94 polydisperse) — not built; the shipped **areal** density read ≈ 11 % low from the edge rule — fixed, ADR 045. `tools/volumetric-density-test` (diagnostic). |

## Moved 2026-09-30 (S2), verbatim

| Gate | Result |
|---|---|
| Raw Al-Mg-Si cube, stride 3, calibrated from its own lattice (2026-09-29; registered `f06dd1f`) | Every prediction held: Q 0.006577 Å⁻¹/px (−0.34 %; the file 1.74× off), ratio 1.0846, 20.8°, [001] 92.9 %, matrix 86.4 %. Found: GPU memory grows per tile in `detectAll` (probe killed at 1.6–2.1 GB; autoreleasepool per tile holds ≈ 500 MB) — **fixed overnight A1** (classical; harness `tiled-detection-memory-test`, 473 → 1 MB over 12 tiles); the probe's one-pixel match tolerance leaves 97 % not indexed on a 256² detector (the app ships 0.02 Å⁻¹ = 3 px there — unmeasured; corrected overnight D1). |
| Bragg disks restored from the session sidecar (2026-09-29; registered `3a4e4d5`) | The peaks the sidecar always wrote are read back and adopted automatically when load spec, detection step, shapes and provenance all match; the nil-kernel staleness hole closed. 16 tests, each broken first. Overnight A2: the detection controls (all 12 parameters, detector class, learned threshold) are seeded from the recorded step on adoption, so a kernel built later keeps the disks current; 9 more tests, 7 mutations red. Unit **941 / 0 / 2 = 943** (`unit-A123.log`). **Seen on screen** overnight (drives 1–2): the restore line, the seeded controls current after Build Kernel, and in-app re-detection reproducing the same 754,479 peaks. |
| **Overnight 2026-09-29** (plan `archive/v4/overnight-plan-2026-09-29.md`, its Log; shots `archive/v4/overnight-2026-09-29-shots/`) | Unit **961 / 0 / 2 = 963**, reconciled (`unit-sm.log`, the last of five runs); inventory exit 0 at every commit. A1 disk-detection memory fixed (a pool per tile + exact-size peak arrays; `tiled-detection-memory-test` gated: 473 → 1 MB over 12 tiles; in-app Detect All on Thronsen A flat at ≈ 1.18 GB, 754,479 peaks); A2 controls seeded; A4 table → map highlight; an **AI-room constraint-loop abort** found by drive 3 (pre-existing) — the room's rows fixed and guarded (`InspectorWidthBudgetTests`), **the Info tab at 915 pt and a widest inspector drag still abort** (Frozen Shell, owner); D1 tolerance measured (the shipped rule fits all four datasets); the 2026-09-09 register triaged. |

Moved 2026-09-30 (clearing batches closeout):

| Gate | Result |
|---|---|
| Session queue S2, workspaces (2026-09-30) | Unit **957 / 0 / 1 = 958**, reconciled with 958 `func test` (967 − 10 per-room width tests + 1 loop over every workspace/task pair); run as the unit lane's own `xcodebuild test` line (`unit-s2.log`) because 3.9 GB free is under its 4 GB floor. Both new tests broken first: phase mapping routed to Imaging → `testWorkspacesFollowTheData` red; Bragg Disks routed to nothing → the width loop red (`mut-s2.log`). One skip, `TB1StallProbeTests` (was 2). |

## Gate rows moved at the 2026-09-30 closeout

| Gate | Result |
|---|---|
| Clearing batches landed and driven (2026-09-30) | Gate D per science item, an independent refuter or supervisor each (records in `archive/v4/`: register D006/D021/D079, IPF key, training leak, learned windows D098/D004; ADR 047 amendment for L4). Unit on `0864244`: **1187 / 0 / 1 = 1188**, reconciled with 1188 `func test` (`close-unit.log`, exit on its own line). Harnesses: 15 scientific harnesses touching today's Core changes exit 0 (`close-h-*.log`); `sidecar-result-test` was red on a stale schema pin ("6"; the writer is 7 since `aa920d0`, by design) — pin updated, green. Drives: 15 rows verified, 1 partial, 2 defects found (legend swatch fixed `e90f168`; Clear Calibration and ptychography filed) (`archive/v4/drives-2026-09-30.md`). |
| S3 Friedel speed, Gate D (2026-09-30) | `friedel-timing` on Thronsen A: 3 572 positions/s at `-O` (8 s), 38/s at `-Onone` (765 s), footprint flat; reads 6 600–7 000/s either way, so the serial-read hypothesis is refuted. The Debug app linked `DSTEMCore` at `-Onone`; `Package.swift` now builds both packages `-O` in Debug (build log: `-Onone … -O`, last wins). Unit **964 / 0 / 1 = 965** (`unit-s3d.log`). The drive's falling-rate shape is not reproduced — re-drive owed. |
| S3 number entry, Gate D (2026-09-30) | In a comma-decimal region the lenient parse read `0.0275` as 275, `0.020` as 20, `0.2` as 0 (clearing the file's Q) — reproduced in the app and in a script; the 09-07 "emptied field clears Q" record refuted (empty throws, the field reverts). Fix: `DecimalEntryFormat` under every numeric field; Q/R/voltage empty show "Not set" and commit nothing. Refuter (Opus) broke the first grouping rule (`0.0.275` → 275, integer `1.600` → 1); fixed and pinned. Unit **964 / 0 / 1 = 965** (`unit-s3b.log`); four mutations red. Seen on screen (scratch build): `0.0275` → 0,0275 Manual, emptied field kept it, voltage 0 → "Not set", `300.5` → 300,5 kV; the typo refusal is unit-tested only. |

### Gate rows moved 2026-09-30 evening (new-Mac closeout)

| Gate | Result |
|---|---|
| Overnight S12–S23 (2026-09-30 night) | Unit on `3cb567e`+S22: **1279 / 0 / 3 = 1282**, reconciled with 1282 `func test` (`unit-final.log`, exit on its own line); baseline 1203 / 0 / 2 = 1205 on 453f344 (`unit-base.log`). New harnesses: `virtual-detector-memory-test` (12 PASS), real-data positions (run.sh exit 0, 73 s), cif-symmetry-test exit 0. Every item Fable-supervised; drives 1, 2A, 2B on scratch builds (`archive/v4/drives-2026-09-30-night-shots/`). YELLOW S14, S20, S21 pre-registered, measured, recorded (`archive/v4/s14-*`, `s20-*`, `s21-*`). |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

## Gate row moved at the Slot 1 P landing (2026-09-30 night), verbatim

| Gate | Result |
|---|---|
| S14-D + polish (2026-09-30 day) | Unit **1305 / 0 / 2 = 1307**, reconciled with 1307 `func test` (`unit-polish2.log`, exit 0); inventory exit 0. S14-D (Gate D, refuter HOLDS): the origin refine walks along a ringed probe's ring, no fixed window ships. Polish: 13 items, Fable-supervised (two FIX-FIRST fixed), driven on scratch builds (drives 3–4). Refuters for S20 and S21 landed (`archive/v4/s20-refuter`, `s21-refuter`). |
