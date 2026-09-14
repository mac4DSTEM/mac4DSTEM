# The pre-registered precipitate baseline — measured 2026-09-11, UNSCORED

`docs/ai-ml/precipitates.md` §6 pre-registered, before the
code was written:

> A baseline: threshold + connected components without the ridge filter. The
> ridge filter must beat it on both the synthetic fixture and the hand count,
> or it does not ship.

It was never written. This is it. **The gate as a whole is UNMET** — the
Al-Si-Mg hand count does not exist (owner, 2026-09-11: "no time"), so only the
synthetic half is scored here. Precipitates are **not wired** to any product.

## What "baseline" turned out to be

No new engine code. `PrecipitateSegmentation.Mode.particles` **is** the
pre-registered baseline — background flatten, Gaussian smooth, threshold,
connected components — and `.needles` is the identical pipeline with
`ridgeMeasure` inserted between the smooth and the threshold. The two arms are
therefore ridge-on and ridge-off over one code path. One further difference,
stated because it is not nothing: `.needles` also drops objects shorter than
`minimumLengthPx`; `.particles` does not.

## The criterion

Owner, `docs/decisions.md` 2026-09-11 (second round): **recall and precision
decide, and a tie passes.**

## Fixture

`mac4DSTEMTests/PrecipitateTests.swift` `buildFixture()` — 200x200, a linear
ramp background, seeded Gaussian noise (sigma 2), **six needles** of known
length, width and orientation (37.2, 127.2, 0, 90, 60, -20 — deliberately
sign-discriminating, the S8 lesson) and **three round particles** (sigma 10)
that a needle counter must reject. Needles E and F are drawn clipped by the
frame edge on purpose.

## Result

| | objects | needles found | particles reported | precision |
|---|---|---|---|---|
| **ridge** (`.needles`) | 9 | **6 / 6** | **3 / 3** | 6/9 |
| **baseline** (`.particles`) | 9 | **6 / 6** | **3 / 3** | 6/9 |

Per-needle measurement, the four interior needles (E and F are edge-clipped and
excluded from length scoring, as the fixture intends):

| needle | drawn L | ridge L | baseline L | error (both) | drawn angle | ridge angle | baseline angle |
|---|---|---|---|---|---|---|---|
| A | 34 | 34.22 | 34.22 | **+0.6 %** | 37.2 | 36.49 | 36.35 |
| B | 42 | 42.60 | 42.60 | **+1.4 %** | 127.2 | -53.33 | -52.91 |
| C | 48 | 49.00 | 49.00 | **+2.1 %** | 0.0 | -0.13 | -0.00 |
| D | 54 | 55.00 | 55.00 | **+1.9 %** | 90.0 | 89.87 | -89.95 |

(B and D read folded into (-90, 90]: -53.33 is 126.67, and -89.95 is 90.05.)

## Verdict on the half that could be scored: TIE, therefore PASS

Recall ties at 6/6. Precision ties at 6/9. Length error is **identical to two
decimal places** on every interior needle. Under the owner's criterion a tie
passes, so the ridge filter passes the synthetic half.

## What the tie actually reveals, which matters more than the verdict

**The ridge filter does not reject the round particles — its entire purpose.**
Both arms report all three. The only measurable difference between the arms on
this fixture is mask `area` on the round objects, where the ridge arm is ~20 %
smaller (578/586/596 vs 718/723/716); `area` reaches an export through
`arealDensity`, so this is not cosmetic, but it is not discrimination either.

Lengths are identical between arms because length is measured on `flattened`
at half maximum, and the mode changes only `filtered`, which drives the mask.
So the ridge filter changes which pixels form an object, not the measured size.

The fixture's own design note concedes the mechanism, and it was written before
this comparison existed:

> making sigma large keeps the particle's incidental curvature far below a
> needle's, since the literal ridge measure (larger-magnitude negative
> eigenvalue) is not itself elongation-selective

So the fixture was built knowing the ridge measure is not elongation-selective,
and then scored a pass because the particles were made easy enough not to
matter. **A pass obtained this way is not evidence the ridge filter earns its
place.** It is evidence that this fixture cannot tell the two arms apart.

## What is still owed, and it is one thing

The Al-Si-Mg hand count on a frozen region. The real image has what this
fixture lacks — touching needles, faint needles, mottled elongated background.
A counting sheet was prepared 2026-09-11 from
`References/training_dataset/060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5`
(330x330 scan, 1.539 nm/px, 508 nm field). **The first attempt at this sheet
identified the wrong reflections** and is corrected here: peak-finding on the
MAX diffraction pattern selected two single-pixel detector spikes at r = 8.1
and 8.5 px, not superlattice reflections. Proof: at the (40,31) candidate only
ONE scan position of 108 900 exceeds 20 sigma, while a quiet background pixel
at the same radius has MORE positions above 3 sigma (2.35 % vs 0.58 %). A real
reflection is elevated at MANY positions, not one.

Re-found with a spike-insensitive statistic — the fraction of scan positions
where a detector pixel exceeds mean + 4 sigma — the real reflections are three
Friedel pairs, each hot at ~0.9 % of positions: (35,23)/(29,41), (40,39)/(24,25)
and (33,22)/(31,41), at r = 9.1-10.7 px against a matrix ring at ~18 px. Three
pairs is what beta-double-prime in Al-Mg-Si gives: three needle variants along
the three <100>Al directions, and the combined image shows needles running in
three distinct directions.

Summing each Friedel pair improves the dark field about fourfold: peak z goes
from 9.2 to 31.1 and the 99.9th percentile from 4.9 to 21.6 sigma. A plain
5-sigma threshold now finds 34 objects of >= 6 px where the old image gave 18.
Background subtraction in diffraction space was tried and REJECTED — measured,
it made the image slightly worse (z(p99.9) 4.91 -> 4.21), because the
real-space background flattening already removes the beam tail and the
reference aperture only adds shot noise.. **One hand count completes this gate.** Nothing else is owed.

Sharpening the fixture now — adding touching or faint needles because this
comparison could not separate the arms — would be re-registering after peeking,
and is refused.
