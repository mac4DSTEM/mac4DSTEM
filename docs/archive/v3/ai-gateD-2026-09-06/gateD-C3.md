# Gate D — C3: the precipitate `widthPx` and `area` readings

Date: 2026-09-06. Branch `ml/disk-detector`.
The Gate B refuter reported two unasserted numbers that look wrong:
`widthPx` reads +4 % axis-aligned and +33 % diagonal (3.0 drawn → 3.99), and
`area` runs 1.6–2.4× the drawn area. This is the diagnosis for both, before
anything was changed.

**Which Gate D trigger applies.** Neither reading can move without moving a
*scientific* number (both are printed in the inspector table and the CSV
export), so the first trigger applies; and the cause of each was NOT
established by the refuter, only the symptom — so the second applies too.

**Spec first.** `docs/ai-ml/precipitates.md` §2 step 4 asks for "Length and
width from the object's principal axes, orientation, area" and gives no
numeric definition of any of the four. The only definition in the repo is the
one in `PrecipitateSegmentation.segment`'s own comment: the extents are taken
"over the member pixels whose flattened intensity is at least half the
object's peak — the half-maximum footprint". So the spec does not settle
either question; the code's comment settles `widthPx`, and nothing at all
settled `area`.

---

## §width — the +1 end-to-end convention

### Diagnosis

`mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift:193-194`:

```swift
let length = uMax > uMin ? uMax - uMin + 1 : 1
let width_ = vMax > vMin ? vMax - vMin + 1 : 1
```

`uMin/uMax/vMin/vMax` are the extremes of the **pixel-centre** projections
onto the object's principal axes. Adding 1 converts a centre-to-centre
distance into an end-to-end extent — which is exact only when the measurement
axis is one of the pixel-grid axes. For an axis-aligned bar 3 px wide the
centres sit at v ∈ {−1, 0, 1}: span 2, +1 = 3, exact. For the same bar
rotated, the centre projections are no longer spaced 1 apart along v; they
fill the strip almost continuously, so the span already approaches the bar's
true width and the +1 is added on top of a quantity that no longer needs it.

Competing hypotheses considered:

- *the anti-aliasing of a diagonal bar* — refuted below: the fixture draws a
  hard-edged bar (a boolean predicate), so no pixel is partially covered and
  there is no anti-aliasing to blame;
- *the ridge filter's smoothing spreading the object sideways* — refuted
  below: the over-read is present in the DRAWN image's own pixel geometry,
  before any filtering, background flattening or thresholding;
- *the half-maximum footprint being taken at the wrong level* — refuted:
  changing the level moves the width by ~0.7 px in the opposite sense (see
  §M11 below), and the over-read survives at the documented half level.

### The observation that would refute it

If the +1 were not the cause, then the drawn bar's own pixel-centre span
across the axis would be ≈ W − 1 (i.e. ≈ 2.0 for a 3-px bar) on a diagonal
just as it is axis-aligned, and the ~+1 px over-read would have to come from
somewhere downstream (filter, threshold, half-maximum level).

### Predicted outcome, stated before the experiment

Measure, in the test and directly from the drawn image, the span of the
pixel-centre projections across the true 37.2° axis. **Prediction: it comes
out ≈ 3.0, not ≈ 2.0** — i.e. essentially the bar's full width — and the
reported `widthPx` equals that span + 1 to within a few tenths.

### Outcome

Both fixtures in `PrecipitateTests` measure this. On the graded-cross-section
bar (drawn FWHM exactly 3.0 px, angle 37.2°), the drawn image's own
half-maximum footprint spans **2.9751 px** across the axis — not 2.0 — and
`widthPx` came back **3.7205** (`fix-c` probe run, 2026-09-06; the 0.26
shortfall against 2.9751 + 1 is background flattening lowering the profile
before the half-maximum is taken). On the sharp-edged bar the assertion
`widthPx == drawnCentreSpan + 1 ± 0.35` passes. The prediction held; the
diagnosis survived.

