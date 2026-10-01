# Second references beyond py4DSTEM — feasibility survey (2026-10-01; web docs only, nothing installed)
Evidence grades: [F] fetched this session; [S] seen in a search result; [K] from memory, verify before citing. Licences marked [K] must be checked in each repo's LICENSE.

## 1. Matrix (Y = yes, P = partial, - = no; "indep" = algorithm independent of py4DSTEM's, "lin" = same lineage / re-implements it)
| Feature | LiberTEM (+blobfinder/holo/iCoM) | HyperSpy + pyxem (+orix, diffsims) | GMS STEMx (proprietary) | Prismatic / abTEM | Ptycho refs |
|---|---|---|---|---|---|
| Loading DM4/HDF5-EMD/MIB | Y: DM3/4, MIB, EMD/HDF5, EMPAD, SER, MRC (indep readers) [F] libertem.github.io/LiberTEM | Y: via HyperSpy/rosettasciiio, DM4/HDF5/MIB [K] | Y native (DM4 is its format) gatan.com/node/2863 [S] | - (they write arrays) | PtyRAD reads py4DSTEM/PtychoShelves files [F] pypi.org/project/ptyrad |
| Calibration origin / ellipse / R-Q / Q from crystal | P: centre via COM/blobfinder refinement (indep) [S] pypi.org/project/libertem-blobfinder | P: centre-beam find, calibration objects, affine distortion; no ellipse fit as in py4DSTEM [K] | P: GUI calibration, conventions undocumented here [S] | simulators: truth calibration by construction | - |
| Virtual imaging BF/ADF/custom | Y: virtual detectors, ring/disk/custom masks, GPU/MapReduce (indep) [F] | Y: virtual apertures/signals (indep) [K] | Y: virtual apertures [S] gatan.com/node/2863 | - | - |
| Bragg disk detection | Y: blobfinder correlation (template/fast-correlation + refinement; indep, same idea as py4DSTEM's) [S] pypi.org/project/libertem-blobfinder/0.6.0 | Y: peak finders (difference of gaussians, template, LoG; indep) [K] | P: max-pixel/Gatan scripts [S] gatan.com/resources/scripts-library | truth positions from the exit wave | - |
| Strain | Y: blobfinder strain map (lattice fit; indep) [S] | Y: pyxem strain from vectors/affine fit (indep) [K] | Y: strain mapping workflow [S] | truth from planted displacement (abTEM atoms) | - |
| ACOM / orientation | - | Y: template matching (diffsims library + orix; indep of py4DSTEM's sparse correlation) [F] pyxem.readthedocs.io tutorial 11, 02 | Y: orientation mapping (method undocumented) [S] | truth orientation by construction | - |
| Phase mapping (vector matching) | - | P: indexation via vector/template matching [K] | P (orientation mapping workflow) | truth | - |
| DPC / iDPC | Y: iCoM / COM (LiberTEM-iCoM) [S] | Y: DPC/ COM in pyxem/HyperSpy [K] | Y: DPC workflow [S] | truth from simulated COM of a known field | - |
| Parallax / tilt-corrected BF | - | - | - | Simulator generates the cube | quantem (parallax + AD ptycho, 2025) [S] arxiv 2505.07814 text; py4DSTEM = the app's present reference |
| Single-slice ptychography | P: SSB direct ptychography only (indep) [F] | - | - | Simulator generates the cube | PtyRAD (AD/PyTorch, MPS ok, LGPL-3.0, indep of py4DSTEM) [F]; PtychoShelves/fold_slice (Matlab, GD/ePIE, indep) [S]; ptypy [K]; phaser [S] arxiv.org/abs/2505.14372 |
| Preprocessing crop/bin/stride/hot pixel | Y: ROI/ binning-by-masks, dead-pixel handling (indep) [F] | Y: HyperSpy rebin/crop; hot-pixel via filters [K] | Y (acquisition-side, dead pixels) | - | - |
| Licence | MIT [F] ; blobfinder GPLv3 [F] | GPLv3 (pyxem/diffsims/orix/hyperspy) [K] | proprietary | Prismatic GPL-3.0, abTEM GPLv3 [S] | PtyRAD LGPL-3.0 [F]; ptypy GPLv2 [K]; fold_slice/quantem [?] |
| Apple Silicon | pip/conda arm64 [K]; numba/JIT works | pip/conda-forge arm64 [K] | Windows only (GMS) [K] | abTEM pip, CPU/torch [S]; Prismatic: conda-forge osx-64 only listed, CUDA absent [S] | PtyRAD MPS [F]; quantem torch [?] |

Note: LiberTEM, blobfinder, pyxem etc. are not py4DSTEM-derived; they are independent implementations of the same textbook ideas (cross-correlation disk finding, lattice-fit strain, template-library indexing).

## 2. Where a second reference tells us something py4DSTEM cannot
- ACOM: pyxem/diffsims/orix is the one genuinely different algorithm (library of kinematic patterns + normalised/ fast correlation, orix symmetry for all 32 point groups). py4DSTEM's sparse correlation (arXiv 2111.00171) and ours share lineage. Agreement between independent methods on the same disk list tests the app's ACOM (and the cubic/hexagonal-only symmetry gap) beyond "matches py4DSTEM". Also gives a point-group-coverage oracle. Convention page: pyxem uses passive ZX'Z'' Euler, lab2crystal, Y_L = -Y_image [F].
- Disk detection and strain: LiberTEM-blobfinder (correlation + refinement) is the same idea with different peak refinement; tests sub-pixel bias and the strain fit separately from the detector. Cheap, but lineage-adjacent, so it can only confirm, not truth-test.
- GMS: users compare the app against GMS numbers; conventions (calibration, strain axes, orientation Euler convention) can only be read from docs/exported maps, cannot be scripted here; value = documented-convention table, not a harness.
- Simulators beat any second reference: a known specimen + probe gives truth for disk positions/intensity (kinematic or multislice), strain (planted lattice displacement), orientation/phase (rotated crystals, known grains; also resolves the "phase mapping unvalidated, no truth" label), parallax and ptychography (known potential, defocus, aberrations; matches ADR 050's "ground truth" ask), and thickness/dose scaling. abTEM (pure Python, pip, GPLv3, multislice 4D-STEM + frozen phonons, Apple Silicon fine on CPU) is the practical generator; Prismatic is unmaintained since 2026 [F] and has no Apple-Silicon build listed.
- Ptychography: PtyRAD (independent AD engine; MPS; reads py4DSTEM-format) and fold_slice are real second references for the single-slice GD and difference-map work; DM is not in either. Caveat: algorithms differ in regularisation, so compare image/probe quality metrics, not pixels.

## 3. Feasibility per comparison
Reusable infrastructure: tools/*/reference.py + conda env (py4DSTEM 0.14.19 vendored), `--dump-peaks`, the demo cube with truth.json, tools/phase-map-probe, tools/singleslice-ptychography-test (truth.py in progress). Axis order, rotation sign and units are the main risks; use identity-calibration wrappers as in the py4DSTEM recipe.
| Comparison | Effort | Reuse / notes | Licence | Risks |
|---|---|---|---|---|
| abTEM-generated truth cube (Al/precipitate grains, strained lattice, thin graphene for ptycho) | 2-3 sessions for generator + 1 each per feature scored | slots into existing truth.json scorers and the Gate D "fixture" rule; cube can be committed small (<1 MiB) as generator script only | GPLv3 tool used externally: fine; generator script GPL-compatible | kinematic vs multislice (dynamical) mismatch; simulated detector has no noise/MTF unless added; sampling/ Å-per-pixel convention |
| pyxem ACOM on the app's own peaks | 1-2 sessions | same wrapper pattern as py4DSTEM head-to-head; diffsims library generation needs its own excitation-error/sigma settings | GPLv3 external: fine | different scoring metric, Euler conventions (passive ZXZ vs app's), symmetry-reduction; compare misorientation, not Euler angles |
| LiberTEM blobfinder disk positions + strain | 1 session | feeds on 4D-STEM cube via HDF5/EMD export already produced by preprocessing export | blobfinder GPLv3 / LiberTEM MIT: fine | refinement is local fit vs Gaussian; frame (x,y) vs (row,col) |
| PtyRAD / fold_slice ptychography | 2 sessions (+ cube export, MPS run time) | needs EMD+metadata export of the simulated cube; PtyRAD reads py4DSTEM-style input | LGPL fine; fold_slice needs Matlab (not scriptable on a headless harness cheaply; skip) | engine differences; probe-defocus sign (the repo already hit defocus = -C1) |
| GMS convention table | 0.5 session, docs only | no harness | proprietary, nothing linked/copied | cannot run GMS; screenshots from user data only |
| HyperSpy as reader cross-check (DM4/MIB) | 0.5 session | dm4-parity-probe exists | GPLv3 external: fine | -|
No licence blocks external reference use (the app does not link or copy them). Do not copy their code or tables into the app (GPL-3.0 compat holds, but LiberTEM MIT/PtyRAD LGPL need notices if ever copied; none planned).

## 4. Recommendation (ranked)
1. abTEM ground-truth cube generator (disks, strain, orientation, ptychography) — stronger than any second reference; lands after the five slots (S2 R2+R3 already builds a ptycho truth; take that generator as seed, then widen) — 1st post-v4.1 item.
2. pyxem/orix template matching vs the app's ACOM on shared peaks — the only independent orientation algorithm; do after slot 5 or as S4 F-review aid if the owner wants; also answers point-group coverage.
3. PtyRAD on the same simulated cube for ptychography — after #1 (needs the cube); a read-only check in Slot 2/3 is possible by hand, not as a gate.
4. LiberTEM blobfinder for disks/strain — cheap; after v4.1.
5. GMS conventions: a docs-only table (axes, strain sign, Euler convention) — can be done now inside v4.1 as pure docs (no code, no gate), but only if wanted.
Timing: nothing new inside v4.1 (feature list frozen, ADR 049; these are tests, not features, but each costs a session and the slots are full). Start with #1 right after Slot 5, as one pre-registered lane.
Docs rule (one line): "py4DSTEM is the parity reference; pyxem/orix for orientation, LiberTEM for disks/strain, PtyRAD for ptychography as optional cross-checks; simulators (abTEM) for truth; GMS is read from its docs only."
