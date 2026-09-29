# Overnight plan — clear the board and consolidate (2026-09-29, unattended)

Owner's brief: clear almost everything open on the board, consolidate, drive the app itself, stay curious — and stay
true to the rules: simple, robust, pure macOS/SwiftUI, scientifically correct, a great and intuitive UX. Sonnet 5.5
subagents do the work; the session (Opus) plans, reviews every diff and screenshot, gates and commits. This file is
the plan AND the night's log: append one line per finished item and commit it, so a crash loses nothing.

## 0. Before the owner leaves (the only human steps)

1. Start the session in **Auto** mode with the kickoff prompt (§6); stay until its first check passes.
2. **Quit the owner's own mac4DSTEM** (same bundle id: tonight the computer-use tools resolved to his instance).
3. Approve screen control when the session asks at the start (`request_access` for mac4DSTEM; Accessibility and
   Screen Recording are already granted to `claude`, proved 2026-09-28 by two drives).
4. Mac on power, awake and **not locking** (the owner's call: System Settings › Lock Screen); the session runs
   `caffeinate -dimsu` itself. SSD may stay plugged in: read-only use of `ROI_5/mac4dstem_subsampled/` only.
5. Push beforehand in GitHub Desktop, so the night starts from a pushed `main`.
6. **Claude Code auto-update off for the night** (every update revokes Accessibility — driving would stop silently;
   if it happens anyway, the session continues with non-driving items). **Screen saver "Never"** (caffeinate does not
   stop a password-locking screen saver). **Hard disks never sleep** if the SSD stays plugged in (a vanished volume is
   a SIGBUS in a probe); or unplug it and skip D2.

## 1. Safety — nothing lost, nothing crushed

- **`main` only**, one coherent commit per item after its gate; `git stash create`/`store` before any risky step;
  this log committed after every item. No push, no branch, no in-repo deletes, no force.
- **One heavy job at a time** (build, unit gate, probe, drive). `df -h /` ≥ 4 GB before a build (free only the
  session's own scratch DerivedData); memory pressure checked; every probe on a multi-GB cube under the footprint
  guard (`phys_footprint` > 1.5 GB or critical pressure → kill; rebuild `guard.sh` from memory note
  never-full-read-bigger-than-ram). **No Detect All Disks in the app on multi-GB cubes** until item A1 lands.
- Disk: every `xcodebuild test` also leaves a ≈ 300 MB log archive in `/var/tmp`; check `df -h /` before each
  build and clear only the session's own scratch. The Board: `read` it before publishing (a publish without a read
  in that session is refused). Memory consolidation runs LAST (the night relies on the notes).
- **Clock:** no new heavy item after 06:30; the §4 morning report starts by 07:00.
- Drives: a scratch build (`-derivedDataPath` in the scratchpad), launched `open -n`, pid-pinned; every claimed
  observation checked against its screenshot by the session before it is written down.
- **Decide, don't stall** (owner, 2026-09-29, replacing "stop, don't guess"): (1) decide from the record — ADRs,
  CLAUDE.md, the owner's recorded preferences; (2) otherwise ask a stronger model: an Opus advisor subagent (Fable for
  the hardest) gets the evidence and the options, argues against the proposal, recommends; (3) if it endorses and the
  step is reversible, do it, commit it with the reason and the advisor's verdict, and list it in §5 as **"decided
  overnight — overrule on sight"**; (4) stop only on what is irreversible or the owner's alone: push, delete, a moved
  shipped scientific number (YELLOW stays measure-only), a Frozen Shell redesign, anything outside the repo.

## 2. The rubric, updated

GREEN (do and commit): no number moves, no owner decision, a gate that runs — now including **on-screen checks**,
since the session drives. YELLOW (measure, refute, propose; commit the record, not the change): anything that
moves a shipped number or a shipped verdict. RED (list only): owner decisions, pushes.

## 3. The night, in order (GREEN first, YELLOW last)

**A — finish tonight's work (GREEN)**
1. Gate D fix: autorelease pool per tile in `TiledDiskDetection.detectAll` — **diagnosis held** (+335 MB per tile
   unpatched, flat with a pool; `tiled-detection-memory-gateD-2026-09-29.md`), a gated memory harness broken first, refuter, unit gate.
