# v2 review recovery — 2026-08-31

All **75 initial entries across 11 areas** have an independent disposition. All **15 available session records** were audited over **208 explicit/grouped claims**. This accounts for the requested review; it does not prove absence of other bugs or fix the reported defects.

**39 confirmed, 34 narrowed, one refuted, one already resolved.** Confirmed means supported by source inspection unless the individual evidence explicitly records an experiment. Duplicates are retained for traceability; this is not a count of distinct bugs. Of the claims audited, **46 remain historically unverified**, chiefly because contemporaneous execution evidence was not retrieved.

Baseline: `main` at `24c13d3`, including the ten pre-existing uncommitted files. The audit concerns that app source state. The recovery added an ACOM fixture and documentation; no app source changed.

## Read this first

- [Session record and current validation state](../v2-session-records/review-recovery.md).
- [Every original finding and corrected disposition](findings.json); [session claim audit](session-audit.json).
- [Independent ACOM Gate B](acom-gate-b.md): control plus five new mutations; [author controls](test-evidence/author-mutations/results.json) add six. The gate covers CPU projection and returned matrices, not universal ACOM accuracy.
- [Recovery-checker review](process-review.md): all 75 IDs preserved, and malformed/missing results must fail. Run `python3 tools/review-record-check/run.py` from the repo root.
- [v3 process proposal](../../v3-development-process.md). Current v2 safeguards remain binding.

## Recommended v2 triage, not an automatic scope expansion

1. Diagnose silent scientific misrepresentation and unsafe file handling first: sidecar string reads (`core-data-01`), incomplete CIF symmetry expansion (`core-crystal-02`), stale result metadata (`app-appstate-01`, duplicate `support-export-01`), cached ACOM plans after voltage changes (`app-appstate-02`), DPC angle units (`core-analysis-physics-01`). These need controlled reproductions before app fixes.
2. Review frame/provenance and overlay findings next, including parallax transpose, hexagonal IPF labels, ACOM/export presentation and gamma. Scientific labels belong with correctness, not a cosmetic sweep.
3. Keep the owner-requested S22 playthrough/UX session, with its recovered [18 survey leads](survey.json). These are code-review leads, not 18 owner-observed defects. Comparison scales, trust labels and destructive result deletion deserve explicit observation.
4. Preserve TB1/TB2 contract checks. Free exploration can precede them in the same sitting; it does not prove unattended replay, foreign-sidecar handling or clean-account behavior.
5. Keep S20 (version/sign/notarize/clean-account/final acceptance) gated. Do not treat this completed review as release approval. The owner still chooses v2 versus v2.x for unscheduled repair work; the ACOM coverage work itself was explicitly requested for v2.

## Findings index

Full rationale, caller checks, corrections and remaining experiments are in `findings.json`. Original reports are preserved under `initial/`; their confidence labels are not the recovery verdict.

