# v5.0 WP2 — the Spectroscopy room and a simulated 4D-STEM + EDX dataset — pre-registration (2026-10-05)

Decided by ADR 055 (build now), 054 (quantification and layout) and 053 (data model M2, spectrum-only window). Mock v3
is the picture: `docs/archive/v5/spectroscopy-mock-2026-10-05/`. WP1's readers come first: lane B landed (`f93bcae3`),
and lane A (Velox) lands after its review fixes. This file is written before any WP2 code.

## Four lanes, run in parallel

Each lane has its own write-set and its own isolated copy, and is gated alone before it lands. Every lane follows the
rules in the session's `LANE-RULES.md`: tests first, each broken once, predictions written into the report before runs.

| Lane | Writes | Builds | Gate |
|---|---|---|---|
| **S — simulator** | `tools/demo-edx/` (new), output in `References/demo-edx/` (gitignored); a < 1 MiB fixture under `mac4DSTEMTests/Fixtures/` if a test needs one | The demo cube's recipes (`tools/demo-dataset/`) with an EDX forward model per recipe and a known per-phase composition. Written as (a) a GMS-style multi-object `.dm4` following `../4d-edx-file-structure-2026-10-05.md` §4a, with every guess listed in the file's own tags and in `truth_edx.json`, and (b) a HyperSpy-style `.hspy` pair (§4b). | rsciio reads both back. `DM4Experiment` lists the `.dm4` with the right roles, rect and Experiment ID. `DM4Reader` opens its Diffraction SI as today. The truth totals equal the written counts. |
| **C — Core spectral basics** | `mac4DSTEM/Core/Spectroscopy/` (new folder) + its tests | The X-ray line table and the FWHM law ported from eXSpy `7185a4d1` (line energies verbatim; DEVIATION notes where needed). A `SpectrumImage` protocol over the Velox sparse store and a dense DM4 EDS SI. A summed spectrum over a mask. eXSpy's background windows and window net counts. Per-pixel net-count maps from the sparse store. | **Parity pins** (`../edx-research-2026-10-05/reports/validation.md` §1b): FWHM Al Kα 0.07661266 at 130 eV; the FePt windows 3710/15872 and 2754/15090; TM002 [84163, 89063, 96117, 96700, 99075]. Gate B, because it produces numbers. |
| **V — room views** | `mac4DSTEM/UI/Spectroscopy/` (new folder) | SwiftUI only (no AppKit), against a small view-model protocol with preview fixtures: the spectrum plot (Canvas; log axis; line markers incl. suspect markers; Spectrum/Background/Model/Residual/Overlay; residual strip; wheel zoom, drag pan, Home), the periodic table (four states, right-click Quantify · Fit only · Off · Lines), the element tile strip, the ColorMix map, the results table (k-free ratio, at% badged "unvalidated", σ terms expandable), and the five steps' inspector content (≤ 7 rows; Expert disclosure). | Unit tests of the view models (state toggles, the "Auto ID never drops manual picks" rule, the narrow-layout switch at 760 pt). It is driven once wired (lane R2). |
| **R — shell and session** | `mac4DSTEM/App/` room wiring, the frozen-shell files (ADR 035, against the accepted mock), `mac4DSTEM/Session/` (new `SpectroscopySession` owner), `docs/architecture.md` | A seventh `WorkspaceArea` `.spectroscopy` (⌘6, Results ⌘7) with its five sidebar steps and Regions list. A **spectrum-only window**: a document with an EDX spectrum image and no 4D cube, splitting today's `hasDataset == is4D` assumption. The session owner holding the spectrum image, element states, regions and the quantification method. Placeholder content where lanes C and V land later. | The unit suite, `core` and `inventory`, and existing navigation tests updated for seven rooms. No change to any 4D behaviour. |

**After these four:**

- **R2** wires V's views and C's numbers into the room.
- The Velox routing goes in: `H5Reader` stops offering a Velox file as a one-row cube, and Velox `.emd` opens in
  Spectroscopy. That is shipped behaviour, so it goes through Gate B.
- A session drives the room on a scratch build: the owner's `References/EDX` file plus the simulated `.dm4`.

## Predictions (written before any run)

| | Prediction | Refuted if |
|---|---|---|
| **S1** | The simulated `.dm4` round-trips: rsciio's DM reader returns the 4D and the EDS arrays equal to what was written. `DM4Experiment` lists thumbnail, survey, scan HAADF, Diffraction SI and EDS SI under one Experiment ID, with the rect's aspect equal to the scan's. | Any array differs, or a role is wrong. |
| **S2** | The summed EDS spectrum of each phase recipe recovers the truth composition's line ratios within counting error (exact Poisson, 95 %) using window net counts. | That fails. The forward model and the measurement disagree, and the truth is not usable. |
| **C1** | Every listed eXSpy pin matches exactly (integers) or to float32 (FWHM). | Any pin differs. |
| **C2** | Window net counts from the Velox sparse store equal those from the same data densified, bit for bit. | Any difference. |
| **R1** | Adding the seventh room changes no existing test's outcome except the navigation tests that count rooms. Those are updated in the same change. | Anything else changes. |

## Not in WP2

Fitting (LS / ML), k-factors, absorption, live-time normalisation, the registration record, pooling by phase or object.
Those are WP3, built on these pieces against ADR 054.
