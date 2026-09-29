# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| **Overnight 2026-09-29** (plan `archive/v4/overnight-plan-2026-09-29.md`, its Log; shots `archive/v4/overnight-2026-09-29-shots/`) | Unit **961 / 0 / 2 = 963**, reconciled (`unit-sm.log`, the last of five runs); inventory exit 0 at every commit. A1 disk-detection memory fixed (a pool per tile + exact-size peak arrays; `tiled-detection-memory-test` gated: 473 → 1 MB over 12 tiles; in-app Detect All on Thronsen A flat at ≈ 1.18 GB, 754,479 peaks); A2 controls seeded; A4 table → map highlight; an **AI-room constraint-loop abort** found by drive 3 (pre-existing) — the room's rows fixed and guarded (`InspectorWidthBudgetTests`), **the Info tab at 915 pt and a widest inspector drag still abort** (Frozen Shell, owner); D1 tolerance measured (the shipped rule fits all four datasets); the 2026-09-09 register triaged. |
| Raw Al-Mg-Si cube, stride 3, calibrated from its own lattice (2026-09-29; registered `f06dd1f`) | Every prediction held: Q 0.006577 Å⁻¹/px (−0.34 %; the file 1.74× off), ratio 1.0846, 20.8°, [001] 92.9 %, matrix 86.4 %. Found: GPU memory grows per tile in `detectAll` (probe killed at 1.6–2.1 GB; autoreleasepool per tile holds ≈ 500 MB) — **fixed overnight A1** (classical; harness `tiled-detection-memory-test`, 473 → 1 MB over 12 tiles); the probe's one-pixel match tolerance leaves 97 % not indexed on a 256² detector (the app ships 0.02 Å⁻¹ = 3 px there — unmeasured; corrected overnight D1). |
| Bragg disks restored from the session sidecar (2026-09-29; registered `3a4e4d5`) | The peaks the sidecar always wrote are read back and adopted automatically when load spec, detection step, shapes and provenance all match; the nil-kernel staleness hole closed. 16 tests, each broken first. Overnight A2: the detection controls (all 12 parameters, detector class, learned threshold) are seeded from the recorded step on adoption, so a kernel built later keeps the disks current; 9 more tests, 7 mutations red. Unit **941 / 0 / 2 = 943** (`unit-A123.log`). **Seen on screen** overnight (drives 1–2): the restore line, the seeded controls current after Build Kernel, and in-app re-detection reproducing the same 754,479 peaks. |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

Earlier gate rows — the 2026-09-28/29 SSD subsample, stride, areal-edge and T6 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-30 morning

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23. `main` carries the overnight session's commits on top of the pushed `1a76089` (plan Log, §4 report). | Owner: read the §4 report and §5, then push. |
| Narrow windows | The constraint-loop abort is fixed and **seen on screen** (2026-09-30, your pick: fixed 460 inspector + the sidebar stepping aside below 1095 pt). Unit 965/0/2 = 967. Residual: Show Tools against the screen's edge. | — |
| **Owner owed** | §5 A (the 915-pt floor), B (D1: keep the shipped tolerance), C (the register's Gate D order); Thronsen's written confirmation (ADR 042); where precipitate analysis lives; the "decided overnight — overrule on sight" list. | Owner. |
| **⚠ Don't run** | Detect All Disks with the **learned** detector on multi-GB cubes (its tiled loop is not pooled). | — |
| Phase mapping | Unvalidated. T4 one metric short; D1 measured: the shipped max(0.02 Å⁻¹, 1 px) lies inside all four datasets' bands (raw 060 cube: matrix 84.4 % at the app's 0.02); `archive/v4/phase-tolerance-results-2026-09-29.md`. | Owner: option (a). |
| **Unverified on screen** | — | — |
| Carried | R–Q residuals; the 28 GB `--parity` run; parallax/ptychography drive; C2's memory and criterion 4; the register's 11 Gate D candidates; Friedel ETA; D2 (raw cube objects — the two probes need bridging first); CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