| ID | Disposition | Severity | Finding |
|---|---|---|---|
| app-appstate-01 | confirmed | high | restoredResultPixelInfo is never cleared, so a freshly computed product exports with the restored session map's pixel size, units and provenance |
| app-appstate-02 | confirmed | high | Changing the accelerating voltage does not invalidate the cached orientation plan, so ACOM re-runs against a flat-Ewald template library and reports in-plane angle only modulo 180° |
| app-appstate-03 | narrowed | medium | Cancel during an open's first whole-cube pass stops nothing and its own message is immediately overwritten by advancing progress |
| app-appstate-04 | confirmed | medium | The cached CoM field is not invalidated when the origin it was measured against changes, so a later DPC display switch renders it under the new origin's provenance |
| app-appstate-05 | confirmed | medium | The strain and ACOM fit-verification overlays are anchored on a fifth hand-rolled origin fallback, so they are drawn at a different point than the analysis they verify |
| app-rest-01 | confirmed | medium | iDPC remedy regression assertion does not match the production remedy |
| app-rest-02 | narrowed | low | Reciprocal-metrology fallback is dead today and would return nil if reached |
| app-rest-03 | narrowed | medium | Recovery-position writes do not verify the dataset identity |
| app-rest-04 | confirmed | low | LoadedView display-surface comment is stale |
| app-rest-05 | narrowed | low | Malformed recents blobs decode to an empty list without reporting the loss |
| app-rest-06 | narrowed | low | Stale bookmark refresh is attempted before the open activates security scope |
| core-analysis-detect-01 | narrowed | medium | The revert of the S13 robust-residual gate left three prose claims saying the gate still reads `robustResidual` — one of them unambiguous |
| core-analysis-detect-02 | narrowed | low | `KnownCrystalQCalibration.estimate` takes `probeRadiusPixels` and never reads it, while its doc promises a check that runs on it |
| core-analysis-detect-03 | confirmed | low | `probeSize` uses `sorted[n/2]` where py4DSTEM uses `np.median`, an unmarked deviation in a file whose header promises every deviation is marked |
| core-analysis-detect-04 | narrowed | medium | Seven ellipse-fit refusal thresholds carry no derivation and no DEVIATION note, on a path py4DSTEM does not gate at all |
| core-analysis-physics-01 | confirmed | high | DPC angle stores turns while claiming radians |
| core-analysis-physics-02 | narrowed | high | Parallax fitting discards the calibrated transpose; stored rotation is also unused |
| core-analysis-physics-03 | narrowed | high | Ptychography uses one global aperture origin and ignores fitted per-position origins |
| core-analysis-physics-04 | narrowed | medium | Non-iDPC DPC exports omit frame, origin and physical-scale derivation |
| core-analysis-physics-05 | narrowed | medium | Parallax correction/depth result provenance omits the aberration fit |
| core-analysis-physics-06 | confirmed | medium | Higher-order parallax basis uses BF-centroid coordinates while py4DSTEM samples array-center coordinates |
| core-analysis-physics-07 | confirmed | low | Strain residual uses weighted RMS while py4DSTEM reports weighted mean distance |
| core-compute-shaders-01 | confirmed | medium | Matrix DFT upsampling wraps one Fourier frequency incorrectly on each odd axis |
| core-compute-shaders-02 | confirmed | medium | DPC and origin CoM clamp negative intensities without documenting the py4DSTEM deviation |
| core-compute-shaders-03 | confirmed | low | Origin refinement includes exact-radius pixels excluded by the py4DSTEM window |
| core-compute-shaders-04 | narrowed | low | Zero-sum DPC patterns are represented as valid zero shift without a validity channel |
| core-crystal-01 | confirmed | high | Hexagonal IPF legend and documented indices disagree with the production colour mapping |
| core-crystal-02 | confirmed | high | CIF without symmetry operations can accept an asymmetric unit as the complete cell despite a non-P1 space-group declaration |
| core-crystal-03 | narrowed | medium | ACOM lacks a user/export disclosure of the flat-Ewald in-plane ambiguity when voltage is absent |
| core-crystal-04 | confirmed | medium | CIF parser silently truncates an incomplete trailing loop row |
| core-crystal-05 | confirmed | medium | ACOM radial-kernel comments claim py4DSTEM semantics the simplified native polar builder does not implement |
| core-crystal-06 | narrowed | medium | Hexagonal IPF fixture does not independently pin the crystallographic labels shown by the legend |
| core-crystal-07 | confirmed | low | ACOM comments still describe only cubic crystals after hexagonal support landed |
| core-data-01 | confirmed | high | Sidecar HDF5 string reads assume scalar variable-length storage without checking the file type or extent |
| core-data-02 | confirmed | high | Scalar session restoration lacks a scan-domain shape check |
| core-data-03 | narrowed | high | Successful view changes can preserve old result nodes while restamping the root view and minimum-reader metadata |
| core-data-04 | narrowed | low | CalibrationReReference reconstruction drops trim metadata, but the claimed live crop scenario is not established |
| core-data-05 | confirmed | medium | Inspector uses retired 0.5% outlier disclosure threshold instead of the shared 2% policy |
| core-data-06 | confirmed | medium | Malformed DM4 counts can trap before their validation guards |
| core-data-07 | narrowed | medium | DM4 scan-shape and voltage selection is global and dictionary-order dependent |
| core-data-08 | narrowed | low | Sidecar calibration serialization silently omits inconsistent origin arrays; no reachable production failure established |
| core-data-09 | confirmed | low | Log diffraction display converts nonfinite pixels into valid zero-valued data |
| support-export-01 | confirmed | high | Restored result sampling/provenance survives new publications and dataset changes |
| support-export-02 | narrowed | high | Exported scalar colorbar ignores the gamma used by image pixels |
| support-export-03 | narrowed | high | ACOM region selection mixes retained-result pixels with navigation caption and range during export |
| support-export-04 | narrowed | high | CBED export invents reciprocal units for a size with missing units and has no provenance record |
| support-export-05 | confirmed | medium | Unknown-unit result sampling is used numerically but labeled pixels |
| support-export-06 | narrowed | medium | Rotated anisotropic result caption prints unqualified original-column sampling |
| support-export-07 | confirmed | medium | Publication strain figure omits a legend for its masked-pixel gray |
| support-export-08 | narrowed | medium | Bragg CSV contains raw detector positions without calibration/frame provenance |
| tests-01 | confirmed | medium | Strain vector/tensor equivalence test permits zero comparable positions |
| tests-02 | confirmed | medium | Stale-strain-remedy test checks initialization twice and never tests clearing |
| tests-03 | narrowed | low | Eight sidebar measurement cases run in the unit gate but assert no behaviour |
| tests-04 | narrowed | low | Demo orientation test is an operational smoke check, not an orientation-accuracy oracle |
| tests-05 | confirmed | low | Binned-origin unit test checks a literal convention, not the export writer |
| tests-06 | refuted | none | Template-derived fixture is appropriate for this explicitly scoped radial-deposition test |
| tests-07 | narrowed | low | Voltage-placement test relies on an unpinned text-field-count assumption |
| tests-08 | narrowed | low | Preview-budget test permits twice its named limit and tests only square scans |
| tools-gates-01 | narrowed | medium | Parity metric round-trip assertion compares a value to itself |
| tools-gates-02 | confirmed | medium | Load-spec applied round-trip can silently skip when both constructions fail |
| tools-gates-03 | narrowed | medium | Disk-correlation README overstates its parallel-path coverage |
| tools-gates-04 | narrowed | medium | Center-of-mass kernel lacks an independent expected-value check in located gated exercises |
| tools-gates-05 | narrowed | medium | Rotation solver and ptychography preparation lack direct located gated tests |
| tools-gates-06 | resolved | none | README aggregate roster count was corrected before recovery |
| tools-gates-07 | confirmed | low | Source-manifest adoption comment lists two users where six now exist |
| tools-gates-08 | confirmed | low | CI exclusion documentation omits three diagnostic helpers |
| ui-01 | narrowed | high | Hexagonal IPF corner direction labels are swapped relative to the crystal Cartesian basis |
| ui-02 | confirmed | high | CBED on-screen bar invents 1/nm when size exists without units |
| ui-03 | narrowed | medium | Square virtual-detector outline is offset half a pixel from its half-open mask |
| ui-04 | confirmed | medium | Circular scan ROI is offset from its visible selected-position center |
| ui-05 | confirmed | medium | Real-space view labels unknown-unit numeric sampling as pixel distance |
| ui-06 | confirmed | medium | Comparison hover samples full-pane coordinates without inverse letterbox or zoom |
| ui-07 | confirmed | low | Performance inspector retains the ambiguous GPU budget label |
| ui-08 | confirmed | low | Aperture handle can round the far-edge center to an out-of-bounds point |
| ui-09 | confirmed | low | Filename scan-step parser matches ss embedded in ordinary words |

