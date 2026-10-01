# T2 predictions, written 2026-10-01 BEFORE any T2 run
Metric: held-out (17 pos / 154 centres) recall/precision at 2 px, thr 0.7, NE; Synthetic drawn disk; r10 = after the owner's one-click outer-edge radius; r6.8 = today's drive default.
Reference (T1, same seed 20260930): r10 bundled .662/.829, ft .701/.800 (decline: precision fell); r6.8 bundled .032/.357, ft .234/.480 (offer).
P0 noise: 3 seeds of the baseline: ft recall spread <= 4 centres (~.03) at r10; <= 12 centres (~.08) at r6.8 (far from converged). Bundled identical across seeds.
P1 steps (r10): 250/500/1000 all within noise of each other (+-.03). At r6.8 1000 > 500 > 250 by > noise (+.05..+.10 per doubling).
P2 lr (r10): 5e-6 within noise (-.01); 2e-5 within noise or +.02. At r6.8: 2e-5 clearly > 1e-5 (+.08), 5e-6 clearly below.
P3 augmentation off (r10): within noise (+-.03); precision no change. At r6.8: slightly worse (-.03).
P4 label count 10/20/23: monotone but weak at r10 (10 vs 23: <= .04 recall). At r6.8: stronger (>= .05).
P5 no single change at r10 beats baseline beyond noise; D7 verdict at r10 stays "decline" or flips between decline/offer on precision noise. At r6.8 no run reaches the r10 bundled recall (.66): the radius click is worth more than any recipe knob.
P6 each run ~70 s on the M5 (T1) +- 20 %.

# T2 report (2026-10-01) — training recipe knobs, one at a time
Setup: tool copy only ($LD/probe/main.swift = T1's probe + TR_LR / TR_AUGMENT / TR_SEED / TR_NTRAIN knobs; $LD/build.sh builds once; runall.sh / run2.sh loop under the heavy lock; logs $LD/logs/*.log, each ends EXIT=0; table by $LD/summ.sh). No repo writes.
Labels: ONLY the committed 40 positions / 370 centres exist on disk (tools/disk-detector/labels/bullseye-2026-09-28.json, Claude-labelled, owner-approved). The owner's 66-position set is not in the repo, References/ or docs (it lives in the app container, which the agent cannot read) -> not used. Consequently NO inter-labeller check was possible. Split 23 train / 17 held-out (154 centres), 2 px, thr 0.7, NE, 500 steps, lr 1e-5, augment on, seed 20260930 unless stated. Held-out is identical in every run (label-count runs drop TRAIN positions only). Single dataset (bullseye): per the threshold rule, nothing here is a property of the method.
Run time: 0.138 s/step on the M5 -> ~70 s per 500-step run incl. prepare + judge (250: 35 s, 1000: 135-140 s). Lock waits not counted.

## Noise (baseline, 6 seeds, r10): fine-tuned recall 108,108,108,110,109,109 /154 (.701-.714), precision .800-.827; bundled fixed 102/154 .662 / .829 (123 predicted).
=> run-to-run noise: +-1 centre in recall (range 2), ~.027 in precision. Seeds 1 and 2 gave identical counts but different final losses (1.34e-3 vs 1.76e-3): a coincidence, not a seed that is ignored.
Baseline reproduces T1/C5 exactly (r10 108/154, r6.8 36/154).

## Results (held-out recall/precision; B = bundled, FT = fine-tuned; D7 = TrainingPolicy.offer)
r10 (Synthetic disk at the ring's outer edge = after the owner's one-click):
| run | FT recall | FT precision | D7 |
| baseline (6 seeds) | 108-110 /154 (.701-.714) | .800-.827 | decline in 6/6 (precision below B's .829) |
| steps 250 | 111 (.721) | .854 | OFFER |
| steps 1000 (3 seeds) | 112-113 (.727-.734) | .800-.806 | decline 3/3 |
| lr 5e-6 | 110 (.714) | .846 | OFFER |
| lr 2e-5 | 111 (.721) | .810 | decline |
| augment off | 107 (.695) | .823 | decline |
| 10 train positions | 110 (.714) | .840 | OFFER |
| 20 train positions | 110 (.714) | .803 | decline |
| (all 23 = baseline) | | | |
r6.8 (today's drive default; B = 5/154 .032 / .357):
| run | FT recall | FT precision | D7 |
| baseline (3 seeds) | 36 (.234) in 3/3 | .480 / .537 / .507 | offer |
| steps 250 / 1000 | 36 (.234) / 38 (.247) | .554 / .447 | offer |
| lr 5e-6 / 2e-5 | 30 (.195) / 36 (.234) | .566 / .444 | offer |
| augment off | 32 (.208) | .464 | offer |
| 10 / 20 train positions | 37 / 37 (.240) | .561 / .481 | offer |

## Verdicts against the predictions
P0 held (noise +-1-2 centres at r10); at r6.8 recall is 36 in all three seeds (narrower than predicted, not wider).
P1 half held: at r10 steps move recall by +1 (250), +3-4 (1000) — 1000 steps is the only change outside the baseline range (112-113 vs 108-110) but costs precision (.80, below B) so D7 declines; at r6.8 steps change recall by 0-2 centres, NOT +.05..+.10 as predicted (refuted).
P2 refuted at r6.8: lr 2e-5 leaves recall at 36; only precision moves (.44-.57), within the precision noise. At r10 inside noise (111 vs 108-110).
P3 held: augment off -1 (r10), -4 (r6.8) — at most a marginal loss, not beyond the 2-centre range except at r6.8 (-4 centres, one run).
P4 refuted for recall: 10 / 20 / 23 positions give the same recall at both radii (110/110/108-110; 37/37/36). The model learns nothing more from labels 11-23 at this recipe.
P5 held: the r10 bundled model (.662/.829) is far above every r6.8 fine-tuned run (best .247 recall): the radius click is worth ~.4 recall, every recipe knob <= .03. Nothing at r6.8 comes close.
P6 held (70 s).

## What beats baseline beyond noise?
Nothing that D7 would ship. 1000 steps raises recall ~+.02-.03 beyond the seed range but precision stays at ~.80 (< bundled .829), so D7 declines it; the D7 "offers" at r10 (steps 250, lr 5e-6, 10 labels) are precision draws (.84-.85) inside the baseline's own precision spread over seeds (.80-.83 gives decline 6/6 but only 6 seeds, and these single-seed offers were not replicated) — not evidence for a recipe change. At r10 the bundled model is already hard to beat: fine-tuning adds +6 to +11 centres and costs ~1-3 points of precision; at r6.8 fine-tuning is rescuing a wrong probe (offers a worse model than bundled-at-r10). No recipe change is proposed; the recipe at 500 / 1e-5 / augment on stays.
Caveats: one dataset, one split (17 positions, 154 centres: one centre = .0065 recall), Synthetic arm only (File probe not re-run), two radii only; labels are a single (Claude) labeller; the owner's 66-set not available so effectiveness on the owner's own labels is unmeasured.
Pinned harnesses that would move: none (no code changed).
