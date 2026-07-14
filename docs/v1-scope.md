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
   with visible quality diagnostics and cancellable progress.
5. Save calibrated data and named results into py4DSTEM-readable EMD/HDF5,
   reopen the session, and recover safely from cancellation or a failed write.

## Feature tiers

### Stable in v1

- HDF5/EMD and DM3/DM4 reading.
- Bounded virtual imaging/diffraction and diffraction statistics.
- Origin, ellipse, R–Q rotation, Q/R sampling, and known-crystal Q calibration.
- Quantitative DPC/iDPC when prerequisites are complete, with an explicit
  qualitative fallback otherwise.
- Bragg-disk detection and py4DSTEM-compatible BraggVectors export.
- Strain mapping with basis/reference diagnostics and failure rejection.
- ACOM for point groups implemented and validated by v1, with CPU scientific
  fallback and an accelerated backend only when parity is demonstrated.
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
  keyboard navigation reach the workflow, state restoration is safe, and the
  primary workflow is usable with VoiceOver and increased text size.
- **Distribution:** a clean Release build is self-contained, sandboxed,
  hardened, signed, notarized when credentials are supplied, and verified on a
  clean supported macOS account.

## Scope-change rule

A new v1 feature must replace an existing item or demonstrate that it closes a
release gate. Performance changes retain the exact CPU implementation as the
reference/fallback until numeric and failure parity are proven.
