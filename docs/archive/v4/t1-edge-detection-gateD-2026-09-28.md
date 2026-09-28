# T1 plate edges called Al — Gate D, detection against Thronsen's peaks (2026-09-28)

The app's largest error class on Thronsen A at stride 3 (T4 configuration): 204 truth-T1 positions called Al, 53 % of its
383 errors, 169 within 1 full-resolution px of a T1 plate edge. Her published vector analysis loses 43 there. Measurement
only; no `mac4DSTEM/` code changed.

**Inputs.** Our side: one probe run in the T4 configuration with `--dump-peaks` (every detected disk within the 0.68 Å⁻¹
reach, in Å⁻¹ from the measured origin 63.77, 63.75) and `--position-detail` for the 204 positions (surviving vectors after
matrix removal, why the position became Al). Her side: her own peak lists from A3a (`Peaks_com.npy`, `Peaks_noAl.npy`,
LoG threshold 0.0005 on max-normalised patterns, COM refined, Al vectors removed at 8 px). Logs: `t1edge/probe.log`,
`t1edge/our-peaks.json`; predictions in `t1edge/predictions.md`, written before any list was compared.

**Convention.** On 150 truth-T1 positions, 99 % of our peaks have one of hers within 0.02 Å⁻¹ when her (row, col) maps to
our (y, x) with no sign flip; the next ordering reaches 92 %, the unswapped ones 42 %. The first comparison, judged from
her side, could not separate them (≤ 19 %), because she reports 43.8 peaks per pattern to our 10.0.

| Prediction | Outcome |
|---|---|
| P1 at ≥ 60 %, she keeps ≥ 2 non-Al vectors where we keep ≤ 1 | **held**: 66 % |
| P2 most of her non-Al vectors there have no peak of ours within 1 px | **held**: 223 of 308 (72 %) |
| P3 her vector analysis calls ≥ 70 % of the 204 T1 | **refuted**, narrowly: 68 % |

**Diagnosis (D-det holds).** At T1 plate edges our detection does not find the weak T1 reflections her peak finder keeps;
with ≤ 1 vector left after matrix removal, 177 of the 204 go to Al through the direct-matrix shortcut (27 have ≥ 2 and are
lost to other rules). The matching rules are not the cause at those 177. Her threshold is about 0.05 % of the pattern
maximum against our 0.15 % floor, and her LoG also keeps many noise peaks (43.8 per pattern), which her Al removal and
per-pattern reference subset tolerate. Lowering our floor to 0.1 % raised T1 speckle to 23 (detection-floor sweep): the
lever is detection that finds weak real disks without noise, which is what a detector trained on marked disks is for.

**Next.** Register a detection change scored under T4 with every class's cost: a learned detector fine-tuned on marked
disks (C3), or a LoG-style finder as a second classical option. Each is judged on per-position error and every class's
speckle together.

## Addendum, same evening: what the missed peaks are

Looked at directly (`figs/06-t1-edge-closer.png`, linear and log, with her full peak list, her non-Al list, ours, and the
Al positions from her pure-Al pattern), every visible disk in the example T1-edge patterns sits on an Al reflection; no
T1 lattice is visible. Measured over all 204 positions (contrast of a 1.5 px disc against a 4–7 px ring, in the ring's
noise σ): Al disks median **64.6 σ** (p10 41.0); her non-Al peaks median **1.7 σ** (p10 0.9, p90 2.9, n = 625); random
background spots −0.3 σ. Her extra peaks are real but about 40 times fainter than the Al disks: at most a trace of T1.

**Revised reading.** The diagnosis above holds mechanically (she keeps features we do not detect), but the features are
barely above noise, and the patterns are Al to the eye (the owner's reading too). At plate edges the truth's T1 label
follows where the annotators drew the boundary in virtual dark-field images, which the paper states is uncertain. Most of
the 204 are therefore an edge-definition question, not a detection failure to chase. The stride-3 sampling is not a
cause: each pattern is the full-resolution pattern at that position.
