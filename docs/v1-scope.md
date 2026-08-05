# mac4DSTEM v1 product scope

This file is the release contract for v1. New work should improve one of these
workflows or be deferred unless it fixes data loss, scientific correctness,
security, accessibility, or a release blocker.

## Supported workflow

1. Open a supported 4D-STEM dataset without Python.
2. Inspect dimensions, calibration provenance, and a live diffraction pattern.
3. Establish or verify origin, ellipse, R–Q rotation, reciprocal sampling, and
   real-space sampling without silently inventing physical units.
4. Produce virtual images, DPC/iDPC, Bragg vectors, strain, and orientation maps
   with visible quality diagnostics and cancellable progress. Orientation mapping
   requires an explicit supported material; an uncalibrated Q-scale run remains
   permanently labelled Exploratory through export and session reopen.
5. Save calibrated data and named results into py4DSTEM-readable EMD/HDF5,
   reopen the session, and recover safely from cancellation or a failed write.

The native product maps this workflow to five persistent destinations:
**Prepare → Image / Map / Reconstruct → Results**. Algorithm choices live as
tasks inside those destinations. Navigation never starts a costly analysis;
the prominent task action, menu command, and progress/cancel treatment make
execution explicit. Reconstruct remains visibly Advanced and Results owns the
review/save/export lifecycle rather than hiding it in an inspector.

## Feature tiers

### Stable in v1

- HDF5/EMD and DM3/DM4 reading.
- Bounded virtual imaging/diffraction and diffraction statistics.
- Origin, ellipse, R–Q rotation, Q/R sampling, and known-crystal Q calibration.
- Quantitative DPC/iDPC when prerequisites are complete, with an explicit
  qualitative fallback otherwise.
- Bragg-disk detection and py4DSTEM-compatible BraggVectors export.
- Strain mapping with basis/reference diagnostics and failure rejection.
- ACOM for the explicitly implemented cubic and HCP-magnesium point groups, with CPU
  scientific fallback and an accelerated backend only when parity is demonstrated.
  Other phases are accepted only after their complete model and point-group behavior
  are implemented and validated; v1 does not infer a phase from a file name or image.
- Named result/calibration sidecars, result browsing, and safe reopen/removal.

### Advanced in v1

- Parallax reconstruction, depth sectioning, and single-slice ptychography.
  These remain available and tested, but the UI labels them Advanced because
  method breadth, GPU batching, and cross-instrument real-data validation are
  not release gates for the stable core workflow.
- Fixture-validated direct Merlin MIB and EMPAD import. Their exact v1 binary
  subsets reject ambiguity and are usable, but promotion to Stable requires
  release-owner-supplied vendor files from at least two acquisitions/instruments;
  the repository currently contains no redistributable real MIB/EMPAD corpus.

### Post-v1

- Complete py4DSTEM API parity, every phase-retrieval method, GPU ptychography,
  materials-service integration, plugin architecture, and arbitrary EMD plot
  authoring.
- Real/diffraction-space cropping, and partial or diffraction-binned loading of
  large datasets. Captured with their constraints in
  [`docs/post-v1-ideas.md`](post-v1-ideas.md) — that file is where post-v1
  ideas needing `Core/` changes are parked, since
  `docs/ui-workflow-backlog.md` is contractually UI/workflow-only.
- **Screen-reader (VoiceOver) usability.** Moved out of the v1 "Mac
  experience" gate on **2026-08-05** by the release owner, on the grounds that
  no current or near-term user of this app needs it, so the verification cost
  bought nothing at v1. Recorded rather than deleted because a release contract
  with a gate everyone steps over devalues the other gates — this is a
  deliberate scope change under the rule below, not an untested gate.
  **What was kept, and is not affected:** the accessibility *identifiers* and
  *label associations* that shipped 2026-08-04 and 2026-08-05 stay in the code.
  They are not there for screen readers — they are the surface XCUITest matches
  on, and `mac4DSTEMUITests/Support/AXDriver.swift` depends on them. Removing
  them would break the QC playthrough.
  The verification procedure is written and parked at
  [`docs/voiceover-verification-checklist.md`](voiceover-verification-checklist.md)
  so v2.0 starts from a checklist rather than from scratch.

## Release acceptance gates

- **Correctness:** checked-in synthetic/source-locked goldens plus the v1 real-
  dataset manifest pass within documented tolerances; deviations are explicit.
- **Performance:** representative workloads have recorded time and memory on
  the checkpoint Apple Silicon machine. Core actions show progress, cancel, and
  finish within their recorded acceptance budgets without unbounded residency.
- **Reliability:** malformed/truncated input, cancellation, stale completion,
  failed export, session replacement, and memory rejection never publish a
  partial scientific result or damage the source file.
- **Interoperability:** each stable reader and exported object has an exact
  native fixture plus a direct py4DSTEM/emdfile read where applicable.
- **Mac experience:** multiple datasets remain isolated, native menus and
  `⌘1…⌘5` keyboard navigation reach the outcome-based workflow, state
  restoration is safe, expensive work is explicit, and retained results remain
  correctly identified across navigation.
  **Screen-reader usability was removed from this gate on 2026-08-05** and
  moved to Post-v1 — see below for the decision and what was kept.
- **Distribution:** a clean Release build is self-contained, sandboxed,
  hardened, signed, notarized when credentials are supplied, and verified on a
  clean supported macOS account.

## Scope-change rule

A new v1 feature must replace an existing item or demonstrate that it closes a
release gate. Performance changes retain the exact CPU implementation as the
reference/fallback until numeric and failure parity are proven.
