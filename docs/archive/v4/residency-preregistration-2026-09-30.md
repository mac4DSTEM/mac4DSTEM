# Residency returns, measured — pre-registration (2026-09-30; NOT started)

Queue line: `ROADMAP.md` › "Residency returns, measured" (owner, 2026-09-30). Governing record: ADR 013 (`.automatic` dropped,
not tuned; `measuredWorkingSetFraction` nil "kept as the return path"). This file is written before any code or run.

## What it would change, and who owns the state
- `ResidencyAdmission.measuredWorkingSetFraction` (`Core/Data/ResidentCube.swift`) nil → one measured fraction; `Residency`
  regains `.automatic`, resolved by `ResidencyAdmission.admits` (already a fraction of the machine's own working set, never a
  byte count, still clamped by `maximumBufferLength`). `LoadConfiguration.fitsResident` starts answering; it has no production
  caller, so **no new surface** (the ROADMAP line's condition). No `AppState` state; the owner is `ResidencyAdmission`.
- Numbers do not move: resident and tiled paths are parity-gated to the same results. What moves is speed and memory — the
  failure class is "slower than tiled while appearing to succeed" (the constant's own comment).

## Gates and rules this session must clear
- `CLAUDE.md` hard rule "Do NOT set `measuredWorkingSetFraction`" and ADR 013 stand until the owner lifts them **in that
  session**; if lifted: a superseding ADR, the rule edited in `CLAUDE.md` (+ `tools/sync-agents-md.sh`).
- Gate D (a threshold is being set) and an independent refuter reading the sweep's own output, not the diff.
- Threshold rule: a knee measured on one machine is that machine's. Measure it on **two**: this M5 Pro (64 GB, working set
  55.7 GB, max buffer 41.7 GB) and the old 8 GB M3 with a cube near its own budget (a ≤ 2 GB file — the old Mac's panic line).

## Measurement plan (predictions stated before running)
1. Data near the budget: the raw Al-Mg-Si DM4 (28 GB on the external SSD); `residency-sweep` reads HDF5 only → convert once to a
   local HDF5, or scan-crop it into a ladder of sizes (≈ 10 / 20 / 30 / 40 / 50 GB as float32 — `byteCountAsFloat32`, not the file
   size). Read the file's real shape and dtype first; nothing is assumed from its size. Local copies only (a NAS measures the link).
2. Per size: `residency-sweep` resident vs tiled, ≥ 3 repeats, with phys_footprint, swap and memory pressure logged.
   **Prediction:** resident beats tiled up to a fraction of the working set, then degrades sharply once Metal pages; the
   knee is expected between 0.5 and 0.8 of 55.7 GB. **Refuted if** there is no knee (resident never faster, or never slower
   before the 41.7 GB buffer cap), or repeats disagree by more than the gap being measured.
3. The fraction ships only if both machines' knees, as fractions, agree within the margin chosen before the old-Mac run;
   otherwise the owner chooses (below). A knee that is not clean keeps ADR 013 as it is — that is a result, not a failure.

## Tests written before the change
`admits` / `resolve` with injected working-set sizes (8 GB and 64 GB) — the same cube streams on one and goes resident on the
other; `.automatic` never exceeds `maximumBufferLength`; each broken by a one-line mutation first. Parity: the existing
resident-vs-tiled harness on one real cube.

## Decisions owed to the owner (at that session's start)
1. Lift the `CLAUDE.md` rule and ADR 013 for this attempt. 2. One fraction for every Mac, or `.automatic` only above a measured
machine size if the two knees disagree. 3. Disk for the converted/cropped copies (tens of GB; 779 GB free on 2026-09-30).
