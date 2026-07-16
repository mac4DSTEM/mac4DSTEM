# mac4DSTEM training-dataset evaluation — 2026-07-15

## Outcome

All four datasets in `References/training_dataset/` were evaluated first on the unchanged build and then on the fixed build. The source HDF5 files remained byte-for-byte unchanged. Import/discovery, CBED reads, virtual imaging, cancellation/restart, comparison, qualitative DPC/iDPC, calibration operations, Bragg detection, save/reopen, EMD export, and py4DSTEM readback completed without crashes.

The fixes reduced the full optimized campaign from 148.20 s to 18.90–33.28 s on this host across repeated fixed-build runs. The principal improvement was the 125×125 Au Bragg path, which fell from 111.01 s to 2.92–3.49 s while preserving 103,657 detected peaks. HDF5's 108 native diagnostic stacks were reduced to zero.

Quantitative scientific claims remain blocked wherever the supplied metadata is insufficient. No physical values, material models, expected maps, or simulation parameters were guessed.

## Inputs

| File | Discovered node | Shape | dtype | Supplied voltage |
|---|---|---:|---|---:|
| `Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5` | `/datacube_root/datacube/data` | 90×45×128×128 | uint32 | 300 kV |
| `downsample_Si_SiGe_exp.h5` | `/4DSTEM_experiment/data/datacubes/datacube_0/data` | 50×200×128×128 | uint64 | 200 kV |
| `polycrystal_2D_WS2.h5` | `/4DSTEM/datacube/data` | 128×128×128×128 | float32 | 200 kV |
| `sim_Au_data_all_binned.h5` | `/4DSTEM_simulation/4DSTEM_AuNanoplatelet/data` | 100×84×125×125 | uint16 | 200 kV |

The Au file also contains the equal-shape alternate node `/4DSTEM_simulation/4DSTEM_polyAu/data`; the deterministic discovery result is the Au nanoplatelet node above.

## Unchanged-build findings

1. Calibration readiness accepted any positive Q/R pixel size, including `1 pixels/pixel`, as physical calibration. This falsely advertised quantitative readiness on all four Q scales and on three R scales.
2. Optional HDF5 discovery/calibration probes printed 108 native error stacks even though missing optional paths were handled normally.
3. Accelerate does not provide a general exact DFT setup for length 125. The correctness fallback therefore performed scalar O(N²) row/column DFTs for every Au diffraction pattern. Au input preparation took 164.59 s in the dedicated ACOM benchmark and Bragg detection took 111.01 s in the campaign.
4. `tools/real-data-acceptance/expected.json` described seven older datasets instead of the four current files, so every valid current run failed the report-count comparison.
5. `tools/real-acom-benchmark/run.sh` resolved a relative dataset path only after changing into its temporary directory, making relative inputs fail.
6. Particle and Si/SiGe origin maps had poor fit quality. Plane RMS residuals were 18.2948 px and 11.6551 px, larger than probe radii of 10.6244 px and 5.0264 px. Constant/parabola alternatives were not meaningful fixes: particle 18.7196/18.1379 px; Si/SiGe 13.1331/11.3020 px.
7. Native UI automation timed out after 54 s waiting for `dataset.card` during the first real-file import. The Debug app remained alive and did not crash. This is recorded as a host/accessibility limitation; the optimized production-source harness covered the real-data operations instead.

## Implemented fixes

- Added cached exact radix-3/radix-5 FFT plans with analytic-bin and round-trip tests. Native detector dimensions and circular-correlation semantics are preserved; no zero-padding was introduced.
- Added one physical-unit normalization/conversion contract for readiness, DPC/iDPC, ACOM scale setup, and parallax reconstruction. Pixel or missing units now remain explicit prerequisites. Unicode `Å⁻¹` and pm are handled consistently.
- Added an origin-quality gate: a measured-map RMS residual above the probe radius no longer unlocks quantitative origin/probe workflows. The UI detail explains that recalibration is required.
- Disabled HDF5's thread-local automatic stderr stack at every reader entry point; mac4DSTEM continues to return its own actionable errors.
- Updated the real-data goldens to the current four files and fixed relative paths in the ACOM runner.
- Added `tools/training-dataset-campaign/`, a reproducible optimized real-data matrix with cancellation/restart, source-preservation checks, atomic sidecars, native reopen, and py4DSTEM readback. Dataset voltage, alternate HDF5 nodes, and optional phase models now come from its explicit manifest; the harness never derives scientific inputs from a filename.

## Final dataset matrix

Common passes for every file: import/discovery, five-position CBED navigation, pre-cancel and mid-run cancellation, restart, BF and annular virtual images, product comparison, finite qualitative DPC/iDPC, rotation calibration, Bragg detection, atomic save/reopen, source preservation, EMD export, and py4DSTEM `BraggVectors` + `RealSlice` readback.

