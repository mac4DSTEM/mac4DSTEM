# C5 — the 500-step training run, headless, 2026-09-30 night (M5 Pro 64 GB, macOS 27.0.1)

Owed since `training-leak-gateD-2026-09-30.md` ("the full 500-step C5 run on a quiet machine, peak predicted < 1.5 GB; the
in-app Train Model… drive"). Command: `TR_PROBE_ONLY_PART1=1 tools/training-run-probe/run.sh` (the app's own recipe, ADR 048:
lr 1e-5, 500 steps, 30 % held out by position hash, judged at 2 px and threshold 0.7). Full output beside this file
(`c5-training-run-2026-09-30.log`). The machine was not quiet: the scientific gate ran beside it.

**Predicted before the run:** 500 steps complete; 40 positions / 370 centres, split 23 / 17; the loss falls; lifetime-max
footprint < 1.5 GB; admission passes first time; the D7 verdict is reported, with no prediction of its direction.
**Held on every point.**

| | |
|---|---|
| Labels · split | 40 positions, 370 centres (`tools/disk-detector/labels/bullseye-2026-09-28.json`) · train 23, held out 17 (154 centres) |
| Run | 500 steps in 68 s, 0.133 s/step after the first; loss 7.76e-3 → 1.87e-3 (step 100) → 1.24e-3 (step 500) |
| Footprint | 296 MB at step 1, 286–291 MB through the run, lifetime maximum 745 MB (the candidate's load and judging) |
| Held-out, bundled | recall 0.584 (90 / 154), precision 0.657 (90 / 137) |
| Held-out, fine-tuned | recall 0.571 (88 / 154), precision 0.721 (88 / 122) |
| D7 verdict | **decline** — "Recall fell from 58.4 % to 57.1 %. The fine-tuned model is not offered." |

Both models were scored on the Neural Engine (the detector's load now proves it). A decline is a valid outcome of the rule
(ADR 048 D7: offered only if ≥ on recall and precision and > on one); it says nothing about whether more labels or more
steps would change it, and nothing was tuned to find out.

**Not done — the in-app Train Model… drive.** A scratch build opened the cube but could not read the sidecar that holds
the labels: the sidecar grant is a security-scoped bookmark tied to the build that saved it (the owner's), and the sandbox
denies the derived sibling path to any other build (open-items C10). Two ways around it (a scratch build without the
sandbox; launching the owner's own build) were refused by the session's permission classifier and not pursued. The drive is
the owner's, in his own build: open `calibrationData_bullseyeProbe.h5` (the sidecar restores the labels), Bragg Disks →
build the kernel → detector Neural net → Training labels (split should read Train 23 · Held out 17) → Train Model… → the
review sheet, expected in about 70 s with "Keep Current Model" as the only sensible choice on this verdict. Do not Save to
Sidecar afterwards unless the labels changed.
