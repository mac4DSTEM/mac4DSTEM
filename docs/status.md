# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Drive 9 (2026-10-12, scratch build of 179d2b9c, stopped at the session limit) | R7 passes on screen; R6 partly; R1–R5, R8 not run. Read from outside, the inspector's AX tree went stale (Info rows 0, 0 vs 2, 3 on screen; Prepare's controls listed after switching rooms); whether VoiceOver hears stale values is open (next: the same steps on a1cea5c2). |
| Final overnight gate (2026-10-08 05:30, `eb272b25`) | unit **2369 / 0 / 3 = 2372** = `func test` count, core 0, inventory 0, `scientific` exit 0, 53 sections, zero FAIL lines (`gateM5/*.log`). Covers everything landed overnight, the two stale-AX fixes included. |
| Exact sum-column dedup (2026-10-08 night, 77c12faa; Gate D) | Registered first (de43f673) after the 0.06 keV rule was refuted (75 of 88 entries changed). Live Velox re-run: the six failing entries score, 88 of 88 others identical in every field; three tests each red on its mutation; refuter (Haiku, read-only) upheld with notes (an exact sum equal to a non-sum column is unhandled). Gate on `main`: unit **2369 / 0 / 3 = 2372** = `func test` count, core 0, inventory 0, `scientific` exit 0, 53 sections, zero FAIL lines (`gateM4/*.log`). |
| SwiftUI review residuals (2026-10-12, `b0cd101d..fe3bc6f3`, 14 commits, UI + tests only) | Written by seven Haiku lanes in scratch repos (trailers per the session's attribution line), each lane's unit gate green; lane B (P4b) and lane E's region actions not landed (no-change closes in `open-items.md`). A read-only Fable review found three defects in them, fixed in `05bf59cc..fe3bc6f3`: ACOM's Work/Expected rows still read the scan position, the comparison panel was no accessibility element, "°" spoken after "in degrees". Gate on the sources of `fe3bc6f3`: unit **2410 / 0 / 3 = 2413** = `func test` count (2369 + 41), core 0, inventory 0 (`lane-R/unit.log`, `core-R.log`, `inventory-repo.log`). No `Core/` file changed, so no `scientific` trigger. |

Earlier gate rows — the 2026-10-07 rows (spec 2 through the WP4 landing, and that night's WP4b, eXSpy pins, SwiftUI review fixes and drives) are at [`archive/v5/status-history-2026-10-07.md`](archive/v5/status-history-2026-10-07.md); the 2026-10-06 rows (the Spectroscopy room rebuild through lane U2) and the 2026-10-05 rows (the v4.5.0 release build and cut, the Velox reader check, the v5.0 research) are at [`archive/v5/status-history-2026-10-06.md`](archive/v5/status-history-2026-10-06.md); the 2026-10-04 rows (the Slot 4⅞ lanes, the polish drive, the `all` on `6456d623`) are at [`archive/v4/status-history-2026-10-04.md`](archive/v4/status-history-2026-10-04.md); the 2026-10-02 rows (Slot 4½, Slot 4¾, the v4.1.0 cut and its `all`, the RC drive) are at [`archive/v4/status-history-2026-10-02.md`](archive/v4/status-history-2026-10-02.md); the 2026-09-30 evening to 2026-10-01 night rows (new-Mac baseline through X3) are at [`archive/v4/status-history-2026-10-01.md`](archive/v4/status-history-2026-10-01.md); the 2026-09-30 overnight S12–S23 and v4.0.0-cut `all` rows, the 2026-09-30 clearing and S3 rows, the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration, Bragg-restore and overnight 09-29 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-10-12: SwiftUI review residuals landed; Auto ID A1 and E1 wait on cards

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.5.0 / 8 released; v5.0 (EDX) on `main`; the night's commits are local (last push before `1f4c4f4b`). | Owner: push. |
| **Landed 2026-10-12** | The SwiftUI review's remaining rows, VoiceOver actions only (owner): scan crop, Label centres, comparison sample, disabled reasons, spectrum candidates, a field's unit spoken once; the Info and ACOM per-scrub re-reads. Gate row above. | Owner: push. |
| **Auto ID** | Exact sum–sum duplicates fixed (77c12faa). A sum-vs-one-peak fix held its gate but is HELD (card A1: its line branch could fold a Cd+Tl pile-up into La on 33.5–37.8 keV axes). | Owner: card A1 (escape-only recommended). |
| **v5.0 science** | E1 registered (`archive/v5/e1-pooling-preregistration-2026-10-08.md`, Gate B review taken). | Owner: cards E1–E6 (Decisions page); then build E1, then the 4D Quantify rows in Results, then B*'s prerequisites. |
| **Unverified on screen** | Open rows of `archive/v5/swiftui-review-verification-2026-10-07.md` (VoiceOver speech R1–R8, Y4, Y5, Shown 6.1 / 6.3, P2a, P2c, WL-1, a GMS DM4 D2-1); Train Model…; Compute Image in 4D; Export › Scale bar; Reduce Transparency. | A drive (VoiceOver and Reduce Transparency are the owner's settings). |
| **Owner** | Swift 6 measured in full (app, tests, tools: ≈ 3.5–6 sessions). The status bar truncates long lines (one line or wrap: a frozen-shell change). Visible wording (2.4, 4.8, 1st #20) and the lineage focus ring (7.3). Core ML stays (ADR 063). | Schedule or not; at the microscope a pure-Al thin foil (same session and settings, per-detector export), the alloy composition, the joint GMS run. |
| Carried | `open-items.md`; your 66 labels; the Impressum and privacy pages. | — |

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Whether the v2.5.1 download (universal executable, arm64-only libraries) is withdrawn or annotated — likely moot under v4.0.0.
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