| Dataset | Origin/probe | Ellipse | Bragg | Strain | ACOM | Quantitative iDPC / reconstruction |
|---|---|---|---:|---|---|---|
| Particle | Quality-blocked: RMS 18.2948 px > 10.6244 px radius | Blocked: residual 0.469 | 42,734 peaks | No supported well-conditioned basis | Missing material and expected map | Blocked: physical Q missing |
| Si/SiGe | Quality-blocked: RMS 11.6551 px > 5.0264 px radius | Did not converge | 123,885 peaks | No supported well-conditioned basis | Operational explicit Si-diamond manifest model; 138/138 sampled positions matched, not quantitatively validated | Blocked: physical Q/R missing |
| WS₂ | Pass: RMS 0.0010 px | Pass: a 32.678, b 32.563, residual 0.0618 | 16,384 peaks | No supported well-conditioned basis | Blocked: no WS₂/custom non-cubic crystal model | Blocked: physical Q/R missing |
| Simulated Au | Pass: RMS 0.1616 px | Blocked: residual 0.466 | 103,657 peaks | Operational: 52.0% indexed, no expected strain map | Operational: 176/340 sampled positions matched, not quantitatively validated | Blocked: physical R missing |

The Si/SiGe and Au ACOM runs demonstrate operational execution only. Their phase choices are explicit campaign-fixture inputs, not filename inference. Neither dataset includes an expected orientation map or complete simulation parameters, so the output must not be treated as a validated physical result.

The generic sampled-pattern disk funnel explains the WS₂ default result without a material-specific branch: 45–47 edge-qualified maxima survive the absolute threshold in each sampled pattern, but only one survives the default `0.005` relative-to-brightest threshold. The detector therefore does find candidate disks; their correlation peaks are less than 0.5% of the dominant reference peak. The Advanced Detection UI now shows this stage-by-stage and lets the user lower or disable the relative cutoff before rerunning the full scan.

## Performance and behavior

The table uses the slower of the two final repeated runs as the conservative comparison; filesystem cache and host load account for the run-to-run spread.

| Dataset | Baseline total | Final total | Baseline Bragg | Final Bragg |
|---|---:|---:|---:|---:|
| Particle | 4.95 s | 5.04 s | 2.12 s | 2.70 s |
| Si/SiGe | 13.11 s | 10.96 s | 4.53 s | 3.07 s |
| WS₂ | 15.12 s | 10.83 s | 6.08 s | 4.52 s |
| Simulated Au | 114.66 s | 6.03 s | 111.01 s | 3.49 s |

Campaign wall time changed from 148.20 s to 18.90–33.28 s. Peak resident memory across the final runs was approximately 1.82–2.13 GB. No out-of-memory event occurred, cancellation published no partial products, and restart completed for every dataset. Peak memory remains worth monitoring on lower-memory Macs.

The dedicated final Au ACOM benchmark retained exact CPU/Metal template and angle agreement. Maximum score difference was `7.45e-7` and maximum reliability difference was `3.22e-6`.

## Export and UI coverage

- Actual per-dataset EMD sidecars were written atomically, reopened by mac4DSTEM, and read by py4DSTEM 0.14.19. Cancellation left no partial destination and source HDF5 attributes/sizes were unchanged.
- The production publication-PNG XCTest passed, including burned-in scale caption and colorbar. A real-file, save-panel PNG export could not be exercised per dataset because the host accessibility smoke test could not reach the imported dataset card.
- Sequential campaign processing showed no cross-dataset contamination, and the native replacement test confirmed that replacing a dataset cancels the old token and rejects late publication. Native UI replacement could not be driven for the same accessibility reason.
- Full iterative reconstruction was not run because no dataset supplied all required physical Q/R sampling. The app now reports those missing prerequisites instead of guessing them.

## Verification

- 32/32 native XCTest cases passed on the final code.
- 24/24 standalone scientific harnesses passed.
- All four real-data golden checks passed within their timing budgets.
- All four final py4DSTEM readbacks passed.
- Final campaign JSON was valid and contained no HDF5 diagnostic stack.
- Final source SHA-256 values exactly matched the pre-fix values:

| File | SHA-256 |
|---|---|
| Particle | `bf40e81a6bb1bb7135de07f3751f627241788ec826c5a8c2f4d08b04104786da` |
| Si/SiGe | `9bb1e593a26d6fe65b7f0cf7eae0f0e6f8b3793bc8a1c4164b182200e866d82a` |
| WS₂ | `88077031044cdb898bdb55541f143818eeac8713b1344960b481fcabde2d47b8` |
| Simulated Au | `a1323c913bd73818375f03eec564bfa81d7fa884f5640acfef941fdb31311e3f` |

Reproduce the optimized matrix with:

```sh
tools/training-dataset-campaign/run.sh
```
