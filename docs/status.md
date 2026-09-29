# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Clearing batches landed and driven (2026-09-30) | Gate D per science item, an independent refuter or supervisor each (records in `archive/v4/`: register D006/D021/D079, IPF key, training leak, learned windows D098/D004; ADR 047 amendment for L4). Unit on `0864244`: **1187 / 0 / 1 = 1188**, reconciled with 1188 `func test` (`close-unit.log`, exit on its own line). Harnesses: 15 scientific harnesses touching today's Core changes exit 0 (`close-h-*.log`); `sidecar-result-test` was red on a stale schema pin ("6"; the writer is 7 since `aa920d0`, by design) — pin updated, green. Drives: 15 rows verified, 1 partial, 2 defects found (legend swatch fixed `e90f168`; Clear Calibration and ptychography filed) (`archive/v4/drives-2026-09-30.md`). |
| S3 Friedel speed, Gate D (2026-09-30) | `friedel-timing` on Thronsen A: 3 572 positions/s at `-O` (8 s), 38/s at `-Onone` (765 s), footprint flat; reads 6 600–7 000/s either way, so the serial-read hypothesis is refuted. The Debug app linked `DSTEMCore` at `-Onone`; `Package.swift` now builds both packages `-O` in Debug (build log: `-Onone … -O`, last wins). Unit **964 / 0 / 1 = 965** (`unit-s3d.log`). The drive's falling-rate shape is not reproduced — re-drive owed. |
| S3 number entry, Gate D (2026-09-30) | In a comma-decimal region the lenient parse read `0.0275` as 275, `0.020` as 20, `0.2` as 0 (clearing the file's Q) — reproduced in the app and in a script; the 09-07 "emptied field clears Q" record refuted (empty throws, the field reverts). Fix: `DecimalEntryFormat` under every numeric field; Q/R/voltage empty show "Not set" and commit nothing. Refuter (Opus) broke the first grouping rule (`0.0.275` → 275, integer `1.600` → 1); fixed and pinned. Unit **964 / 0 / 1 = 965** (`unit-s3b.log`); four mutations red. Seen on screen (scratch build): `0.0275` → 0,0275 Manual, emptied field kept it, voltage 0 → "Not set", `300.5` → 300,5 kV; the typo refusal is unit-tested only. |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

Earlier gate rows — the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration, Bragg-restore and overnight 09-29 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-30, the clearing batches landed and driven (owner delegated every decision)

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23; `main` pushed by the owner after S5; every later commit unpushed. | Owner: push. |
| **Done** | Clearing the board A, B, E; C through the leak fix (`7361eea`); D through L4 Rewind to Here (`34af213`). Register D004, D006, D019, D021, D023, D025, D079, D098; strain support; aperture drag; IPF key (the v4.0.0 known issue); ptychography sampling; stale zone-axis list; challenged-matrix stripe and legend; iDPC caption; the task "Disk detection" (owner). Drives 2026-09-30: every drawing change above seen, a Fable supervisor per group (`archive/v4/drives-2026-09-30.md`). | — |
| **Next** | `lineage_step` on products (ROADMAP D); the register's D068, D017, D020, each its own Gate D; Clear Calibration and the ptychography result (open-items). | Session. |
| **Overrule on sight** | Core `-O` in Debug (`9fe9440`); ADRs 047 (with the L4 amendment), 048 (MPSGraph; Core ML for every model; T4 as a quantity); the D025 radius at R + 0.5; < 256 px off-centre probes keep the crop's dose scale (byte-identity). | Owner. |
| **Owner owed** | D1 option (a); Thronsen's written confirmation (ADR 042). C5 and Train Model… wait for the new hardware (owner, 2026-09-30; admission refuses here, 2.10–2.13 of 2.16 GB). | Owner. |
| Phase mapping | Unvalidated. T4 one metric short, shipped as a quantity (ADR 048). | — |
| **Unverified on screen** | Train Model… in the app (C5, after the new hardware); the zone-axis notice after an identical origin re-fit. | Session. |
| Carried | R–Q residuals; parallax/ptychography and the 28 GB parity run (hardware); the virtual-detector tiled loops; CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Whether the v2.5.1 download (universal executable, arm64-only libraries) is withdrawn or annotated — likely moot under v4.0.0.
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
