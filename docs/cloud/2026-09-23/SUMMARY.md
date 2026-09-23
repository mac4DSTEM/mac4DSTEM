# Cloud session 2026-09-23: summary

**Brief tasks T1–T6: not started.** The brief `docs/cloud/2026-09-23-brief.md` exists on no ref. The environment also denies `zenodo.org` and `doi.org` (proxy CONNECT 403), and the brief allows data from Zenodo 6645396 only. Evidence is in `PROGRESS.md`. The owner could not fix either from where they were and asked for "anything else you can do". What follows is that follow-up, done under the brief's limits:
- read-only against the app;
- writes only here and in `tools/cloud-analysis/`;
- no data and no Swift toolchain.

Every Swift-behaviour statement below is **read-verified, not executed**.

## What was produced

| File | What it is | Headline |
|---|---|---|
| `defect-triage.md` + `.json` | Proposed triage of the 2026-09-09 register's 121 open claims (owed per `open-items.md`) | 83 CONFIRMED, 23 PARTLY, 6 FIXED, 5 GONE, 3 REFUTED, 1 CANNOT_TELL. **Priority 1:** D021, D031, D070, D101 (details below). |
| `rq-sign-convention.md` | Decision memo for owner decision 2 (R–Q sign) | App consumers are self-consistent in the app frame. The wrong numbers are at the py4DSTEM boundary, about 2θ each way. Recommends **B**: keep the app sign and convert `QR_rotation` at import and export, bumping the sidecar schema 6 → 7 (owner's call). |
| `al-lattice-constant.md` | Decision memo for owner decision 3 (Al a = 4.0495 vs 4.04 Å) | Confirms the refuter's `kMax` knife-edge explanation. No user-facing default depends on 4.0495. Leans towards keeping 4.0495, with a draft `DEVIATION` note. |
| `precipitate-objects-crosscheck.md` + `tools/cloud-analysis/precipitate_objects_ref.py` | Python reference of `classObjects`/density/bridge, checked against the Swift tests' expected values | 24/24 selftest, every mutant as expected, 200 random maps agree with scipy. Main finding on `lengthPx` below. All six open-items segmentation defects are still present. |

The four priority-1 claims in the triage:
- **D021:** the parallax stack mean saturates in Float32. The lead session reproduced it in numpy: 0.579 instead of 1.000 at 58 M elements. **Gate D.**
- **D031:** a sidecar save can silently strip saved results when the existing file fails to open.
- **D070:** the DPC colour wheel traps (crashes) on a single non-finite centre-of-mass value.
- **D101:** the R–Q sign issue, already open.

The `lengthPx` finding: length is measured centre to centre + 1 (`PrecipitateSegmentation.swift:430-431`), not the documented end-to-end extent. The two agree only for axis-aligned objects; the 45° test pins 6.66 px where the pixel squares span 7.07 px. It is a definition question with a number at stake, so it is for the owner.

## Checks by the lead session (not the agent that wrote each piece)

- **Al:** \|g220\| arithmetic re-run. Results: 0.69846 / 0.70011 Å⁻¹, edge at a = 4.04061 Å.
- **R–Q:** `AppState+Open.swift:468` assigns `QR_rotation` unconverted while the origins beside it are swapped.
- **Precipitate:** `precipitate_objects_ref.py all` re-run, exit 0. The `lengthPx` lines were read.
- **Triage:** D021 reproduced numerically; D031 and D070 confirmed by reading. The other 117 verdicts are one verifier's reading each, and should be treated as leads.

## Owner actions

1. **Before merging:** add `cloud-analysis` to `diagnostic=(…)` in `tools/run-tests.sh`. Otherwise `inventory` reports it `UNCLASSIFIED`; that file was off-limits here.
2. Decide on R–Q (memo recommends B), Al (memo leans towards keeping 4.0495), and the `lengthPx` definition.
3. Take the triage order, or amend it: D021, D070 and D031 first, as separate sessions.
4. **For T1–T6:** commit the brief, allow `zenodo.org`, and start a new session. Swift probes need a Mac.

No scientific number in the repo moved. No app code, tests, CI or live docs changed, and no data was committed.
