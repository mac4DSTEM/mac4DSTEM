# ProposerError error 2 in the Auto ID Velox check (diagnosis, Gate D)

Scope: diagnosis only. No fix, no repo file edited, nothing written beside the owner's files.
Trigger: the cause of a defect is not established (Gate D). The owner's drive was read only.

## 1. What error 2 is (read from source, before any run)

- `mac4DSTEM/Core/Spectroscopy/Proposer/ElementProposer.swift:118` declares
  `package nonisolated enum ProposerError: Error, Equatable` with cases in this order:
  0 `lengthMismatch`, 1 `noChannels`, 2 `rankDeficient`, 3 `cancelled`.
- The harness prints `harness.ProposerError error 2.`: the module name is `harness` (the binary is built
  with `-o harness`), and the code is the 0-based declaration index, so **error 2 = `rankDeficient`**.
- `rankDeficient` is thrown at one site only: `ElementProposer.swift:218`, inside the proposer's
  `run(_:on:)`, when `FitNullVariance.compute(design:result:)` returns nil.
- `FitNullVariance.compute` (`Proposer/FitNullVariance.swift`) returns nil in three ways:
  (a) `k == 0` or `n < k` (fitted channels fewer than supported design columns plus free columns);
  (b) `FitLinearAlgebra.pseudoInverse` returns nil, which happens when `dmax == 0` or
      `dmin/dmax <= 1e-10` on the diagonal of R from the QR of the scaled design, or when LAPACK
      `info != 0`.
- The design (`Fit/LinearDesign.swift`) depends on the axis (offset, scale, size), beam energy, resolution,
  fit window and the group set of that pass. Counts enter the design only through `.countsAboveEdge`
  reference shapes (not used by Auto ID) and through the forward loop, which decides which groups a pass
  contains. Line and escape columns are zeroed and marked unsupported when `max < 1e-8`, so an all-zero
  column is excluded before the QR. `FitNullVariance` uses the fitted model only for the variance values,
  not for rank.
- The harness catches the error in `main.swift`: `analyse` throws, the `do/catch` in `main()` records
  `skipped <name>: failed: ... error 2`, and no `<n>.json` is written for that file.

## 2. The failing entries (tv.log lines 151-156, paths resolved on the owner drive by find)

| tv.log name | count in log | path(s) on /Volumes/PL_SSD_2TB/NAS_Backup/01_projects |
|---|---|---|
| SI HAADF 0944.emd | 2 | LOT_Quadrature_Project/HP087/HP_087_overview_images_20250402/emd/ ; LOT_Quadrature_Project/HP087/20250402/emd/ |
| SI HAADF 1121.emd | 2 | LOT_Quadrature_Project/HP087/20250415_EELS/Overview_images/emd/ ; LOT_Quadrature_Project/HP087/20250415/Overview_images/emd/ |
| SI HAADF 1140.emd | 1 | LMN_EM_General/for_Safarov/MF_0cycle_2/ |
| SI HAADF 1253.emd | 1 | LMN_EM_General/for_Safarov/Ag-SiO_2-ITO_BA_MS/PL_MS_AgSiO_2-ITO_lam/ |

Scored copies of 1253 (tv_out JSON, `file` key): LMN_EM_General/for_MDW/MDW_PL_Maurice/ (tv_out/51.json,
totalCounts 3527799, scan [350,1000], 4096 ch, 200 keV) and LMN_EM_General/for_MDW/MDW_PL_Maurice_2/
(tv_out/54.json, same numbers). The third copy (Ag-SiO_2-ITO_BA_MS) is the one that failed.
Total in tv.log: 112 files found; 17 skipped for no stored selection; 1 refused (not Velox); 6 failed with error 2.

## 3. Prediction (written before any build or run)

