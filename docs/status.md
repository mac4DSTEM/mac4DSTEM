# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| New-Mac Gate D (2026-09-30 evening, M5 Pro) | First unit run 1300 / 3 / 4 = 1307 (`unit-newmac.log`). Trainer SIGSEGV = an MPSGraph bf16 max-pool-gradient crash on the M5: fixed with the index-returning pool; `DetectorTrainerTests` 10 / 0 (`fix-test.log`, exit 0), mutation red on exactly the 2 (`mut-test.log`, exit 65); refuter HOLDS. Learned parity 2.26 %: Core ML `.all` runs on the GPU there, forced ANE passes 354/354 — owner decision (`open-items.md`). Record: `archive/v4/newmac-gateD-2026-09-30/`. |
| S14-D + polish (2026-09-30 day) | Unit **1305 / 0 / 2 = 1307**, reconciled with 1307 `func test` (`unit-polish2.log`, exit 0); inventory exit 0. S14-D (Gate D, refuter HOLDS): the origin refine walks along a ringed probe's ring, no fixed window ships. Polish: 13 items, Fable-supervised (two FIX-FIRST fixed), driven on scratch builds (drives 3–4). Refuters for S20 and S21 landed (`archive/v4/s20-refuter`, `s21-refuter`). |
| Overnight S12–S23 (2026-09-30 night) | Unit on `3cb567e`+S22: **1279 / 0 / 3 = 1282**, reconciled with 1282 `func test` (`unit-final.log`, exit on its own line); baseline 1203 / 0 / 2 = 1205 on 453f344 (`unit-base.log`). New harnesses: `virtual-detector-memory-test` (12 PASS), real-data positions (run.sh exit 0, 73 s), cif-symmetry-test exit 0. Every item Fable-supervised; drives 1, 2A, 2B on scratch builds (`archive/v4/drives-2026-09-30-night-shots/`). YELLOW S14, S20, S21 pre-registered, measured, recorded (`archive/v4/s14-*`, `s20-*`, `s21-*`). |
| `run-tests.sh all` (v4.0.0 cut) | **exit 0 — 2026-09-22/23** on `1b76c98` (`all-v4-20260922.log`, `GATE_EXIT=0` on its own line): 50 harnesses, zero `FAIL` lines, real-data acceptance and package-test (4.0.0 (7), floor 27.0, arm64 alone) included; unit **860 passed / 0 failed / 1 skipped = 861**, reconciled with 861 `func test`. |

Earlier gate rows — the 2026-09-30 clearing and S3 rows, the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration, Bragg-restore and overnight 09-29 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-30 night, the overnight block S12–S23 landed (owner delegated every decision)

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23; pushed through `8b6f93d` (the overnight block); the day's later commits are unpushed (the day's S14-D, polish, records). | Owner: push. |
| **Done (day)** | S14-D Gate D closed as recorded (`340eec4`, refuter `5de09ea`); polish in three rooms (`97af1b2`, `7862138`, `9925598`), driven; S20 and S21 refuters; 18 owner decisions distilled on the Board. | — |
| **Done (night)** | S17 `c403125`, S13 `f59e65f`, S19 `f73be56`, S16 `e19b32c`, S12 `b8b4544`, S23 `08f457a`, S18 `64015f0`, S15 `19f5b07`, owner decisions 1–2 `3cb567e`, S22 `53440b3` (`archive/v4/overnight-plan-2026-09-30.md` log). | — |
| **Yours** | The Board's "Your decisions" (18 cards, `archive/v4/owner-decisions-2026-09-30.json`): S21 take-after-five-fixes; S20 grain-C Gate D at true Q; S14-D window-sensitivity quantity; D1; the DM4 transpose check. | Owner. |
| **Next** | The new Mac (owner, 2026-09-30): bring-up and a full `run-tests.sh all` baseline there, then C5 training, the parallax/ptychography drive and the 28 GB parity run (`open-items.md` › Ready on the new hardware). The external-agent review (`archive/v4/polish-and-review-session-plan.md`) can run beside it. | Owner starts them. |
| **Overrule on sight** | Plan §5 (eight): origin-row warning + Restore; Fit anyway from lineage; `CrystalModelLibrary` kept; gate/l-filter deferred; `scientific` fails closed; "In memory" wording (Frozen Shell); S15 label-only; S20 amendment. Earlier: Core `-O` in Debug; ADRs 047, 048. | Owner. |
| **Owner owed** | The Board's "Your decisions" (18 cards); Thronsen's written confirmation (ADR 042). | Owner. |
| Phase mapping | Unvalidated. T4 one metric short, shipped as a quantity (ADR 048). | — |
| **Unverified on screen** | Decision 2 ("Fit anyway" after reopen, needs a ring refused as sparse); S23's pinch zoom and restored-origin branch. | Session. |
| Carried | Drive proposals and the bin-2 aperture defect (open-items S4); the S20 grain-C and S21 follow-ups (Board cards); CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Whether the v2.5.1 download (universal executable, arm64-only libraries) is withdrawn or annotated — likely moot under v4.0.0.
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
