# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Session queue S2, workspaces (2026-09-30) | Unit **957 / 0 / 1 = 958**, reconciled with 958 `func test` (967 − 10 per-room width tests + 1 loop over every workspace/task pair); run as the unit lane's own `xcodebuild test` line (`unit-s2.log`) because 3.9 GB free is under its 4 GB floor. Both new tests broken first: phase mapping routed to Imaging → `testWorkspacesFollowTheData` red; Bragg Disks routed to nothing → the width loop red (`mut-s2.log`). One skip, `TB1StallProbeTests` (was 2). |
| **Overnight 2026-09-29** (plan `archive/v4/overnight-plan-2026-09-29.md`, its Log; shots `archive/v4/overnight-2026-09-29-shots/`) | Unit **961 / 0 / 2 = 963**, reconciled (`unit-sm.log`, the last of five runs); inventory exit 0 at every commit. A1 disk-detection memory fixed (a pool per tile + exact-size peak arrays; `tiled-detection-memory-test` gated: 473 → 1 MB over 12 tiles; in-app Detect All on Thronsen A flat at ≈ 1.18 GB, 754,479 peaks); A2 controls seeded; A4 table → map highlight; an **AI-room constraint-loop abort** found by drive 3 (pre-existing) — the room's rows fixed and guarded (`InspectorWidthBudgetTests`), **the Info tab at 915 pt and a widest inspector drag still abort** (Frozen Shell, owner); D1 tolerance measured (the shipped rule fits all four datasets); the 2026-09-09 register triaged. |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

Earlier gate rows — the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration and Bragg-restore rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-30 morning

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23; `main` pushed at `5bd686b` (2026-09-30): the overnight work, the narrow-window fix, the session queue. | — |
| Workspaces (S2) | ADR 046's six built and **driven** 2026-09-30 on a scratch build at 915 and 1470 pt: every room's tasks, settings, toolbar verb, ⌘1–⌘6 names; Group Patterns and Detect All Disks run from the toolbar; the Bragg-disks requirement opens Bragg Disks. Found (pre-existing shell path, S6): an explicitly shown sidebar at 915 pt clips the inspector, then leaves empty strips when widened. | — |
| **Next — the session queue** | `ROADMAP.md` › **Session queue**: S1 Close and S2 Workspaces done 2026-09-30. Next unchecked: **S3 Prepare polish** (manual Q, voltage placeholder, the Friedel ETA — Gate D first); S4–S6 polish; S7–S11 Gate D; then training, then the lineage graph. | `/pickup`. |
| **Owner owed** | D1 option (a); the lineage graph's session-file format (when it is registered); Thronsen's written confirmation (ADR 042); the "overrule on sight" list (plan §5). | Owner. |
| **⚠ Don't run** | Detect All Disks with the **learned** detector on multi-GB cubes (its tiled loop is not pooled). | — |
| Phase mapping | Unvalidated. T4 one metric short; D1 measured: the shipped max(0.02 Å⁻¹, 1 px) lies inside all four datasets' bands (raw 060 cube: matrix 84.4 % at the app's 0.02); `archive/v4/phase-tolerance-results-2026-09-29.md`. | Owner: option (a). |
| **Unverified on screen** | — | — |
| Carried | R–Q residuals; the 28 GB `--parity` run; parallax/ptychography drive; C2's memory and criterion 4; the register's 11 Gate D candidates; Friedel ETA; D2 (raw cube objects — the two probes need bridging first); CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Whether the v2.5.1 download (universal executable, arm64-only libraries) is withdrawn or annotated — likely moot under v4.0.0.
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
