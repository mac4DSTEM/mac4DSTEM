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
