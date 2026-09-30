# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| New-Mac baseline (2026-09-30 evening, M5 Pro 64 GB, macOS 27.0.1) | `all` on `9026863`: unit **1302 / 1 / 4 = 1307**, reconciled with 1307 `func test` (`all-newmac.log`, `GATE_EXIT=65` — the one red is the diagnosed M5 learned-parity test, owner pick). The runner stops there, so `scientific` ran alone after `62c8eda`: **51 harnesses, zero FAIL, `GATE_EXIT=0`** (`sci2-newmac.log`, 7 min 11 s; its first run caught `result-presentation-test` broken by `9925598`); `package-test` exit 0 (`pkg-newmac.log`); inventory exit 0. Gate D: the M5 MPSGraph training crash fixed, the parity failure diagnosed, both refuters HOLD (`archive/v4/newmac-gateD-2026-09-30/`). |
| S14-D + polish (2026-09-30 day) | Unit **1305 / 0 / 2 = 1307**, reconciled with 1307 `func test` (`unit-polish2.log`, exit 0); inventory exit 0. S14-D (Gate D, refuter HOLDS): the origin refine walks along a ringed probe's ring, no fixed window ships. Polish: 13 items, Fable-supervised (two FIX-FIRST fixed), driven on scratch builds (drives 3–4). Refuters for S20 and S21 landed (`archive/v4/s20-refuter`, `s21-refuter`). |

Earlier gate rows — the 2026-09-30 overnight S12–S23 and v4.0.0-cut `all` rows, the 2026-09-30 clearing and S3 rows, the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration, Bragg-restore and overnight 09-29 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-09-30 evening, the new Mac brought up (after the overnight block S12–S23 and the day's polish)

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.0.0 released 2026-09-23; pushed through `8b6f93d`; the day's later commits and the new-Mac bring-up (`9026863`, `62c8eda`, closeout) are unpushed. | Owner: push. |
| **Done (day)** | S14-D Gate D closed as recorded (`340eec4`, refuter `5de09ea`); polish in three rooms (`97af1b2`, `7862138`, `9925598`), driven; S20 and S21 refuters; 18 owner decisions distilled on the Board. | — |
| **Done (evening)** | New-Mac bring-up: envs recreated from the old Mac, M5 training crash fixed (`9026863`), harness repaired (`62c8eda`), baseline green but the one owner pick, limits re-measured. | — |
| **Done (night)** | S17 `c403125`, S13 `f59e65f`, S19 `f73be56`, S16 `e19b32c`, S12 `b8b4544`, S23 `08f457a`, S18 `64015f0`, S15 `19f5b07`, owner decisions 1–2 `3cb567e`, S22 `53440b3` (`archive/v4/overnight-plan-2026-09-30.md` log). | — |
| **Yours** | The Board's "Your decisions" (18 cards, `archive/v4/owner-decisions-2026-09-30.json`): S21 take-after-five-fixes; S20 grain-C Gate D at true Q; S14-D window-sensitivity quantity; D1; the DM4 transpose check. | Owner. |
| **Next** | ROADMAP queue: "Residency returns, measured" — pre-registered, not started (`archive/v4/residency-preregistration-2026-09-30.md`, three owner decisions at its start); then the M5 learned-parity pick (a/b), C5, parallax/ptychography, the 28 GB parity run. The external-agent review can run beside them. | Owner starts them. |
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