Predicted mechanism: the throw at line 218 comes from `pseudoInverse` returning nil on a near-rank-deficient
design (the R diagonal ratio falls to 1e-10 or below), at a forward-loop pass whose group set adds a
candidate whose line column (or escape column, or the polynomial background) is nearly collinear with
another column inside the fitted window. It is not `n < k` and not an all-zero design: the design
cannot be all zero for a file with a supported line, and a file with fewer channels than columns
would be a property of the axis that the 4096-channel scored files would not share.

Predicted observations that would support it:
- P1: the reproduced throw is the same `rankDeficient` (error 2) on re-run (deterministic), on every one of the 6 entries.
- P2: at the throwing pass, n >= k and the smallest |R_jj| / max |R_jj| is at or below 1e-10.
- P3: the Ag-SiO_2 copy of 1253 has a different sha256 from the two MDW copies and its axis or counts differ from them;
  the two MDW copies have identical sha256 (or identical bytes) and both scored.

Refuting observations (any one refutes the predicted mechanism):
- R1: the throw is a different error case (not 2), or it does not reproduce on re-run (nondeterministic).
- R2: at the throwing pass n < k, or dmax == 0 (all R diagonal zero), or LAPACK info != 0. Then the cause is the
  axis/window or a zero column, not near-collinearity.
- R3: the Ag copy's axis (offset, scale, size, beam) and totals are identical to a scored copy and its bytes are identical,
  so the failure would have to come from the counts alone (through the forward loop), which would move the cause
  from the design to the data and would need a different prediction.
- R4: the six failing entries all have the same axis as scored files and no smaller-than-expected n: then the
  near-collinearity must come from the counts, and I would report "mechanism of the group set, unknown which pair".

Predicted fix direction (not a fix): a guard in the proposer, not a change to the threshold; to be registered only after the mechanism is proven.

## 4. Commands run (in order)

1. Read-only: `grep` for `enum ProposerError`, `rankDeficient`, `ProposerError`; read `tools/autoid-velox-check/run.sh` and `main.swift`;
   read `ElementProposer.swift` 110-240, `FitNullVariance.swift`, `LinearDesign.swift` (build, fitChannels), `FitLinearAlgebra.swift` (pseudoInverse).
2. Read-only: `find` for the four file names on /Volumes/PL_SSD_2TB/NAS_Backup/01_projects; read `tv_out/*.json` (the `file` key) to map the scored 1253 copies.
3. `shasum -a 256` and `stat` on the duplicate copies (read only).
4. Heavy lock: `mkdir .../locks/heavy.2` (succeeded on the first try), build, `rmdir` (done; lock dir confirmed absent at the end).
5. Build the UNMODIFIED repo harness the way run.sh does: a scratchpad copy of run.sh with WORK fixed to scratchpad/research/build and the
   final run line replaced by an echo (`research/build-harness.sh`; log `research/build.log`, exit 0, no `error:` lines).
6. Reproduction: `research/build/harness --out research/rep/<n> <one file>` for the 6 entries and the scored 1253 MDW copy as control (`research/rep/*.log`).
7. Diagnostic copy (NOT a repo edit): `research/diag/` = copy of `mac4DSTEM/`, `tools/`, the three dylibs, with stderr prints added to
   ElementProposer.swift (pass axis/groups, sum groups with %.17g energies), FitNullVariance.swift (n, k, column names; per-column best
   |cos| with an earlier column on pseudoInverse failure) and FitLinearAlgebra.swift (the R diagonal at the failing pivot). Built under the
   heavy lock (3 builds, all exit 0, 0 `error:` lines). Logs `research/diag-run/`.
8. Pass-level check across all passes of 5 files (`f1`-`f5` logs): does a pass with a duplicate sum energy coincide with the failing pass?

## 5. Observations

- O1 (reproduced, deterministic): all six entries fail with `harness.ProposerError error 2` on a fresh run from the unmodified repo harness.
  Both copies of 0944 (same sha256 `094419e5...`) and both copies of 1121 (same sha256 `3d402052...`) fail. Each run ends with
  `skipped <name>: failed ...` and no `<n>.json`. The harness exits 0 when files fail (the failures are only in its skipped lines).
