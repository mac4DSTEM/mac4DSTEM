# Thronsen et al. 2024 — notes for mac4DSTEM (read 2026-09-28)

E. Thronsen, T. Bergh, T.I. Thorsen, E.F. Christiansen, J. Frafjord, P. Crout, A.T.J. van Helvoort, P.A. Midgley,
R. Holmestad, "Scanning precession electron diffraction data analysis approaches for phase mapping of precipitates in
aluminium alloys", *Ultramicroscopy* 255 (2024) 113861, doi:10.1016/j.ultramic.2023.113861, open access CC BY 4.0.
Data: Zenodo 10.5281/zenodo.6645396. Code: github.com/elisathr/SPED-phase-mapping (use permitted, ADR 042). A local copy
of the PDF is in the gitignored `References/papers/thronsen-2024-ultramicroscopy-255-113861.pdf` (sha256 `dcb202c3…`;
3.1 MB, over the repo's 1 MiB file guard). Notes are paraphrase; nothing is quoted at length.

## What the paper does

- **Sample and phases.** Al-Cu-Li (Cu 3.00, Li 1.50, Mn 0.55, Fe 0.20 wt.%), solution treated, aged 24 h at 250 °C.
  Phases: Al (Fm-3m, a = 4.04 Å), T1 Al₂CuLi (P6/mmm, a = 4.95, c = 14.15 Å, cell compressed to match Al), θ′ Al₂Cu
  (I-4m2, a = 4.04, c = 5.80 Å). Viewed along ⟨001⟩Al: T1 along ⟨0-41⟩ with two in-plane variants; θ′ face-on (θ′[001],
  one variant) and edge-on (θ′⟨100⟩, two perpendicular variants). Six unique patterns in total.
- **Acquisition.** JEOL 2100F at 200 kV, NBD mode, NanoMEGAS P1000, Merlin 256² detector, precession 1.04°, 100 Hz,
  10 ms per pattern. Dataset A 512 × 512; dataset B the same except a 2.3 nm step.
- **Pre-processing (all methods).** Centre on the direct beam (COM), calibrate from the mean pattern's Al {400}, bin to
  128 × 128, normalise each pattern to its maximum. Template matching and the ANN also take log(I + a) − log(a).
- **Ground truth.** Assigned by hand from virtual dark-field images by several authors; classes Al, T1, θ′[001], θ′⟨100⟩,
  not indexed. Overlaps prioritised θ′⟨100⟩ > T1 > θ′[001]. Accuracy = share of pixels equal to the truth.
- **Vector matching** (closest to the app's matcher, ADR 044). LoG blob finding, COM refinement, Al vectors removed
  using one pure-Al pattern, < 2 vectors left → Al. Kinematic references (diffsims) in slabs of 0.030 Å⁻¹ (T1) and
  0.300 Å⁻¹ (θ′), rotated to the Al in-plane angle. Score Σ|u − v| / N_unique over a per-pattern reference subset;
  lowest score wins, > 0.07 → not indexed. No overlap handling and no priority scheme.
- **Template matching.** Difference-of-Gaussians background, Al reflections masked, log transform (a = 0.001) minus
  0.05, pyxem polar cross-correlation over 202 orientations within 3° of the zone axes, 1° in-plane step; max excitation
  error tuned per phase (0.03 / 0.05 / 0.022 Å⁻¹ for θ′⟨100⟩, θ′[001], T1); Al regions from a thresholded correlation map.
- **NMF.** Direct beam, high angles and Al reflections masked; hyperspy NMF with NNDSVD initialisation; n by SVD and
  trial; components labelled by hand; iterated, excluding identified pixels, until all phases are found.
- **ANN.** TensorFlow, one hidden layer, trained on 10 000 kinematic simulations per phase with augmentation (spot
  size, Al : precipitate weighting, Poisson and Gaussian noise, radial background, random log transform); experimental
  patterns log-transformed (a = 0.024), beam masked, rotated to the reference in-plane angle.

## Results that matter to us

- **Table 3 accuracy (dataset A):** NMF 98.50 %, vector matching 98.46 %, template matching 98.25 %, ANN 99.04 %. These
  are the full-resolution errors we compute from the Zenodo maps (1.50 / 1.54 / 1.75 / 0.96 %); at the stride-3 grid
  they are 1.56 / 1.51 / 1.70 / 0.95 %. The app is at 1.31 % there (T4 run).
- **Where errors sit:** most mislabelled pixels of every method are at precipitate edges, and the authors state that
  the hand-made truth itself is uncertain at interfaces. Template matching adds single-pixel speckle in Al, which they
  say post-processing (removing single pixels) can clean. Vector matching fails most at θ′⟨100⟩ interfaces and overlaps,
  which the authors attribute to strain shifting Bragg peaks rather than to too few vectors.
- **Their own advice:** vector matching needs little pre-processing but a precise peak finder; the ANN is fastest
  once trained but costly to set up; NMF handles overlap best but needs many manual steps.

## Consequences for the app

- The segmentation truth is theirs; the detector's quality is judged by what it does to the segmentation (ADR 043).
- **Edge errors:** B1's three truth-Al edge-on calls sit 1–2 px from truth needles. The paper's point that the truth is
  uncertain at edges fits that. The earlier suggestion that the pattern picks up a neighbouring needle does not hold: the
  probe is 1.3 nm and the step larger. Corrected in the B1 record.
- **Overlap:** none of our rules applies their priority scheme; neither does their vector matching.
- **Open: the scan step.** The paper's text gives a 4.6 nm step (and "about 2.4 µm²" for 512 × 512); their
  `datasetA_preprocessed.hspy` axes say 2.4943 nm/px (read from the file 2026-09-28); the 400 nm bar in their Fig. 7
  suggests about 2.2–2.5 nm/px (a rough read of a figure). The R scale sets every length and density the app reports on
  this dataset, so it must be settled with the authors before a density is quoted.
