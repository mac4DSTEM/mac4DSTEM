> Gate B notes by the independent Fable 5.1 reviewer (read-only), 2026-10-13, on `71929a01..5311bc43`. Verdict PASS WITH CHANGES; the one blocking item (four moving test files used the app-side `fourD:` overload and `.fourDCube`) was fixed in the next commit and re-checked: the reviewer's sources-only package plus the 28 moving test files builds clean from scratch with 0 errors. Logs it names are session logs, not retained.

# Gate B notes — SpectroKit S0+S1, 71929a01..5311bc43 (2026-10-13)

Evidence files here: d-lock.diff, d-cancel.diff, d-seams.diff, moving.txt (54 files), skpkg/ (scratch package),
sk-sources.log (rc 0, "Build complete"), sk-tests.log (rc 1, 40 errors), golden.log (rc 0, golden passed 28.0 s, record skipped).

- Strip check: 30 source files of 5311bc43 byte-identical after `perl -pe 's/\b(public|package)\s+//g'`; 438 (+public) / 438 (-package).
- func test by name: 2472 → 2474 (+2 golden) → 2481 (+7 lock) → 2491 (+10 cancel) → 2491 to the freeze; names identical across the partition.
  My regex undercounts the gate's by a constant 3; deltas match 2475 → 2477 → 2494.
- Helper copies: spectroDisplayFileName == displayFileName (FourDDataSource.swift:19); spectroKilovolts == kilovolts(fromAttribute:) (:81).
- libhdf5 calls in VeloxEMDReader.swift: all at 713/719 (init/deinit, locked) and in the private *Locked methods 725-854, each reached
  only through its HDF5Serial.run wrapper; images/readImageFrame/isVelox*/readFrame*/storedElementSelection hold the lock whole.
- App catch sites at default args: open paths use Task.detached (no cancellation inheritance) + load.isCancelled after; compute() at
  SpectroscopyRoomController.swift:751 discards a cancelled task's output; proposer keeps ProposerError.cancelled (caught :328, :637).

## Verdict as reported (supervisor's transcription of the reviewer's hand-back)
**Blocking (fixed):** the moving test files `SpectroCancellationTests.swift:107,115,119`, `SpectroscopyQuantifyTests+Spectro.swift:17`,
`SpectrumImageOpeningTests+Spectro.swift:34,70` called `openGMSEDS(path:fourD:)` and `SpectroscopyLaneUTests+Spectro.swift` used
`BeamEnergySource.fourDCube` — both app-side (`Core/Data/GMSFourDRegistration.swift`). The sources-only package built clean; with the 28
moving test files it failed with 40 errors. Fix: the library overload `openGMSEDS(path:)`, and `.supplied(label: "the 4D cube, same run")`.

**Verified:** (1) no number moved — the golden comparison reproduced on the reviewer's own copy of 5311bc43; changed paths it does not
reach are pinned elsewhere (the registration overload by staying tests; multi-block Velox by `testSmallBlocksGiveTheSameStoreAsTheDefaultBlock`
and velox-parity; the marker scans and image reads by the lock test and velox-parity). (2) Every libhdf5 call in `VeloxEMDReader.swift`
runs under `HDF5Serial` (init/deinit and the private `*Locked` methods); open handles across unlocked decode are legal; exit now waits at
most one block. (3) `SpectroCancelled` is rethrown before every swallowing catch; nothing partial is returned; default-argument calls
resolve to the old behaviour; progress monotone. (4) The seams reproduce the old logic exactly. (5) The moving sources compile alone.
(6) `public` is access-modifiers only, 438 ↔ 438, ζ not public. (7) 258 moving names. (8) Gate counts reconcile.

**Non-blocking, carried to S2:** moving tests read `mac4DSTEM/Resources/Spectroscopy/*.csv` and Proposer *source* by `#filePath`
(`SpectroscopyProposerTests.swift:286` and five more); the proposer keeps `ProposerError.cancelled` (two cancel errors); the joint open
parses the DM4 tag tree twice; `FitRange`/`Unlisted` report progress 0 twice; the app passes no `cancelled:` yet (a cancelled load waits
for the whole read); main-actor isolation warnings in the moving tests (Swift 6 in S2).
