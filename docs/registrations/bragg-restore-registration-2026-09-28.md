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

## Built (2026-09-29; Sonnet implementer, reviewed)

`BraggVectorEMDWriter.loadPeakGrid` (axes swapped back, empty positions, float64 → Float32); `SessionPeakRestore`
(pure adoption checks, in `SessionCalibrationFramePolicy.swift`); `restoreSessionPeaks` at the end of `activate`,
detached and epoch-guarded; `DiskDetectionRecordMatch` maps the provenance keys to the replay step's. **Automatic**
(owner's choice) when the load specification decides `.identity`, a disk-detection step exists, and scan shape,
detector shape and all 14 provenance keys match; otherwise "Stored disks not used — <why>". Adoption sets only the
peaks and their count; replay and learned-detector records untouched. **Staleness hole closed:** with no kernel the
disk signature is the peaks' own provenance restated in step keys, so a missing or disagreeing step reads stale.
16 tests (`BraggPeakRestoreTests`), each red under its named mutation (`bragg-mut-*.log`). Unit **932 / 0 / 2 = 934**
via the script's own xcodebuild line (`run-tests.sh unit` refused, exit 69: 3.7–4.0 GB free; scratch builds deleted
after). **Open:** the detection controls stay at detector defaults after a restore, so once a kernel is built the
restored disks read "computed with different settings" — seed the controls from the recorded step (next). **Not yet
seen on screen** (the owed drive).


**Seeded (overnight A2, 2026-09-29 night; Sonnet implementer, reviewed):** on adoption only,
`DiskDetectionRecordMatch.controls(fromStepParameters:)` — the reverse of `replayParameters`, nil unless every key
parses, so never a partial seed — sets all 12 `DiskDetectionParams`, the detector class and (learned) the threshold.
The kernel keys have no control (a kernel is built, not set), and a learned step reads stale on
`learned_model_sha256` until the model is prepared. 9 tests (`DiskDetectionControlsFromStepTests`,
`BraggPeakSeedsControlsOnOpenTests`), each red under its mutation (`a2-mut-*.log`); unit 941 / 0 / 2 = 943.