## Session audit index

Historical counts are evaluated at their stated revisions. Later code or a later green run cannot prove a past execution. Missing records are not fabricated: S9a/S9b/S11/S19 have inline release-plan evidence, S12 has its design document, S14/S15 are W4a, and S20 has not happened.

| Record | Claims examined | Dispositions |
|---|---:|---|
| S1 | 20 | 10 confirmed, 2 known, 1 narrowed, 7 unverified |
| S2 | 12 | 9 confirmed, 3 unverified |
| S3 | 17 | 11 confirmed, 2 known, 4 unverified |
| S4 | 26 | 14 confirmed, 1 contradicted, 3 known, 8 unverified |
| S5 | 29 | 18 confirmed, 3 known, 2 narrowed, 1 resolved, 5 unverified |
| S6 | 13 | 9 confirmed, 4 unverified |
| S7 | 11 | 6 confirmed, 1 contradicted, 2 narrowed, 2 unverified |
| S8 | 13 | 7 confirmed, 1 known, 2 narrowed, 3 unverified |
| S10 | 14 | 8 confirmed, 2 contradicted, 1 known, 2 narrowed, 1 unverified |
| S13 | 23 | 7 confirmed, 4 contradicted, 1 known, 5 narrowed, 1 resolved, 5 unverified |
| S17 | 5 | 3 confirmed, 1 narrowed, 1 unverified |
| S18 | 7 | 2 confirmed, 2 known, 3 narrowed |
| S21 | 5 | 2 confirmed, 1 known, 2 narrowed |
| W4a | 6 | 2 confirmed, 2 narrowed, 2 unverified |
| W4b | 7 | 3 confirmed, 2 narrowed, 1 refuted, 1 unverified |

## Limits

No app bug was fixed by this review. Source inspection does not reproduce crashes, demonstrate whole-suite mutation survival or score UI acceptance. Review coverage is the eleven stated areas, not a security certification of vendored libraries. The external living v2 board was not updated: its publishing tool is unavailable here.
