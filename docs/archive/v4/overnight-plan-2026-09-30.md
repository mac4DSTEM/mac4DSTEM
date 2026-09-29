# Overnight plan — the remaining queue, S12–S23 (2026-09-30, unattended)

Owner's brief (2026-09-30): resolve every remaining session in one night, no input from the owner; Sonnet 5.5 subagents
do the work, a Fable 5.1 supervisor reviews after every important block, the app is driven for on-screen confirmation.
The session (Opus) plans, reviews every diff and screenshot, gates and commits. This file is the plan AND the log:
append one line per finished item and commit it, so a crash loses nothing. Model of this file: `overnight-plan-2026-09-29.md`.

Owner decisions taken before the night (2026-09-30): the queue below is accepted as ranked; science items that would
move a shipped number are **measure + propose** (YELLOW: commit the record and a ready patch, never the moved number);
reversible owner decisions go through "decide, don't stall" (§1) and land as overrule-on-sight; the D025 radius and D1
stay the owner's; volumetric density stays parked (ADR 046); Train Model…/C5 waits for the new hardware and no longer
blocks new surface (status "Unverified on screen" holds only what a session can drive).

## 0. Before the owner leaves (the only human steps)

1. **Free disk to ≥ 5 GB** (the machine sat at ~1.5 GB on 2026-09-30; the heavy-lock floor is 1.5 GB and a full unit
   build needs ~1 GB of headroom): e.g. delete `~/Library/Developer/Xcode/DerivedData` (1.5 GB, Xcode rebuilds it) and
   `~/Library/Developer/Xcode/CodingAssistant` (354 MB) — the session may not delete outside its scratchpad.
2. **Quit the owner's own mac4DSTEM** (same bundle id). Quit what else is not needed overnight (memory: 8 GB).
3. Start the session in **Auto** mode with the kickoff prompt (§6); approve screen control when it asks; stay until
   its first check (§3 step 0) passes.
4. Mac on power, awake, **not locking**; screen saver "Never"; **Claude Code auto-update off** (an update revokes
   Accessibility and driving stops silently). The session runs `caffeinate -dimsu` itself.
5. Push beforehand (GitHub Desktop), so the night starts from a pushed `main`.

## 1. Safety — nothing lost, nothing crushed

- **`main` only**, one coherent commit per item after its gate, this log committed after every item. No push, no
  branch, no in-repo deletes of tracked history, no force. A lost session resumes from this log and its scratchpad.
- **Machine rules** (the disk filled three times on 2026-09-29/30): every build/test/probe takes the heavy lock
  (`mkdir <scratch>/heavy.lock`, released by a trap), only when `df -m /` ≥ 1500 and swap used < 6000 M; `-jobs 2`;
  ONE shared scratch DerivedData; delete `Logs/Test/*.xcresult` after reading each run, and the
  `/var/tmp/test-session-systemlogs-*.logarchive` a test run can leave (~470 MB each; 1.4 GB on 2026-09-30); a guard kills builds below
  350 MB free. Never read an exit code through a pipe. Never full-read a file bigger than RAM (footprint guard on any
  probe over a multi-GB cube).
- **Parallel where safe:** Sonnet implementers on disjoint write-sets work in parallel; heavy jobs serialize behind the
  lock; two drivers may share the machine only with the focus lock (`mkdir <drive>/focus.lock` around every
  focus-needing click/keystroke) and each pid-pinned; never a drive during a memory measurement.