- O2 (the throw): the failing pass always has `pseudoInverse` nil at its R diagonal, with n >= k and dmax = 1.0:
  - 0944 (HP_087 root): n=991, k=102, R_jj ratio 2.68e-16 at column 41 (`sum:Dy+Ti`).
  - 1121 (20250415): n=991, k=125, ratio 3.71e-16 at column 64 (`sum:Dy+Ti`).
  - 1140: n=1981, k=47, ratio 1.17e-16 at column 18 (`sum:In+Si`).
  - 1253 Ag copy: n=1981, k=77, ratio 2.26e-16 at column 43 (`sum:In+Si`).
  Not n < k (R2 refuted), not an all-zero design (dmax = 1).
- O3 (the duplicate): in each failing pass exactly one column has |cos| > 0.999999 with an earlier column, and it is identical to 16 digits:
  - 0944 and 1121: `sum:Dy+Ti` vs `sum:Cs+Ho`, cos = 0.9999999999999997, rawnorm 0.2777266121569712 for both, nz = 52.
  - 1140 and 1253 Ag: `sum:In+Si` vs `sum:Ag+Zr`, cos = 0.9999999999999997, rawnorm 0.2339911562735358 for both, nz = 73.
  Energies, printed by the diagnostic (%.17g): `sum:Cs+Ho` E=11.0061, `sum:Dy+Ti` E=11.0061, FWHM 0.17224546438150412 (identical);
  `sum:Ag+Zr` and `sum:In+Si` at E=5.0266999999999999. The sum-peak energy is the sum of two tabulated parent line energies, so two different
  pairs can land on exactly the same value.
- O4 (dup <-> fail, all passes): over every pass of each file, "a pass contains two sum groups at the same energy" coincides with "the pass
  fails": 1598/1598 (1121), 242/242 (1140), 700/700 (1253 Ag), 1596/1596 (0944), and 711/711 with zero duplicates (1253 MDW scored copy).
  In each file the duplicate pass is the first failing pass, and the file aborts there.
- O5 (scored copy of 1253): the two MDW copies have identical bytes (sha256 `dfaf4018...`) and both score. The Ag copy has different bytes
  (sha256 `55a69c05...`), a different axis (offset -0.96370, scale 0.01 keV/ch vs MDW offset -1.93221348, scale 0.02), and the sum pair
  `sum:Ag+Zr` / `sum:In+Si`, which never occurs in any MDW pass. No pass in the MDW copy contains any of Cs+Ho, Dy+Ti, Ag+Zr or In+Si.
- O6 (code path): `ElementProposer.swift` 262-275 (`sumColumns`) adds a sum column for every pair from `LineConflicts.sumEnergies`
  whose energy is in the fit window and below the beam, and which is not within `sumPeakToleranceKeV` of a listed or claiming line. It
  never compares a new sum column with the other sum columns, so two pairs with the same energy both get a column. `sumEnergies` returns every
  pair (self-pairs included) without de-duplication.
- O7 (room, by reading only, not seen on screen): `SpectroscopyRoomController.swift` ~line 316-328 catches only `ProposerError.cancelled`;
  any other error becomes `failure = "Auto ID could not fit this spectrum: " + ((error as? LocalizedError)?.errorDescription ?? "\(error)")`.
  ProposerError is not a LocalizedError, so the room shows the case name, probably `rankDeficient`. Not driven, so unverified on screen.

## 6. Prediction against the evidence

- P1 (deterministic, same error 2 on each entry): CONFIRMED (O1; diagnostic re-runs identical).
- P2 (failing pass has n >= k and R_jj ratio <= 1e-10): CONFIRMED (O2: ratios 1.2e-16 to 3.7e-16).
- P3 (Ag copy differs in sha256 and axis or counts; MDW copies identical bytes and both score): CONFIRMED (O5); the axis differs as well.
- R1 (different error case or nondeterminism): not observed.
- R2 (n < k, or dmax = 0, or LAPACK failure): not observed.
- R3 (identical axis and bytes between the failing and scored copy): not observed.
- R4 (no duplicate column, cause in the counts only): not observed; the duplicate is present in every failing pass and in no passing pass (O4).
- My prediction said the cause would be near-collinearity of a line, escape or polynomial column. The collinear column is a SUM-PEAK column, and it
  is collinear with another SUM-PEAK column, not with a line. The prediction's general shape held; its detail was wrong.

