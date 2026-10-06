# Status

The one live status table. Updated in the same commit as the work it describes; anything older than the current step moves to `docs/archive/`. Numbers are quoted only from dated runs. Releases: `docs/releasing.md` § Releases.

**What a log name in these rows is** (settled 2026-09-09): a log name like `unit-c7s2-20260908.log` identifies the run a number came from, not a path a reader can open — session logs live in the gitignored session scratchpad and are not retained past the session. What a reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only thing that knows the harness count. Evidence a reader must be able to open is committed under `docs/archive/`, and the inventory gate fails on a repo-rooted path a truth doc cites and does not have.

## Where the UI stands

What that train left behind is the shape the app has now — `DSTEMCore` and `DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`, `ProductWorkflow.readiness`, `ACOMSession`, six workspace sidebars. The dated step table is archived at [`archive/v3/status-steps-2026-09-16.md`](archive/v3/status-steps-2026-09-16.md).

## Last gates (retained logs)

| Gate | Result |
|---|---|
| Lane U2 (2026-10-06) | Fresh gate copy (main + U2): unit 2057 run by name / 0 failed / 3 skipped, exit 0 (`gateU2/unit.log`); core 0. Mutations 2/2 red. Driven on the owner's Velox SI 1339: "Accept Cu, Al, O" accepts only the shown tiles, at% computed for all five, zoom 0–9.5 keV. |
| UX pass (2026-10-06, lanes uxAB/uxC/uxDE from Fable's spec) | Fresh gate copy (main + 3 lanes + supervisor: the Auto ID unvalidated badge kept, Home/reset uses the counts-energy zoom): unit 2055 run by name / 0 failed / 3 skipped (one passed line split by output, read at its line), exit 0 (`gateUX/unit.log`); core 0. Lane mutations AB 7, C 3, DE 4, each red. Driven on the owner's Velox SI 1339: 3 proposed tiles, one Accept button, quiet chart, one-voice panel; found: Accept takes all proposals (at% then blank) and the zoom spans 0–70 keV — next lane. |
| R10 + WP3e D3 (2026-10-06) | Fresh gate copy (main + R10 + the D3 sort): unit 2041 run by name, 0 failed, 3 skipped (2037 "passed on" lines + one split by parallel output), exit 0 (`gateR10/unit.log`); core 0. Lane mutations R10 6/6, D3 1/1 red. WP3e D1 failed its pre-landing print → closed (evidence in `archive/v5/wp3e-results-2026-10-06/`). |
| Room polish R8 (2026-10-06) | Fresh gate copy (main + R8): unit **2032 / 0 / 3 = 2036** = `func test` count, exit 0 (`gateR8/unit.log`); core 0. Lane mutations 7/7 red. Driven on the owner's Velox SI 1339: Al proposed on open (no false excess), ColorMix and tiles stretched, scale bar "200 nm", one caveat block. |
| WP3e no-Gate-D items R7 (2026-10-06) | Fresh gate copy (main + R7): unit **2025 / 0 / 3 = 2028** = `func test` count, exit 0 (`gateR7/unit.log`); core 0. Lane mutations 4/4 red. No file under `Fit/`; `ProposalResult.reducedChiSquared` added (existing value). Unverified on screen (the drive was stopped: a keystroke sequence lost focus). |
| Room polish R6 (2026-10-06) | Fresh gate copy (main + R6): unit **2021 / 0 / 3 = 2024** = `func test` count, exit 0 (`gateR6/unit.log`); core 0. Lane mutations 8/8 red. Supervisor kept the at% header's "· no absorption" in words (R6 had moved it to a hover). Driven on the owner's Velox SI 1339: ColorMix dominant, tiles beside, net ± σ one line, caveat shown. |
| Room drive fixes R5 (2026-10-06) | Fresh gate copy (main + R5): unit **2020 / 0 / 3 = 2023** = `func test` count, exit 0 (`gateR5/unit.log`); core 0. Lane mutations 12/12 red. Driven by the supervisor on the owner's Velox SI (build of the same tree): fixes seen, open items listed in the drive record. |
| WP3d A2 (2026-10-06) | Fresh gate copy (main + A2): unit **2011 / 0 / 3 = 2014** = `func test` count, exit 0 (`gateA2/unit.log`); core 0; after Fable's wording fixes `SpectroscopyRoomLiveRegionTests` + `SpectroscopyUnlistedLineTests` exit 0, 20 passed (`wording.log`). Mutations red: beside rule every-line / ±1 FWHM / beside-into-refit / caveat dropped / blanking restored. No path under `Fit/` or the proposer changed. Fable post-fix review: LAND. |
| Spectroscopy room rebuild (2026-10-06, R4b + R4c) | Fresh gate copy (main + lanes): `run-tests.sh unit` **2008 / 0 / 3 = 2011** = `func test` count, exit 0 (`gateR4c/unit.log`); `core` exit 0; `inventory` on main exit 0 (`inventory-main.log`). Lane mutations: R4b 28/28 red (M6, M24 tests strengthened after staying green), R4c 7/7 red. Fable Gate B: FIX FIRST → fixed (whole-map at% now waits for the unlisted check; tile label wrap). Frozen shell byte-identical. |

Earlier gate rows — the 2026-10-05 rows (the v4.5.0 release build and cut, the Velox reader check, the v5.0 research) are at [`archive/v5/status-history-2026-10-06.md`](archive/v5/status-history-2026-10-06.md); the 2026-10-04 rows (the Slot 4⅞ lanes, the polish drive, the `all` on `6456d623`) are at [`archive/v4/status-history-2026-10-04.md`](archive/v4/status-history-2026-10-04.md); the 2026-10-02 rows (Slot 4½, Slot 4¾, the v4.1.0 cut and its `all`, the RC drive) are at [`archive/v4/status-history-2026-10-02.md`](archive/v4/status-history-2026-10-02.md); the 2026-09-30 evening to 2026-10-01 night rows (new-Mac baseline through X3) are at [`archive/v4/status-history-2026-10-01.md`](archive/v4/status-history-2026-10-01.md); the 2026-09-30 overnight S12–S23 and v4.0.0-cut `all` rows, the 2026-09-30 clearing and S3 rows, the 2026-09-28/29 SSD subsample, stride, areal-edge, T6, raw Al-Mg-Si calibration, Bragg-restore and overnight 09-29 rows are at [`archive/v4/status-history-2026-09-29.md`](archive/v4/status-history-2026-09-29.md); 2026-09-17 through the 2026-09-23 overnight runs — are archived verbatim at [`archive/v4/status-history-2026-09-23.md`](archive/v4/status-history-2026-09-23.md). The 2026-09-23 night to 2026-09-25 rows are at [`archive/v4/status-history-2026-09-28.md`](archive/v4/status-history-2026-09-28.md). The 2026-09-28 morning's DM4, ellipse, clean-up and diffraction-groups rows are there too, and that day's R–Q, parallax, floor, T4, A2 and C2 rows.

## Handoff — 2026-10-06 night: the Spectroscopy room rebuilt, driven and polished; next session = the owner's UI list

| Item | State | Next step, owner |
|---|---|---|
| **Now** | v4.5.0 / 8 released 2026-10-05 (`docs/releasing.md`). v5.0 (EDX) on `main`, local only — main is far ahead of origin, nothing pushed. | Owner: push. |
| **v5.0 room** | Rebuilt to ADR 056 / mock v2.1 and polished through six session drives on the owner's Velox SI 1339 and the synthetic joint file (`archive/v5/room-drive-2-2026-10-06.md`, gate rows above): ColorMix dominant, ≤ 3 proposed tiles, one Accept button, quiet chart, one-voice quant panel, auto-contrast maps, scale bar, χ²ᵣ shown, at% with a caveat (A2). Fable's UX spec of record: `archive/v5/ux-spec-2026-10-06.md`. | Next session (Fable designs, Sonnet builds): the owner's UI bullet list, then the spec's "owner picture needed" items (Liquid Glass toolbar/sidebar, inspector width, title truncation, more-maps disclosure) as pictures for his decision. |
| **v5.0 science** | WP3d (real Al-alloy fit) and WP3e (Auto ID suspects) pre-registered, run, refuted (`archive/v5/wp3d-…`, `wp3e-…`); A2 and WP3e R7/D3 landed; WP3e D1 failed its pre-landing print → closed. Open: Auto ID misses Si and Mg and proposes Eu/Hf/Ho on real Al pools; "Hf+Hf sum? (or Zr Kα)" stays. | A new registration (Fable) when the owner wants it. Owner: a pure-Al spectrum (same detector, kV); the alloy composition; card V5-8. |
| **Unverified on screen** | Train Model…; the dataset refused as a save/Export destination (macOS Replace click). | Yours. |
| Carried | `open-items.md`; your 66 labels; the Impressum and privacy pages. | — |

Text of record for the 2026-09-16/17 handoff: [`archive/v3/status-handoff-2026-09-18.md`](archive/v3/status-handoff-2026-09-18.md); the day's evidence stays in `open-items.md` and `archive/v3/`.

## Owed to the owner

- The §10g decisions and plan §8 (sidecar wire format). C8's engines question was settled 2026-09-08: leave (`decisions.md`).
- Whether the v2.5.1 download (universal executable, arm64-only libraries) is withdrawn or annotated — likely moot under v4.0.0.
- Four session-4 choices to overrule on sight, and the C4 slices 1-2 drive — both carried in [`archive/v3/v3.0.0-closeout-2026-09-11.md`](archive/v3/v3.0.0-closeout-2026-09-11.md).
