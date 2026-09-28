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

## 1. Safety — nothing lost, nothing crushed

- **`main` only**, one coherent commit per item after its gate; `git stash create`/`store` before any risky step;
  this log committed after every item. No push, no branch, no in-repo deletes, no force.
- **One heavy job at a time** (build, unit gate, probe, drive). `df -h /` ≥ 4 GB before a build (free only the
  session's own scratch DerivedData); memory pressure checked; every probe on a multi-GB cube under the footprint
  guard (`phys_footprint` > 1.5 GB or critical pressure → kill; rebuild `guard.sh` from memory note
  never-full-read-bigger-than-ram). **No Detect All Disks in the app on multi-GB cubes** until item A1 lands.
- Drives: a scratch build (`-derivedDataPath` in the scratchpad), launched `open -n`, pid-pinned; every claimed
  observation checked against its screenshot by the session before it is written down.
- Stop, don't guess: an owner decision is written into §5 with a recommendation and the session moves on.

## 2. The rubric, updated

GREEN (do and commit): no number moves, no owner decision, a gate that runs — now including **on-screen checks**,
since the session drives. YELLOW (measure, refute, propose; commit the record, not the change): anything that
moves a shipped number or a shipped verdict. RED (list only): owner decisions, pushes.

## 3. The night, in order (GREEN first, YELLOW last)

**A — finish tonight's work (GREEN)**
1. Gate D fix: autorelease pool per tile in `TiledDiskDetection.detectAll` (experiment in
   `tiled-detection-memory-gateD-2026-09-29.md`), a gated memory harness broken first, refuter, unit gate.
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

## 5. Decisions for the owner (filled in during the night)

## 6. Kickoff prompt (paste into a new session, Auto mode)

> /pickup the overnight plan in docs/archive/v4/overnight-plan-2026-09-29.md. Read it, CLAUDE.md, docs/status.md,
> the memory notes it names. Run it unattended in order: Sonnet 5.5 subagents for implementation, drives and sweeps;
> you review every diff and every screenshot, gate, commit, and append to the plan's log after each item. First:
> caffeinate, request screen access for mac4DSTEM, confirm the owner's own app is not running, check disk and memory.
> Never push, never branch, one heavy job at a time, stop-don't-guess into §5. Stay curious: where a drive shows
> something clumsy, record it with a proposal. End with the §4 morning report.

## Log
