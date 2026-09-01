# Independent continuation: data, crystal and compute/shaders

2026-08-31. Scope: all **20** original entries in `core-data.json` (9), `core-crystal.json` (7), and `core-compute-shaders.json` (4), plus all concrete claims in the short S1–S5 session records.

## Method and limit

Read AGENTS.md, development-process.md and the adversarial-review skill. Tried to refute each finding through the actual callers, guards, source-locked py4DSTEM reference and existing debt records. Reviewed relevant landing commits, not only today's tree, when auditing dated claims. No app fixes, shared-tree mutations, compilation, scientific/unit tests, GUI actions, sidecar writes or commits were performed. The only computation was a small independent Python arithmetic check of Fourier-bin wrapping, Miller–Bravais direction conversion, negative-intensity centroids and strict/inclusive mask boundaries. Its output is `data-crystal-math-experiments.json`; it is **not production runtime reproduction**.

`verified-data-crystal.json` retains every original title with explicit outcome, adjusted severity, source evidence, remaining verification and duplicate relationships. **13 confirmed by source; 7 narrowed; none silently discarded.** Confirmed means the source mechanism survived this review, not that the failure was observed in the app or that a proposed fix is approved.

## Findings that survived most strongly

- Sidecar attribute and dataset string readers pass the file datatype to HDF5 with only a pointer-sized destination. Fixed strings and unchecked extents make this unsafe; run isolated subprocess/ASan cases before any fix.
- Scalar result restore lacks the RGBA shape refusal. Successful promote can also preserve old product nodes while restamping the root as full extent. S7's guard addresses failed crop restore, not this successful-view-change trigger. Some per-product provenance survives; the original claim that all provenance is erased was too broad.
- DM4 numeric conversion can trap before bounds guards. The existing overflow fixture accurately tests multiplication overflow, not arbitrary UInt64-to-Int corruption; it should not be accused of having claimed universal corruption coverage.
- Hexagonal IPF labels disagree with the colour function in the lattice frame. Explicit [11-20] conversion reduces to the green 0° direction; [10-10] is the blue 30° direction. The current legend says the reverse. This is an index/colour contract defect, not proof that one external palette is mandatory.
- A complete cubic CIF with a non-P1 declaration and asymmetric-unit-only sites can be admitted as if those sites comprise the full cell. Reduced original severity from critical to high because no runtime/user incidence was measured.
- Odd-axis matrix DFT refinement assigns the central positive frequency to a negative one. At n=7, production's formula gives -4 where the reference gives +3; even n=8 is unchanged. Fractional-pixel phase differs. Quantitative impact on actual reconstructed maps still needs a fixture.

## Material narrowing

- `CalibrationReReference` drops trim metadata at helper level, but its current production call first resets calibration and imports source maps that already have no trim history. The advertised live 'fit, crop, lose disclosure through this helper' scenario was not established. A scan crop also cannot preserve the original scalar exclusion fraction faithfully without mask/history semantics.
- Missing voltage creates a mathematical ACOM ambiguity and lacks a model/disclosure field, but it does not establish random 180° errors at half the pixels. Symmetry equivalence and deterministic tie-breaking matter.
- Global DM4 tag selection is real; competing X/Y combinations often fail the byte-count guard. A realistic file showing a wrong-but-compatible reshape still needs reproduction.
- Silent omission of internally inconsistent origin arrays is real defensive behaviour; a normal app path reaching that state was not demonstrated.
- Swapping both implementation colours and expected test colours is not a valid mutation control. The legitimate IPF fixture gap is the absence of an independent crystallographic-label assertion.
- Zero-sum DPC becomes a valid zero vector, but the initial claims about the direction of rotation bias and a flat iDPC patch are not established.

## S1–S5 audit

`audit-s1-s5.json` contains **104 explicit claim rows** across all five assigned records. Implementation claims are checked against source/history; dated run, mutation and screen results whose primary outputs were not recovered are marked **unverified**, never disproven because today's counts differ.

One direct bookkeeping contradiction: **S4 added 28 test methods across four new files, not 22.** `git show 34fc329` gives 5 image-version + 13 pending-load + 4 recognition + 6 relocation tests. The record's 232→260 suite totals agree with 28. S3's nine net-new tests is correct: the apparent tenth added method is a rename of a preexisting residency test. S1's initial 13 is correct; the follow-up label test brought it to 14.

S5's **36 tests** is ambiguous, not disproven: its commit adds 22 methods, and 22 plus 14 existing locator tests equals 36. Recover the invocation before labeling that a new-test count.

A substantive historical rationale also needs narrowing: the S5/current DPC comment says the computation takes no aperture at all, but landing commit `0af2e66` uses `calibration.meanOrigin ?? (aperture.centerX, aperture.centerY)`. The current reader still uses aperture centre as a fallback. Radius and shape do not affect this CoM computation; centre can. The transient original recorder is not committed, so the audit cannot establish exactly which removed fields were unused or approve the blanket rationale.

The S1 claim that no automated test could catch the missing grant-persistence call is similarly too absolute: automation may catch wiring omission, although an unsandboxed test cannot prove real grant/panel/reopen semantics.

Historical visual acceptances and explicit unverified limits remain intact. The session records do not gain new test/run/visual claims from this audit.