- **Drives:** a signed scratch build copied OUT of DerivedData before launching (`ditto` to `<scratch>/drive/appN`), so
  later builds never rewrite a running bundle; `open -n`, pid-pinned helpers (`axd`, `ev`, `winid`, `shot.sh` — rebuild
  from the 2026-09-30 session's scratch `drive/src` if gone); window-only shots; every claimed observation checked
  against its shot by the Fable supervisor before it is written as verified; restore the owner's window frame at the end
  ({0,33} first, then 1470×923). Back up any sidecar a drive can touch and `cmp` it after; drive on scratch copies of
  datasets when a save is part of the drive.
- **Decide, don't stall** (owner, 2026-09-29): (1) decide from the record — ADRs, CLAUDE.md, recorded preferences;
  (2) otherwise a **Fable advisor** subagent gets the evidence and the options, argues against the proposal,
  recommends; (3) if it endorses and the step is reversible, do it, commit with the reason and the verdict, list it in
  §5 as **"decided overnight — overrule on sight"**; (4) stop only on: push, a delete of tracked history, a moved shipped
  scientific number (YELLOW), a Frozen Shell redesign (`CLAUDE.md`), anything outside the repo.
- **Review per block:** after each cluster's gate, one **Fable supervisor** reviews the diagnosis (not the diff), the
  mutation evidence and every drive shot; FIX-FIRST goes back to the implementer; the commit names the verdict.
- **Clock:** no new heavy item after 06:30; the §4 morning report starts by 07:00.

## 2. The rubric

GREEN (do, gate, drive, commit): no shipped number moves, no owner-only decision, a gate that runs. YELLOW (measure,
refute, propose; commit the record + a ready patch file under `docs/archive/v4/`, not the change): anything that would
move a shipped number or verdict. RED (list only): push, owner-only decisions (D025 radius, D1), hardware.

## 3. The night, in order (GREEN first, YELLOW last)

Step 0 — start-up: caffeinate; owner's app not running; screen control proved on a scratch build; disk ≥ 5 GB and swap
noted; tree clean and pushed; `run-tests.sh unit` baseline count reconciled with `func test`.

Each item: Sonnet implementer (tests first, each red before the fix and red on a one-line mutation, cp+cmp restore) →
touched classes green → Fable supervisor → drive if it draws → commit (gate numbers in the message) → log line.
Size S/M/L; one full unit run after every two items and at the end.

- **S17 Lean sweep (S–M, GREEN, first as a warm-up):** retire the stale open-items entries the 2026-09-30 queue draft
  lists (S6 heading; S4 "fixed and seen" bullets; "Strain unlocks…"; `power_radial`; β″ ⟨110⟩ note; ptychography
  `analysis_mode`; #30 NAS; #31 validationIssues; the demo 0.247 ellipse refusal after `ellipse-calibration-test`
  confirms it is the designed refusal; drifted line refs). Diffraction groups: profile the single vs two-pass path under
  `-O`; delete the two-pass path only if the single pass wins AND fixtures stay byte-identical. The `.fixedSize` zoom
  badge only if it is really armed. Gate: unit + byte-identity.
- **S12 Stale marks II (M, GREEN):** the zone-axis ranking's stale check gains matrix phase + matching tolerance;
  objects redrawn at a new minimum size are recorded as their own run; "Computed this session" says what was computed
  (no new rows unless the surface rule allows — it now does, the Unverified row being session-drivable); the objects
  picture stripes challenged matrix like the map; the challenger's axis residual named or fixed. Drive: zone-axis
  notice (Q change, identical origin re-fit — empties the Unverified row), objects re-run, the objects picture.
- **S13 CIF trust (M, GREEN — refusal only, no number):** refuse a CIF whose symmetry-operation list is shorter than its
  space group's order (IT number → group order table), name the gap; a second block with only a symmetry loop no
  longer merges; `isSymmetry` bijection fixture. Gate: Gate D (diagnosis by reproducing CIF) + Fable refuter + unit.
- **S19 Regression net (M, GREEN):** acceptance reports compare positions, not counts; `compare.py fail()` collects
  all; an empty glob is a FAIL, not a SKIP-exit-0; `scientific` reaches the real-data harness where data exists. Each
  check broken first. Gate B by the Fable supervisor (a shared helper can green 46 harnesses).
- **S22 Accessibility (S, GREEN):** step 0 — one AX probe of a scratch build; retire what already holds, fix what does
  not (labels only), drive-verify.
- **S16 Virtual-detector tiled loops (M, GREEN measure → fix only if flat is refuted):** a
  `tiled-detection-memory-test`-style harness on Thronsen A 171²; if a leak shows, fix like A1 (pool per tile); in-app
  check under the footprint guard.
- **S18 Promote / replay / load tail (L, GREEN; do (a)(b)(d) first):** a superseded load's `discardPartialLoad` tail;
  promote position; fitted-origin shape check on a full-extent restore; replay contracts in three places; fabricated
  provenance on pre-2026-08-18 sidecars → refuse or mark "unrecorded". Gate B + drive on scratch copies.
- **S15 R–Q sign residuals (M, GREEN if it only refuses/labels; YELLOW if a number would move):** a datacube exported
  before 2026-09-28 is detected (version stamp) and refused or labelled, never silently flipped; the campaign report
  and the parallax fit's rotation get the new sign or a test. Beware the 90° symmetric test constant.
- **S23 Origin validity overlay (M, GREEN, new surface):** greyed excluded positions via
  `DisplayedProduct.validityMask`; unit + drive; the Frozen Shell files are not touched.
- **Owner decisions the night takes (decide, don't stall → §5):** detector move destroying the origin fit — banner vs
  refuse; persist the "Fit anyway" mark in the sidecar (wire format, additive); delete `CrystalModelLibrary` (pre-S5
  replay recipes only) if a Fable advisor endorses and old recipes still refuse by name; the origin-gate statistic and
  the reference-shell l-filter design (2H-WS2 2.26×) — decide or record why deferred.
- **YELLOW, last — measure, refute, propose (never commit the moved number):** **S14** origin coarse seed (vs the
  Gaussian-argmax comparator, every dataset it touches); **S20** ACOM off-grid recovery (dump the winner's and the true
  axis's templates for one failing case first); **S21** detection defaults (bullseye noise; drop TBG as off-path). Each:
  pre-registration committed before any run, Fable refuter, record + ready patch under `docs/archive/v4/`, §5 entry.

## 4. Morning

`docs/status.md` rewritten (handoff ≤ 450 words, gate row, Unverified row), ROADMAP queue lines ticked with commits,
open-items shorter (count entries before/after), the Board republished (read it first; one lane/queue view), a §4a
morning report here: what landed (commits), what was seen on screen (shots under `drives-2026-09-30-night-shots/`),
what is proposed (YELLOW), §5 decisions, what did not fit and why. Memory notes updated last.

## 4a. Morning report

(written at the end of the night)

## 5. Decisions for the owner (filled in during the night)

(each: the decision, the record/advisor verdict, the commit, how to overrule)

## 6. Kickoff prompt (paste into a new session, Auto mode)

> /pickup the overnight plan in docs/archive/v4/overnight-plan-2026-09-30.md. Read it in full, then CLAUDE.md,
> docs/status.md, ROADMAP.md's Session queue, docs/open-items.md and the memory notes it names. Run it unattended, in
> §3's order, with no input from me: Sonnet 5.5 subagents implement, drive and sweep (disjoint write-sets in parallel,
> heavy jobs one at a time behind the lock); after each important block a Fable 5.1 supervisor reviews the diagnosis,
> the mutation evidence and every drive shot, and nothing lands on its FIX-FIRST; you review every diff and screenshot,
> gate, commit with the numbers, and append one line to the plan's log per item. Drive the app for every on-screen
> change (scratch build copied out, pid-pinned, window-only shots). First: caffeinate, request screen access for
> mac4DSTEM, confirm my own app is not running, check disk ≥ 5 GB and memory, write the session rules into your
> scratchpad's resume file. Never push, never branch. Decide, don't stall (§1): record → Fable advisor → reversible steps
> proceed as "decided overnight — overrule on sight" in §5; YELLOW science stops at a committed proposal; stop only on
> push / delete / a moved shipped number / Frozen Shell / outside the repo. Stay curious: where a drive shows something
> clumsy, record it with a proposal. End with the §4 morning report and the Board.

## Log

- Step 0 (21:32): caffeinate on; owner's app not running; 9.1 GB free, swap 2.1 GB; tree clean and pushed; unit baseline
  1203 / 0 / 2 = 1205 = `func test` on 453f344 (`unit-base.log`); screen control proven on a scratch build (a pid-pinned
  click moved Prepare → Bragg Disks).
- S17 Lean sweep: open-items 21 → 20 headings, 43 → 38 bullets, 189 → 179 lines (retired entries' evidence cited in the diff);
  the two-pass diffraction-groups path KEPT — it is the memory bound past 512 MB; single pass 25.6–26.1 s vs two-pass
  51.2–51.5 s at -O, outputs identical (`profile-dg2.log`); zoom badge not armed (by reading). Fable supervisor COMMIT;
  unit 1250 / 0 / 3 = 1253 (`unit-b1.log`).
- S13 CIF trust (Gate D): a symmetry list shorter than the named IT group's order is refused by name (reproduced first: MgO
  225 with 48 ops imported as CsCl, 2 sites / 1 308 reflections vs 8 / 330); a symmetry-only second block no longer merges;
  bijection fixture; a garbled-coefficient crash found and clamped. All 10 References CIFs identical before/after (dump
  rebuilt on the final file); cif-symmetry-test exit 0 (`cif-harness.log`); 77 / 0 in the CIF classes (`log_green2.txt`);
  4 mutations red. Fable refuter/supervisor COMMIT (every claim HOLDS; it caught a false "harness exit 0" — re-run).
- S19 Regression net: compare.py collects every mismatch; 173 peak positions pinned on the 5 pinned datasets (0.05 px,
  bit-identical across 3 runs / 2 builds); no data = FAIL; `scientific` reaches the harness (loud CI opt-out). Each check
  broken first (14 comparator mutations; a 1 px moved peak; a +0.3 px `polyRefine` shift → 15 named FAILs where counts saw
  nothing). run.sh 60 → 73 s. Fable Gate B FIX-FIRST (a dead citation; the unnamed mutation site) → fixed → COMMIT.
- S16 Virtual-detector tiled loops: measured FLAT (prediction "growing" refuted; written before the run) on all six streaming
  paths, 0–2 MB over 10 tiles; `virtual-detector-memory-test` gates it (retained-buffer mutants red at 352 MB), in `scientific`;
  Thronsen A: 778 MB between passes, no growth. No code change. Fable supervisor COMMIT.
- S12 Stale marks II: zone-axis ranking stale on a changed matrix phase / matrix-removal tolerance; objects redrawn at a new
  minimum size recorded as their run; Info "In memory" says fitted here / restored / N peaks (Frozen Shell wording only, the
  helper moved out); the objects picture stripes challenged matrix; the challenger limit named in the evidence line. 122 / 0,
  M1–M12 red. Fable supervisor COMMIT; drive 1 VERIFIED a–e on screen (supervisor checked every shot); an identical origin
  re-fit leaves the ranking current (empties the Unverified row). Post-drive string fixes (grouped count, "· restored",
  "matrix removal") gated (14 / 0, grouped-count mutation red) — re-driven in drive 2.
- S23 Origin validity wash: excluded positions greyed in Prepare's real-space pane with a count legend, gated by Fit overlay; no
  new control, no Frozen Shell. 8 / 0, two mutations red. Fable supervisor COMMIT (not transposable; 5×4 asymmetric mask); drive
  1: 891 of 8400 = Positions used 7509, toggle, Results and rotation seen; pinch zoom not synthesisable.
