# mac4DSTEM roadmap

Rewritten 2026-10-21 after the kit switches. The app owns SwiftUI, app logic, provenance and the study workflow, built on five
released kits (exact pins in `Package.swift`). What is live: `docs/status.md`. Every defect and debt: `docs/open-items.md`
(this file points to it, it does not repeat it). Cross-repo direction: `../ROADMAP.md`.

## What the app owns, and what the kits own

| Owner | Holds |
|---|---|
| **App** (`mac4DSTEM/`) | rooms and SwiftUI, `AppState`, Metal image view and Metal engines (virtual detector, ACOM backend `MetalACOMMatcher`), lineage/replay/marks, session sidecar writes, calibration orchestration, precipitates, Materials Project fetch glue, 4D x spectroscopy correlation |
| **CuboKit 0.6.0** | virtual imaging, CoM and origins (`OriginFit`, Friedel, beamstop), probe size, disk detection (`CuboBragg`), strain (`CuboStrain`), DPC/iDPC (`CuboPhase`), parallax aberration/depth/position correction, ptychography probe, PCA/k-means, hot-pixel mask, calibration re-reference |
| **DiffractoKit 0.7.1** | cells, CIF, symmetry, structure factors, ring and ellipse fit, vector matching and phase mapping, Euler/orientation symmetry, ACOM library and matcher, Materials Project decode |
| **FormatoKit 0.7.0** | HDF5 reader and libhdf5 frameworks, sidecar reads and the peak-grid EMD read, DM4/DM3 (not the 4D gather), MIB, EMPAD, Velox EMD |
| **SpectroKit 0.7.1** | EDX fit, quantification, proposer and Auto ID, spectrum image, mask transport and pools |
| **ImagoKit 0.4.0** | `FFT2D`, `FFT1D` (ACOM) |

Kept in the app on purpose, each marked `delete at <Kit> <version>`: `SingleslicePtychography`, `ParallaxAlignment` with
`MatrixDFTCorrelation`, `H5Reader`'s `HDF5LegacyProbe`, `DM4Reader`, the sidecar writer, header-less MIB. The kit asks that end
them are in `docs/open-items.md` "Kit asks"; the owner tags kit releases and the app re-pins once per kit minor.

## Study items mac4DSTEM must deliver (`../ROADMAP.md`)

The acceptance target is the owner's correlative TEM study (unpublished: keep its text and data out of this public repo).
1. **Number density N_V with thickness** on the owner's microprobe Al-Mg-Si cube; thickness typed +- sigma until SpectroKit EELS t/lambda.
2. **Talk-quality figures:** apertures drawn on the exported mean pattern, the EDX region box in exported maps, multi-panel layout,
   high-DPI or vector output.
3. **beta'' (monoclinic) orientation maps:** the symmetry is DiffractoKit's; the app needs the map, IPF and export path; then re-measure the needles.
4. **Validation of what the talk shows:** phase and orientation mapping against pyxem, a beta'' truth set, the Euler frame rotation versus py4DSTEM.
5. Smaller: numeric aperture entry or snap to a reflection; the mean pattern without Prepare first; drift-corrected EDX sums (SpectroKit/FormatoKit).

## Open app work, in order (details: `docs/open-items.md` "App work")

1. Notarisation (archive verified 2026-10-20) and the Hardened Runtime load (the release proof for the framework signing).
2. Number density v2: a new registration (study item 1).
3. Phase mapping object bar and the matrix verdict (with the DiffractoKit ask); stays badged unvalidated.
4. Known-crystal Q ring assignment (design pass); origin-fit gate and seed holes; rotation-calibration tests.
5. Lineage, replay and sidecar identity residuals; room-switch defects; the Compute Strain crash hunt.
6. Spectroscopy room drive and the HDF5/DM4 robustness items.
7. Test-run traps, harness gaps, D12 tolerance conversion; then accessibility, Swift 6 (owner's schedule) and the parked refactors.

## Features frozen until reopened

The v4.1 plateau holds: sessions finish or remove, they do not add, apart from the study items above. Parked: amorphous and
nanocrystalline modes, strain where disk detection fails, grain segmentation, detector realism, direct ptychography, live acquisition.