So the cause is the `+1`, and it is not a slip: it is the correct correction
for an axis-aligned object and the wrong one for a rotated object.

### Verdict — RECORDED, not fixed

There is no ≤ 30-line fix that is right for both cases, and I will not invent
a convention the owner has not chosen. The correction that is exact
axis-aligned (+1, one pixel pitch) and the correction that is exact for a
generic angle (+0, because the centre projections already fill the strip)
differ by a full pixel, and the true correction is the mean gap between
successive lattice projections onto that axis — a function of the angle with
no closed form, ~1 at rational angles with small denominators and ~0
elsewhere. Any of these is a *choice*:

1. keep +1 and state that a diagonal object reads up to ~1 px wide (today);
2. drop the +1 and state that an axis-aligned object reads 1 px narrow;
3. add the projected extent of one pixel, |ax| + |ay| (1 axis-aligned, 1.40
   at 37.2°) — the extent of the union of the pixel SQUARES rather than of
   their centres, which is defensible but reads 4.4 for this bar;
4. stop measuring extents and fit the object's profile.

**For the owner**: options 1–4, on a measurement the inspector and the CSV
both print. Until he chooses, the tests pin the current number and say in
their failure messages that it is recorded, not endorsed —
`testNoiseFreeNeedleMeasuresItsDrawnExtents` and
`testNeedleWidthFollowsTheHalfMaximumFootprint`.

---

## §area — the mask footprint, not the object

### Diagnosis

`PrecipitateSegmentation.swift:143` sets `let area = members.count`, and
`members` is the connected component of the THRESHOLDED filter response.
`Object.area` and `Object.pixelIndices` therefore agree with each other
exactly — `area` really is "the object's pixel count" — but the object in
question is the detection mask, and on needles the mask is the thresholded
*ridge response*, which is broader than the bar that produced it because the
Hessian's negative-eigenvalue lobe extends past the object's own edges.

So the refuter's 1.6–2.4× is not an arithmetic error: it is the difference
between two different things both called "area". There is no defect to fix
under the definition the code implements, and the spec names no other.

### The observation that would refute it

If `area` were *not* simply the member count — if it double-counted, or
counted a different pixel set from `pixelIndices` — then `area` and
`pixelIndices.count` would disagree on some object.

### Predicted outcome, stated before the experiment

`area == pixelIndices.count` for every object on every fixture, and the
mask/drawn ratio stays in a band around the refuter's 1.6–2.4× on the noisy
fixture while the *length and width* stay correct (because those are measured
on the narrower half-maximum footprint, not on the mask).

### Outcome

Confirmed on both fixtures. `testNeedleMaskFootprintExceedsTheDrawnBar` now
asserts `area == pixelIndices.count` and pins the ratio band (1.3 … 2.9)
against the rasterised drawn pixel count of each interior needle, while the
length/orientation assertions continue to pass.

### Verdict — RECORDED, not fixed

`Object.area`'s doc comment now says what it is (the thresholded mask
footprint, ~2× the drawn bar, and NOT `lengthPx * widthPx`). **For the
owner**: either rename it `maskAreaPx` everywhere it surfaces (inspector "A",
CSV) or re-measure it on the half-maximum footprint that already supplies
`lengthPx`/`widthPx`. It is threshold-dependent either way, which is worth
saying next to the number the way the density's criterion already is.

---

## §threshold — a degenerate robust threshold on a noise-free image

Found while building the fixtures, not in the refuter's report.
`robustThreshold` returns `median + sigmas · 1.4826 · MAD`. On a perfectly
noise-free field the MAD is 0, so the threshold collapses to the median
(0) and the mask becomes "any positive filter response": the noise-free bar's
mask came out ~47× the drawn bar. The extents survive it (they are taken on
the half-maximum footprint), and no real dark-field image has MAD 0, so this
is not a shipping defect — but a synthetic or heavily-denoised input could hit
it. **For the owner**: worth a floor on `robustSigma`, or a refusal, rather
than a silent whole-image mask.