2. Bragg restore: seed the detection controls from the recorded step; test broken first; then **drive** — open
   Thronsen A, see "Disks restored…", map phases without detecting; screenshots reviewed.
3. `AppState`: move one responsibility out only where that makes the app better (owner 2026-09-29, "Rules
   serve the app"); otherwise record why not.
4. Object Table: a selected row highlights its object on the map (open residual); the relationship field's grey
   prompt stops reading like a value. Drive-verified.

**B — every "seen on screen" debt (GREEN, driven)** — open-items: Friedel progress/ETA screen check (2026-09-19),
"Owed on screen from earlier drives", "No workflow logic in the rooms", the origin validity overlay if it exists,
`PaneSplit` image-floor residual, the inspector's maximum at the 915-pt window (drag test), light mode on a real
cube. Each: a scratch drive, shots reviewed, the item closed or re-recorded with the evidence.

**C — consolidation (GREEN)**
- `docs/open-items.md` (517 lines): archive closed and superseded items verbatim, merge duplicates, every live entry
  ≤ 12 lines; target ≤ 300 lines, cold-start set down.
- `status.md`, `ROADMAP.md`, the Board: one truthful state; stale rows archived.
- Skills: `pickup`/`closeout` still speak of v2 plans and dev branches — align with `main` only, the overnight
  rubric, drives. Memory: consolidate (`anthropic-skills:consolidate-memory`).
- The 119-defect triage: a Sonnet sweep classifies each as closed / live / duplicate — records only.

**D — science, measure only (YELLOW, last)**
1. Physical (Å⁻¹) phase-match tolerance instead of detector pixels: measure on Thronsen A, the demo cube, the binned
   and raw Al-Mg-Si cubes; propose with numbers; no ship.
2. The raw 060 cube: known variants with β″ (needs an ellipse input in the phase-map probe); edge-corrected density
   with pixel size, minimum size and count.
3. The polydisperse bar for volumetric density (parked): only if everything above is done.

## 4. Morning

Board republished, this log complete, a closeout: what landed (commits, gate numbers), what was seen on screen (with
the shot names), what is YELLOW awaiting the owner, and the §5 decisions.

## 4a. Morning report (written 2026-09-29, ~04:50)

**Landed** (18 commits on `1a76089`, none pushed; each with its gate in the message): A1 memory fix `6cf4dfe` (harness
473 → 1 MB; Opus refuter) · A2 seeded controls `aed83c4` · A3 strain move `9bb1e48` · A4 table highlight + "Any rotation"
+ table minimum `e1ea1ff` · grouped counts `a076f0a` · AI-room abort part 1 `d03f867` (Gate D `a11e492`, `4cef2d1`,
`a6fd6e5`, `af00e57`) · three drive findings `3d8bae1` · triage `c436c41` · skills `41c5584` · open-items 521 → 346
`760ce23` · D1 registered `7f99ded`, amended `3f828d5`, measured `e1b24e1` · this closeout. Last unit gate **961 / 0 / 2
= 963** (`unit-sm.log`); inventory exit 0 at every commit.
**Seen on screen** (five drives on scratch builds, pid-pinned, every shot reviewed; `overnight-2026-09-29-shots/`): the
restore line and seeded controls (`d1-02`, `d1-04b`); in-app Detect All flat at ≈ 1.18 GB with 754,479 peaks (drive 2
guard log); the outline around the selected object and gone on close (`d2-05b`, `d2-05f`); the table clamping at 674 pt
(`d2-06`); light mode (`d1-07a`); load cancel with no stale badge (`d5-02`); a 60-character phase name truncated
(`d4-L4-03`). **Found:** the constraint-loop abort (fixed in the room; Info tab and widest drag still abort — §5 A), the
915-pt clipping (`d1-08b`, `d4-L1b-03`), the Friedel ETA that only grows.
**YELLOW, awaiting you:** D1 — option (a) recommended (§5 B). D2 and D3 not started (the raw cube's objects need the two
probes bridged first; D3 was "only if everything above is done").
**Not done from the plan:** "Owed on screen" failure paths and the disk-centre label (need a failure to provoke / your
hand); memory consolidation ran last (this session).

## 5. Decisions for the owner (filled in during the night)

**Decided overnight — overrule on sight** (each reversible; the reason is in its commit):
1. **Table → map highlight design** (`e1ea1ff`): an app-scoped selection relay keyed by the classification run's
   `sourceID`; an outline overlay, never a published product. Opus advisor endorsed a narrowed proposal and rejected
   re-publishing the objects picture with emphasis (it would leak into Save Result and the sidecar).
2. **Object Table windows are not restored at launch**; their minimum width is the one-line summary (`e1ea1ff`).
3. **"Any rotation"** as the relationship field's placeholder; the example moved into the help (`e1ea1ff`).
4. **Peak counts grouped** with the app's en_US count formatter, as "29,241 positions" already is (`a076f0a`).
5. **The strain run moved to `AppState+Strain.swift`** (`9bb1e48`): the one AppState move that helped.
6. **`findMaxima` copies survivors to an exact-size array** (`6cf4dfe`): the second memory mechanism; values identical.
7. **The AI-room rows shortened** (`d03f867`): "Å⁻¹ (0 = detector)" → "Å⁻¹" (meaning in the help), "Direct matrix, max",
   "Specific reflections, min", "Min. intensity … of max"; phase names truncate in the middle (`InspectorDataRow`).
8. **An unchanged manual Q/R value is not an edit** (`3d8bae1`): within half the field's last digit (5e-7).
9. **Skills** (`41c5584`): pickup/closeout now carry "decide, don't stall", v4 numbering, session drives, main only.

**Yours (not done — each needs you):**
- **A. The 915-pt floor (Frozen Shell).** Found tonight: the inspector's Info tab at 915 pt and a widest inspector drag
  still **abort** (the same constraint loop as the fixed AI-room case); after Info the layout overflows ≈ 17 pt; each
  image pane is ≈ 146 pt at the floor. Proposal: (1) the Info tab's dataset rows truncate like `InspectorDataRow`
  (`WorkspaceInspector.swift`), (2) the inspector's maximum follows the window (≤ window − sidebar − the panes' floor,
  `LayoutPolicy`), and collapse the sidebar before the panes fall under ~240 pt each (Xcode's behaviour). Alternative:
  raise the window floor to ~1000 pt. Evidence `ai-room-narrow-crash-gateD-2026-09-29.md`, shots `d1-08*`, `d4-*`.
- **B. D1** (`phase-tolerance-results-2026-09-29.md`): **recommended (a)** — keep the shipped max(0.02 Å⁻¹, 1 px); it is
  the only rule tested inside all four datasets' bands. (b) a new default → Gate D, a refuter, then you.
- **C. The 2026-09-09 register:** order of the 11 Gate D candidates (recommended first: D025, the circle-ROI mask +0.5 px
  off the drawn ROI; then D023, D019).
- **D. The Friedel ETA** only grows (329 → 106 positions/s, bursty, cancel ≈ 20 s): a Gate D when you want it.
- Carried: Thronsen's written confirmation (ADR 042); where precipitate analysis lives; the learned detector's tiled
  loop (awaits Core ML inside — no plain pool).

## 6. Kickoff prompt (paste into a new session, Auto mode)

> /pickup the overnight plan in docs/archive/v4/overnight-plan-2026-09-29.md. Read it, CLAUDE.md, docs/status.md,
> the memory notes it names. Run it unattended in order: Sonnet 5.5 subagents for implementation, drives and sweeps;
> you review every diff and every screenshot, gate, commit, and append to the plan's log after each item. First:
> caffeinate, request screen access for mac4DSTEM, confirm the owner's own app is not running, check disk and memory.
> Never push, never branch, one heavy job at a time. Decide, don't stall (§1): record → Opus advisor → reversible
> steps proceed as "decided overnight — overrule on sight" in §5; stop only on push/delete/shipped numbers/Frozen Shell. Stay curious: where a drive shows
> something clumsy, record it with a proposal. End with the §4 morning report.

## Log

- Start-up: caffeinate; owner's app not running; screen control granted and proved on a scratch build (pid 41839); 5.3 GB free; tree clean at `1a76089`, pushed.
- A3 `AppState`: `runStrainMapping` → `AppState+Strain.swift` (every run now has its own extension file; nothing widened; AppState.swift 1554 → 1430). Unit 941/0/2 = 943 (`unit-A123.log`), inventory 0.
- A2 Bragg restore: detection controls seeded from the recorded step on adoption (12 params, detector class, learned threshold); 9 tests, 7 mutations red (`a2-mut-*.log`); unit 941/0/2 = 943. Drive owed (B1).
- A1 disk-detection memory: pool per tile + `findMaxima` survivors copied to their own size (second mechanism, found by the harness); `tools/tiled-detection-memory-test` gated in `scientific`: original 473 MB / no-pool 321 / no-compaction 153 / shipped 1 MB over 12 tiles; Opus refuter NOT REFUTED WITH FIXES (mechanism wording corrected; learned + virtual-detector loops filed open). Unit 941/0/2 = 943.
- C triage: all 156 register clusters judged against `main` (two Sonnet sweeps + a refuter on the 37 science rows: 19 hold, 15 narrowed, 4 refuted); record `archive/2026-09-09-review/triage-2026-09-29.md`; open-items entry now names the 11 reachable Gate D candidates.
- B drive 1 (`report-drive1.md`, shots `d1-*`): seen — Bragg restore line "Disks restored from the session — 754479 peaks (detected 28. Sep 2026)" (`d1-02`), seeded controls current after Build Kernel (`d1-04b`), light mode on Thronsen A (`d1-07a/b`), load cancel (`d1-09c`), Recents labels (`d1-01`); found: inspector drag at 915 pt clips sidebar + inspector (`d1-08b`), restored 300-pt Object Table unreadable (`d1-01c`). Peak counts now grouped ("754,479"). Unit 945/0/2 = 947 (`unit-A4.log`).
- A4 table→map highlight (app-scoped relay keyed by the run's `sourceID`; outline overlay, never published) + "Any rotation" placeholder + Object Table minimum = its one-line summary + no window restoration. 4 tests, 6 mutations red (`a4-mut-*.log`); unit 945/0/2 = 947 (`unit-A4.log`). Drive 2 (`report-drive2.md`): outline around exactly the selected object (`d2-05b`), gone when the table closes (`d2-05f`), table clamps at 674 pt (`d2-06`), "Any rotation" (`d2-03a`); in-app Detect All on Thronsen A: 754,479 peaks = the restored run, footprint flat ≈ 1.18 GB for 1:28 (`d2-guard.log`); density help (edge-weighted wording) read from the running app. Unverified row emptied.
- D1 registered before any run (`phase-tolerance-registration-2026-09-29.md`, Opus): the premise corrected — the app ships 0.02 Å⁻¹ (≈ 3 px on the raw cube), the 97 % was the probe's own 1-px rule; status/open-items/probe comment fixed.
- C open-items: 521 → 346 lines (Sonnet draft, orchestrator-reviewed; every removed line verbatim in `archive/v4/open-items-detail-2026-09-29.md`); tonight's drive results folded in; cold-start set 585 lines (`inv-8.log`).
- AI-room crash (found by drive 3; Gate D registered first; E1/E2/E3 + Opus refuter): part 1 landed — the room's rows ≤ 248 pt, data names truncate, `InspectorWidthBudgetTests` (12, 6 mutations red); unit 957/0/2 = 959. Drive 4: entering the room at 915 now lives; the Info tab and a widest inspector drag still abort — Frozen Shell, owner (§5).
- Small fixes from the drives: an unchanged manual Q/R commit keeps its provenance; Manual-state help text; the Results badge dies with a cancelled load. 4 tests, 2 mutation runs red (`sm-mut*.log`); unit 961/0/2 = 963 (`unit-sm.log`). Drive 5 (orchestrator, build-app-5): R unchanged → "From session", Q 0,1905 → Manual with the new help, no Results badge after "Load cancelled" (`d5-02`); Thronsen sidecar byte-identical to its backup.
- D1 measured (Sonnet runner, Opus refuter; raw read after the amendment): the shipped max(0.02 Å⁻¹, 1 px) lies inside all four bands; raw cube at the app's 0.02 → matrix 84.4 %; P2 held, P1/P3/P4/P5 partly refuted as recorded; supports option (a). `--tolerance-px` added to phase-map-probe (refuses unparsable values). Record `phase-tolerance-results-2026-09-29.md`.
- Closeout: status.md rewritten for the morning (older gate rows → `archive/v4/status-history-2026-09-29.md`), ROADMAP facts, §4a report and §5 decisions written; Board republished; memory consolidated.
