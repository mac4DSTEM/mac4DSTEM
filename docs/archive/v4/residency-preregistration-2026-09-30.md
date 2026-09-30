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
- Threshold rule: a knee measured on one machine is that machine's. Only this M5 Pro (64 GB, working set 55.7 GB, max buffer
  41.7 GB) is available — the old 8 GB M3 was retired 2026-09-30 — so the fraction is measured on one machine, and that is
  decision 2 below, not a footnote.

## Measurement plan (predictions stated before running)
1. Data near the budget: the raw Al-Mg-Si DM4 (28 GB on the external SSD); `residency-sweep` reads HDF5 only → convert once to a
   local HDF5, or scan-crop it into a ladder of sizes (≈ 10 / 20 / 30 / 40 / 50 GB as float32 — `byteCountAsFloat32`, not the file
   size). Read the file's real shape and dtype first; nothing is assumed from its size. Local copies only (a NAS measures the link).
2. Per size: `residency-sweep` resident vs tiled, ≥ 3 repeats, with phys_footprint, swap and memory pressure logged.
   **Prediction:** resident beats tiled up to a fraction of the working set, then degrades sharply once Metal pages; the
   knee is expected between 0.5 and 0.8 of 55.7 GB. **Refuted if** there is no knee (resident never faster, or never slower
   before the 41.7 GB buffer cap), or repeats disagree by more than the gap being measured.
3. A knee that is not clean keeps ADR 013 as it is — that is a result, not a failure. A clean knee is this Mac's; how far it
   travels is the owner's decision 2.

## Tests written before the change
`admits` / `resolve` with injected working-set sizes (8 GB and 64 GB) — the same cube streams on one and goes resident on the
other; `.automatic` never exceeds `maximumBufferLength`; each broken by a one-line mutation first. Parity: the existing
resident-vs-tiled harness on one real cube.

## Decisions owed to the owner (at that session's start)
1. Lift the `CLAUDE.md` rule and ADR 013 for this attempt. 2. One machine's fraction for every Mac, or `.automatic` only on
Macs at least this one's working set (smaller Macs keep streaming, today's behaviour). 3. Disk for the converted/cropped copies (tens of GB; 779 GB free on 2026-09-30).

## Added 2026-09-30 evening (owner discussion + Fable advisor, before any run)
- **The deliverable is the characterisation itself** (owner: "this knowledge could be useful in the future anyways"): the
  resident-vs-streamed curve on this Mac is committed under `docs/archive/` whatever ships. Step 0, before the ladder: is
  resident faster at all? The only timing in the repo is a 134 MB synthetic cube on the retired M3 (S18, 2026-08-27; the
  resident number varied by half). Resident skips the disk read but keeps the tiled reductions (bit parity), so a single
  pass may gain little and repeated passes (detection, many virtual images) most — time both kinds.
- Sizes are `byteCountAsFloat32`: a uint16 file doubles in memory (the 28 GB raw may be 56 GB, above the 41.7 GB buffer cap
  — then it can only stream; crop below the cap for the upper rungs).
- Alternatives weighed and parked until the curve exists: a per-open user toggle in `UI/LoadConfigurator.swift` (a room, not
  frozen; its caption already describes a control that does not exist; needs the drive rule cleared and a mock first); a
  fixed rule "half the working set" (owner withdrew it: macOS and other apps take a roughly fixed few GB, so half is generous
  on 64 GB and risky on 8 GB). If resident is not faster, the lean-app outcome is to remove the unreachable "Release cube"
  button and `fitsResident` and close the line as measured-and-declined.
