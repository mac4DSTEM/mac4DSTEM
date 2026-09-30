# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Late 2026-09-30 (sidecar access, memory budget) | Unit **1308 / 0 / 4 = 1312**, reconciled with 1312 `func test` (`unit-budget.log`, `GATE_EXIT=0`); the six phase-contrast harnesses green on the budget (`h-*.log`); inventory exit 0. |
| ANE return + board clearing (2026-09-30 night, M5 Pro) | Unit **1305 / 0 / 4 = 1309**, reconciled with 1309 `func test` (`unit-ane.log`, `GATE_EXIT=0`; the M5 parity test green on the Neural Engine, asserted three ways); `scientific` **51 harnesses, zero FAIL, `GATE_EXIT=0`** (`sci-ane.log`); inventory exit 0. Gate D + two independent refuter passes (`archive/v4/ane-return-2026-09-30/`); the 28 GB parity run (`archive/v4/parity-28gb-2026-09-30.md`, refuted independently); the parallax/ptychography cost (`archive/v4/parallax-ptycho-cost-2026-09-30.md`). |
| New-Mac baseline (2026-09-30 evening, M5 Pro 64 GB, macOS 27.0.1) | `all` on `9026863`: unit **1302 / 1 / 4 = 1307**, reconciled with 1307 `func test` (`all-newmac.log`, `GATE_EXIT=65` — the one red is the diagnosed M5 learned-parity test; owner: the app back on the ANE). The runner stops there, so `scientific` ran alone after `62c8eda`: **51 harnesses, zero FAIL, `GATE_EXIT=0`** (`sci2-newmac.log`, 7 min 11 s; its first run caught `result-presentation-test` broken by `9925598`); `package-test` exit 0 (`pkg-newmac.log`); inventory exit 0. Gate D: the M5 MPSGraph training crash fixed, the parity failure diagnosed, both refuters HOLD (`archive/v4/newmac-gateD-2026-09-30/`). |
| S14-D + polish (2026-09-30 day) | Unit **1305 / 0 / 2 = 1307**, reconciled with 1307 `func test` (`unit-polish2.log`, exit 0); inventory exit 0. S14-D (Gate D, refuter HOLDS): the origin refine walks along a ringed probe's ring, no fixed window ships. Polish: 13 items, Fable-supervised (two FIX-FIRST fixed), driven on scratch builds (drives 3–4). Refuters for S20 and S21 landed (`archive/v4/s20-refuter`, `s21-refuter`). |

Earlier gate rows — the 2026-09-30 overnight S12–S23 and v4.0.0-cut `all` rows, the 2026-09-30 clearing and S3 rows, the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration, Bragg-restore and overnight 09-29 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-30 night: the owner's sitting done (ADR 050); the v4.1 plan registered, five slots of three lanes

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23; pushed through `2f5d90e2`; the sitting's docs commit follows. The 21 cards are answered (ADR 050); the plan is `archive/v4/v41-plan-2026-09-30.md`. | Owner: fire the cloud review; then Slot 1. |
| **Decided (night)** | ADR 049 (the plateau) and ADR 050 (the sitting: v4.1 = py4DSTEM parity for the shipped features; ptychography, training, raw-data preprocessing and the keep-in-memory control finished; the decision-sheet format kept; two rules in `CLAUDE.md`). | Overrule on sight. |
| **Late (owner's drive)** | Sidecar access fixed (Allow Access…, driven); review sheet width; memory budget half of RAM; C5 headless (D7 declines) and the owner's Train Model… drive (0/82: the Synthetic kernel on a ringed probe); graphene cube: parallax agrees with py4DSTEM, ptychography lacks a defocus input and its DM diverges (`archive/v4/parallax-ptycho-graphene-2026-09-30/`). | Lanes T and R. |
| **Done (night)** | Learned detector back on the Neural Engine (the load refuses a model the ANE did not run; ≤ 0.45 % of accepted peaks move at 0.7); the 28 GB parity run (the app's DM4 read is right; the "unfiltered" cubes are hot-pixel filtered at 15 pixels incl. the direct beam); the 051 cost measured (estimators honest). | — |
| **Next** | Slot 1: P polish room · Q science quick wins · R1 the ptychography probe (three supervisors, disjoint write-sets); R, T, X, K, F, Z follow (`archive/v4/v41-plan-2026-09-30.md`). | `/pickup` per lane. |
| **Yours** | The review's findings, one sitting, on a decision sheet (ADR 050's format); the File-probe training run; the "do my numbers read those pixels?" check; the Si-SiGe re-export; the X3 and K1 mocks when they come. | Owner. |
| **Overrule on sight** | ADR 049's freeze list; the refusal (not a CPU fallback) on a machine with no Neural Engine; the memory budget at half of RAM; plan §5 (eight) and the earlier list. | Owner. |
| Phase mapping | Unvalidated. T4 one metric short, shipped as a quantity (ADR 048). | — |
| **Unverified on screen** | Decision 2 ("Fit anyway" after reopen, needs a ring refused as sparse); S23's pinch zoom and restored-origin branch; the review sheet at its new 480-pt width (the owner saw it clipped; the fix is not yet seen). Driven: Allow Access… (scratch build, 40 labels restored); the Train Model… flow (owner, 19:43, sheet reached). | Owner / session. |
| Carried | Drive proposals and the bin-2 aperture defect (open-items S4); the S20 grain-C and S21 follow-ups (Board cards); CI paused (ADR 040). | `open-items.md`. |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Whether the v2.5.1 download (universal executable, arm64-only libraries) is withdrawn or annotated — likely moot under v4.0.0.
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
