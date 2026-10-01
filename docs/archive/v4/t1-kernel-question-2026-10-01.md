# Lane T1 — the kernel question (headless File-probe run), 2026-10-01
## Summary
(in progress)
## Findings before any run (reading)
- tools/training-run-probe (C5, docs/archive/v4/c5-training-run-2026-09-30.md) HARD-WIRES kernelSource .fileProbe and the measured
  probe image (probe r 7.36, "probe_template"): so the headless C5 run of 2026-09-30 already IS a File-probe training run:
  held-out (17 pos / 154 centres) bundled recall 0.584 (90/154) precision 0.657; fine-tuned 0.571/0.721; D7 decline
  (docs/archive/v4/c5-training-run-2026-09-30.log). The Synthetic arm (the owner's 0/82) was never run headless.
- In the app, Synthetic = a DRAWN solid disk probe image (LearnedDetectionSession.syntheticProbe, radius = calibration
  probeRadius, 6.8 px per the owner's drive) fed to the net as its probe channel + a flat kernel on that disk (TrainingSampleBuilder
  and LearnedDiskDetector use ProbeKernel.flat on the probe crop regardless of source label). File probe = the real ring image.
## Predictions (dated 2026-10-01, written BEFORE any run of this lane)
P1 File-probe arm re-run (same labels, same split, 500 steps): reproduces C5 within +-3 centres per model: bundled 90/154 recall .584,
   fine-tuned ~88/154; D7 decline. (Not new information; a determinism check.)
P2 Synthetic arm (drawn disk r 6.8, same params): bundled held-out recall <= 0.10 (owner saw 0/82), precision <= 0.2 or undefined;
   fine-tuned recall <= 0.40 (500 steps at lr 1e-5 cannot relearn the probe channel) and strictly below the File-probe fine-tuned 0.571.
   D7 verdict for Synthetic: OFFER (fine-tuned beats a near-zero bundled) - an "offer" of a worse model than the bundled-on-File-probe.
P3 Classical detector at the app's params, all 40 positions: py4DSTEM-style flat kernel from the file probe: recall >= 0.5, precision >= 0.3;
   synthetic trench kernel at r 7.36 (what S21 recorded: 0.119/0.020) and at r 6.8: recall <= 0.2.
P4 Supported-claim test: if P2 holds (Synthetic bundled/fine-tuned << File probe at the same labels), "default = measured probe image when one exists"
   is supported for the LEARNED path. If Synthetic bundled recall > 0.3, the cause of the drive's 0/82 is elsewhere.
## Runs
- classical-only arms (run-classical.log, EXIT=0): all-40 / held-out-17, app params (minPeakSpacing 7, edgeBoundary 10, minRel .0015, sigmaCC 2; r 7.36):
  | kernel | all-40 recall | all-40 precision | held-out recall | held-out precision |
  | flat file probe (py4DSTEM-style) | .627 (232/370) | .083 (232/2800) | .610 (94/154) | .079 (94/1190) |
  | sigmoid-trench file probe r 7.36 | .616 | .101 | .597 | .093 |
  | synthetic trench r 6.8 (the drive's radius) | .119 (44/370) | .020 | .110 (17/154) | .017 |
  | synthetic trench r 7.36 | .151 | .029 | .143 | .025 |
  | synthetic trench r 10 | .887 (328/370) | .419 | .890 (137/154) | .396 |
  | synthetic trench r 14 | .616 | .388 | .656 | .390 |
  (synthetic r 6.8 reproduces S21's recorded 0.119/0.020 exactly.) P3 partly refuted: the flat file-probe kernel has recall .63 but precision .08 (<0.3).
- Training arms (runall.out: file/synth68/synth10 EXIT=0; logs run-file.log, run-synth68.log, run-synth10.log; same 40 labels / 370 centres, split 23/17, 154 held-out centres, 500 steps, lr 1e-5, NE, 2 px, thr 0.7; ~70 s each):
  | arm (probe channel + flat kernel) | bundled recall / precision | fine-tuned recall / precision | D7 |
  | FILE probe (ring image, r 7.36) | .584 (90/154) / .657 | .571 (88/154) / .721 | decline (recall fell) — identical to C5 |
  | SYNTHETIC drawn disk r 6.8 (the drive's) | **.032 (5/154)** / .357 (5/14) | .234 (36/154) / .480 | offer |
  | SYNTHETIC drawn disk r 10 (ring's outer edge) | **.662 (102/154) / .829** | .701 (108/154) / .800 | decline (precision fell) |
- Probe radial profile (bullseye probe_template, centre 125.05,125.0; python, mean/max): central peak to ~3.5 px, ring peak at 8, ring outer edge ~10.5;
  the estimator's 7.36 = ring's inner shoulder (S21).
## Outcome vs prediction
P1 held exactly (90/154, 88/154 = C5 bit for bit). P2 held (bundled 5/154 = .032 <= .10; ft .234 <= .40 and < .571; D7 offer — the offer is a worse model
than bundled-on-File-probe). P3 half refuted: classical flat file-probe kernel recall .63 but precision .08 (py4DSTEM-style kernel needs the learned/other filter).
P4: supported only in a narrower form. The owner's 0/82 is reproduced as 5/154 (the same cause: Synthetic at calibrated radius 6.8). File probe lifts bundled recall .032 -> .584.
BUT the synthetic arm at the ring's OUTER-edge radius (10) beats the File probe (.662/.829 vs .584/.657), and the classical trench at r 10 also wins (.887/.419 vs flat-file .627/.083).
=> Gate D diagnosis: the blocker is the RADIUS READ (inner shoulder 6.8/7.36 on a ring probe), not "synthetic vs measured" per se. "Default = measured probe image when one exists"
   fixes the learned path to .584/.657 (a big gain) but is not the best available; "outer-edge radius" (S21's patch) gives more and also fixes the Synthetic arm. Not enough to
   say measured is better than a correctly-sized synthetic; only one probe (bullseye) measured. Per CLAUDE.md threshold rule: measure the ten datasets before any default flips.
   Also noted: py4DSTEM correlates with the measured probe (flat for structured probes); in this app's learned path, source label does NOT change the kernel code — both arms use ProbeKernel.flat on the probe image; only the probe image differs.
## Changes
None. No app code changed (cause is established for the 0/82, but the correct default is a decision: file-probe-default vs outer-edge radius; flip requires the ten-dataset measurement).
Tool copy only: $LD/probe/{main.swift,run.sh} (TR_KERNEL=synthetic, TR_RADIUS, TR_CLASSICAL_ONLY knobs). Suggest folding these three env knobs into tools/training-run-probe if the owner wants the arm repeatable.
## Pinned harnesses that would move on a default flip (list only, not re-pinned)
Anything running the bullseye cube with the Synthetic default: tools/disk-detection-test, tools/bragg-spacing-probe/bullseye-*, tools/disk-detector/scan-bench, tools/datacube-discovery-test (bullseye fixture);
the learned-detector bullseye fixtures under tools/disk-detector. Normal (solid-beam) probes: File-probe default would move nothing only if the sized disk equals the image; unmeasured.
## git status --short
(no repo writes by this lane)
