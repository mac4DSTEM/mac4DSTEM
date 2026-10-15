# The switch to SpectroKit 0.4.0 and FormatoKit 0.0.3 — registration (2026-10-15, lane R2; tier 1 for numbers, tier 2 for the plumbing)

Registered at `37f0c0d3`, before any switch code; the BEFORE values below were recorded on that unswitched tree (logs under the
lane's `before/`). The kits' claims are `SpectroKit/docs/consumers-0.4.0.md` (§1-§3, §5-§7) and `FormatoKit/docs/consumers-0.0.1.md`
to `-0.0.3.md` (tag `0.0.3` = `8d647bd`, SpectroKit `0.4.0` = `9b93fb4`). The readers (DM4, Velox EMD), the HDF5 lock and the
line, quantification and fit code move between modules: **no number a scientist reads may move** (byte-identical outputs), except the
two moves the notes name. One refuter on the frozen switch. Gate D does not apply (no diagnosed defect).

## One change, two pins
SpectroKit 0.1.0 to 0.4.0 and FormatoKit 0.0.3 together (consumers-0.4.0 §5: two `HDF5Serial` locks around one thread-unsafe
libhdf5 is the race the lock exists to prevent). Products: SpectroEDX, FormatoCore, FormatoDM, FormatoEMD, FormatoHDF5 beside SpectroCore.

## Predictions
- **R1 (unit).** BEFORE: 2436 test names, 2432 passed, 0 failed, 4 skipped (`unit-before.log`, `before/unit-testcases.txt`). AFTER:
  the same 2436 names with the same outcomes, plus the one new test `HDF5SingleLibraryTests` (2437). No test is removed: the two
  moved-test copies (`DM4ExperimentTests`, `DemoEDXFixtureTests`) stay as consumer tests; two assertions of the second that need
  FormatoDM's `package` API (`experimentIDs`, `spectrumImageRect`) go, held by FormatoKit's `DemoEDXFixtureTests+Spectro.swift`.
- **R2 (golden).** The seven golden files of `SpectroGoldenTests` are byte-identical except `velox-tiny.txt`, which gains exactly the
  13 nil lines of the six Velox metadata fields SpectroKit 0.2.0 added (consumers-0.4.0 §3 last line), and no value line changes.
- **R3 (Velox parity).** `tools/velox-parity`: 20 cases and 27 image stacks (80 frames) compared, 0 failures, every line equal to BEFORE.
- **R4 (DM4 and HDF5 harnesses).** `tools/dm4-robustness-test` all passed with the same PASS lines; `tools/hdf5-exit-race-test`
  order PASS and 200 of 200 runs clean; `tools/dm4-parity-probe` on its synthetic 128 MB DM4: the subsample file's sha256 and the
  484 of 484 bit-identical verification equal BEFORE.
- **R5 (Auto ID on the owner's Velox file).** `tools/autoid-velox-check` on `$MACEM_DATA/stem-edx/SI HAADF 1456 77000 x 20260420.emd`:
  hits 4 of 7, extras 4, the same picks; `00.json`, `00.spectrum.u64` and `summary.json` byte-identical (the owner file writes its
  detector keys in index order, so FormatoKit 0.0.3's written-order rule moves nothing: consumers-0.0.3, last bullet).
  The harness did not compile at `37f0c0d3` (three breaks left by S4: the kit import inside `#if canImport(DSTEMCore)`, the
  `package` reach of `storedElementSelection`, the internal `LineConflict.init`); BEFORE was recorded with a temporary patch
  (`before/autoid-temp-harness-patch.diff`), not the repo's code.
- **R6 (one libhdf5).** In the unit test host (the app process) after the app's writer and FormatoKit's Velox reader have both
  entered libhdf5, dyld has mapped exactly one libhdf5, one libsz and one libaec, each the app's `Frameworks/` copy.
- **R7 (scientific, core, inventory).** `tools/gate.sh scientific`, `core` and `inventory` green with the same harness list.

## Checks
The unit, core, scientific and inventory gates on the lane's tree; counts by name. Mutations (tier 2 sample): the lock path and a
moved import's behaviour, each seen red and restored; the new test broken once. A failed prediction is reported, not amended.