## 7. Established mechanism

Established (reproduced, and the discriminating pass-level test agrees in every pass of five files):

1. `ProposerError.rankDeficient` (harness code 2, ElementProposer.swift:218) is thrown when `FitNullVariance.compute` returns nil, which
   happens when `FitLinearAlgebra.pseudoInverse` finds the R diagonal ratio at or below 1e-10.
2. The proposer's design can contain two sum-peak columns at the same energy, because `sumColumns` (ElementProposer.swift ~262-275) only
   tests sum energies against the listed and claiming lines, never against each other, and `LineConflicts.sumEnergies` returns every pair.
3. Two identical columns make the design exactly rank-deficient (cos 1 to 16 digits; R diagonal 2e-16). The pass throws and the whole Auto ID
   for the file fails, with no partial result.
4. Whether a file hits it depends on which parent elements the forward loop detects (counts-dependent), because the collision needs both pairs
   in the same pass. Energies of the pairs come from the line table, so the collision itself does not depend on the axis.

Still unknown (not established):
- U1: why the MDW copy never detects the colliding parents (Cs, Ho, Dy, Ti, Ag, Zr, In, Si in those pairs). The files differ in bytes and in
  axis, and I did not separate counts from axis (a discriminating run would feed the Ag counts with the MDW axis and the reverse).
- U2: how common exact sum-energy collisions are across the element pool and the real spectra. Not counted. The six failing entries are the
  only failures in the 112-file tv.log; the other scored files had no duplicate pass (by reading the logs only; not checked per pass).
- U3: the on-screen message in the room (O7 is by reading only).
- U4: what the WP4b numbers would become if these six entries were scored. They are absent from the set, not counted as zero.
- U5: whether the duplicate is always the same energy within the 1e-16 level or sometimes a near collision (sumPeakToleranceKeV-scale). Not
  tested; the two cases observed are exact.

## 8. Suggestion for a fix registration (not a fix)

Register a new item (ADR 050: a failed reproduction closes an item; this one reproduced, so it is a new item with its own gate). It is a
scientific change, so Gate D applies, and the owner gets the decision as a sheet. Options for the sum-peak columns: (a) merge sum columns at
the same energy into one column whose label names both pairs ("Cs+Ho or Dy+Ti"), since the design cannot tell them apart; (b) keep the first
and drop the others, deterministically, and name the dropped pair in the notes. Separately, `rankDeficient` aborts the whole Auto ID; a guard
that degrades instead of failing is a second option, to be decided on its own. Before the fix, measure how often exact collisions occur over
the element pool (a pre-registered table scan of `LineConflicts.sumEnergies` over pairs of pool elements) and over the owner's files
(per-pass check as in O4). Fixtures: 0944 and 1253 Ag (read-only, owner drive, referenced by path) plus a synthetic spectrum with two parent pairs
at 11.0061 keV. Mutation: with the de-duplication removed, the synthetic test must go red with rankDeficient. The independent refuter should
re-run the per-pass check on the fixed harness and confirm the six entries now score.

## 9. Housekeeping

- No repo file was edited. Diagnostic copies live only under scratchpad/research/diag (not committed, not in the repo).
- No file was written beside the owner's files. The EMD files were opened read-only by the harness.
- Heavy lock: taken for the first build, released; taken for the diagnostic build (x3), released each time. Lock dir absent at the end.
- The harness exits 0 when files fail: a run with failures prints `skipped ...: failed` and still exits 0. This is an aside relevant to
  "never widen a gate that fails silently": the WP4b tables omit these six files without any non-zero exit.
