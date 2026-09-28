# Restore detected Bragg disks from the session sidecar — registration (2026-09-28 night)

Owner's idea 2026-09-28: detect disks once (the compute-heavy step), keep them, and start precipitate analysis,
strain or ACOM later without detecting again — as py4DSTEM does. Registered before any code.

## What exists (verified in code)

The sidecar already WRITES every peak: `BraggVectorEMDWriter.writePeakGrid` → `braggvectors/_v_uncal`, py4DSTEM
0.14's `PointListArray` (float64 qx, qy, intensity per position; `BraggVectorEMDWriter.swift:1986`) with the
detection provenance attribute. On open, `loadSession` only checks the group exists (`:551`, the sidebar's
"BraggVectors" label) and `activate` clears the peaks (`AppState+Open.swift:592–595`). No decision records why: the
read half of a round trip was never built. Thronsen A's sidecar holds 754 479 peaks (≈ 18 MB). py4DSTEM reads the same
group back (`braggvectors.py:314–320`).

## The change

1. `BraggVectorEMDWriter.loadPeakGrid(from:)`: reads `_v_uncal`, swaps py4DSTEM's axes back, returns `BraggVectors` and
   the provenance. Float32 → float64 → Float32 is exact, so restored peaks are the detected ones bit for bit.
2. On open, after the calibration restore (off the main actor, epoch-guarded like it), adopt the peaks **only when**
   the scan and detector shapes match the loaded view, the recorded load specification matches, the replay record
   has a disk-detection step, and the stored provenance matches that step. Otherwise leave them and say why in the
   status line. Adopted: "Disks restored from the session — N peaks (detected <date>)".
3. **Staleness hole closed first:** with no probe kernel, `currentReplaySignature(.disks)` is nil and the verdict is
   `.current`, so restored peaks would look valid before anything could say so. Restored peaks are judged against the
   recorded step until a kernel exists; a kernel built with other settings marks them stale (the existing rule).
4. State: `resultPresentation` (where peaks already live) — nothing new in `AppState`.

## Tests before code (each broken first)

Round trip write → read, per position, including empty positions and the axis swap (mutation: no swap); each refusal
(shape, load specification, missing step, provenance mismatch); the nil-kernel staleness case (mutation: today's
`.current`); restoring does not touch the learned-detector record or the replay record. Not Gate D — no number moves
(bit-identical peaks) — but a drive is owed: open Thronsen A, see "Disks restored", map phases without detecting.

## Decision for the owner (recommended default in bold)

Restore **automatically when every check passes**, or ask each time ("Use stored disks?").
