# Vector-matched phase mapping — steps 1, 2, 4 and 5, 2026-09-12

The record of the session that landed
[`v3-vector-matching-plan.md`](../../v3-vector-matching-plan.md) steps 1, 2,
4 and 5, and deferred step 3. Method: **Thronsen et al., Ultramicroscopy 255
(2024) 113861, CC BY 4.0** — the published description only. Their GitHub
repository carries **no licence**, so nothing from it is here and every
parameter was derived in this repo.

## What is validated, and what is not

**Step 3 has NOT run.** Scoring this against their published ground truth
needs their preprocessed `datasetA`, ~7.4 GB, against a machine that ended
this session with 5.7 GB free. The owner chose to defer it and to land the
rest labelled. Everything the app publishes carries `validation: "none"` in
provenance, the task's guidance line says "Unvalidated", and the panel repeats
it above the legend. **A phase fraction read off this map is not a
measurement.**

What IS checked, and by what:

| claim | checked against |
|---|---|
| fcc reference |q| for {200} and {220} | arithmetic: 2/a and 2√2/a, to 1e-9 |
| monoclinic |q(h0l)| | the reciprocal metric a* = 1/(a sinβ) etc., worst 2.2e-16 |
| the library's projection | a separate projection in the harness — see Gate B, finding on the shared frame |
| β″ cell content | Mg₁₀Si₁₂ = 22 atoms, the paper's own statement |
| the matcher's verdicts | planted truth, four pre-registered criteria |
| the length-band prune | brute force, 60 000 probes, 0 mismatches |

## The two pre-registered criteria that failed, and why both were real

**P3 — random-vector positions must be "not indexed" ≥ 90 %. Measured 0 %.**
Cause, measured rather than guessed: a β″ [010] entry held **130** reference
vectors out to 1.2 Å⁻¹, and at the 0.06 Å⁻¹ pair radius first chosen those
cover **a third of the plane**. A third of any random vector set therefore
matched by chance, and with 180 in-plane orientations searched, something
always fitted. Two changes, each with a number behind it:
`maximumVectorsPerEntry` = 48 caps the density directly, and the pair radius
came down to 0.02 Å⁻¹ on a stated error budget (sub-pixel refinement ~0.004,
1 % Q-calibration error at |q| = 0.7 → 0.007, strain on top).
`PhaseOrientationReference.chanceMatchFraction` now reports the coverage, so
the trade is a number rather than a matter of taste.

**P5 — the fitted in-plane rotation must recover the planted 13.7°. Measured
284.0°, an error of 89.7 %.** This was the **test** being wrong. An fcc [001]
projection is 4-fold symmetric: 283.7° and 13.7° produce the same spots, and
no method that looks at spots can separate them. The check is now on the
vector **set**, with a sign-flipped plant shown not to satisfy it (0.270 Å⁻¹
away). The consequence is recorded wherever the angle is reported: an in-plane
rotation from this matcher is meaningful **only modulo the projected symmetry
of the phase**, and is never presented as an absolute orientation.

## The guard that was replaced rather than tuned

A minimum matched **fraction** is the obvious way to stop a phase explaining
one vector in ten from beating one explaining nine. It cannot work here,
because `maximumVectorsPerEntry` caps the library: a pattern showing more
spots than the library holds can never reach any fraction, and the harness's
β″ positions went to **0 % indexed while being perfectly matched**.

What replaced it is two things, and **the first version of this section
credited the wrong one** — corrected after Gate B measured them apart:

| removed | random-vector accuracy |
|---|---|
| nothing (shipped) | 99.2 % |
| the chance guard alone | **99.2 %, unchanged** |
| the matched-vector floor alone | 48.8 % |
| both | 5.5 % |

The 99.2 → 5.5 collapse is the **matched-vector floor** (3), not the chance
guard. The guard's bar is `5·V·ρ²·n/R²`, which at shipped settings crosses a
floor of 3 only above about **45 surviving vectors per pattern** — and the real
cube measured in step 4 has a median of **7**. So on typical SPED data the
floor binds and the guard is inert. It is kept rather than deleted because it
bounds a dense library on a pattern rich enough to need bounding, which a fixed
cap cannot see; the gate now prints the three rows above and the binding
threshold, so the wrong one cannot be credited again.

## The 2026-09-11 refutation, re-run and answered

On a pattern containing only **aluminium**, with gold and aluminium both
candidates, the template-matched route returned **gold** at a contrast of
−0.008 ([`phase-discrimination-2026-09-11.md`](phase-discrimination-2026-09-11.md)).
Vector matching returns aluminium **200/200**, contrast **+0.00618 Å⁻¹**.

| peak-position noise σ | Al | Au | refused |
|---|---|---|---|
| 0 px (0 Å⁻¹) | 200 | 0 | 0 |
| 0.25 px (0.0020 Å⁻¹) | 200 | 0 | 0 |
| 0.50 px (0.0040 Å⁻¹) | 200 | 0 | 0 |
| 1.00 px (0.0080 Å⁻¹) | 127 | 41 | 32 |
| 2.00 px (0.0160 Å⁻¹) | 34 | 30 | 136 |
| 4.00 px (0.0320 Å⁻¹) | 28 | 32 | 140 |

The separation survives to about half a detector pixel of position noise at
this scale and then degrades into **refusal** rather than into a confident
wrong answer. Al and Au (200) differ by 0.00348 Å⁻¹, 17.4 % of the shipped
pair radius — the discriminating quantity is now a distance a reader can
compare against the spacing they care about, which is exactly what the
template score could not offer.

## Step 4 — the Al-Mg-Si cube, and what it says

`tools/phase-map-probe` (diagnostic; needs a machine-local cube), on
`060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5`: scan 330 × 330,
detector 64 × 64 after 4× binning, **0.045741 Å⁻¹ per detector pixel** from the
file's own calibration, detector reach 1.464 Å⁻¹. Sampled at stride 6
(55 × 55 = 3025 positions), synthetic 2.5 px probe kernel, 22 267 peaks,
median 7 per pattern.

**1 — The pre-registered resolution prediction was WRONG, and the reason is a
reflection condition.** The prediction was that β″'s a* = 0.0684 Å⁻¹ = 1.50
detector pixels would make adjacent (h0l) reflections unresolvable. Measured:
the closest kept pair is **0.1368 Å⁻¹ = 2.99 px**, exactly 2a*. C-centring
(C2/m: h + k even) extinguishes odd h in the k = 0 zone, so only even h
survives. β″ **is** resolvable on this detector — and the extinction is itself
a check on the structure the app built from Andersen et al.

**2 — The specimen is not on ⟨100⟩Al.** Fitting every low-index Al zone axis
over 433 sampled patterns, the best is **⟨110⟩**, and all five sampled ⟨110⟩
equivalents tie at **39.0 %** of vectors explained with an identical mean of
0.0333 Å⁻¹. The exact tie across the family is what cubic symmetry requires,
so the sweep is behaving.

**3 — And that settles why the β″ library was the wrong one.** β″ is coherent
along its **b-axis** with a ⟨100⟩Al direction (Andersen et al. 1998). With the
beam on ⟨110⟩Al, **no β″ variant is viewed down its needle axis**, so a [010]β″
reference library cannot match this data whatever the tolerances. The run
labelled 1.0 % β″ and **99.0 % "not indexed"**, with zero matrix — which is the
correct outcome for a library aimed at an orientation the specimen is not in.

**4 — The origin has to be measured, not assumed.** The centre of mass of the
mean pattern is (31.772, 31.803) against a geometric centre of (31.5, 31.5) —
**0.407 px = 0.0186 Å⁻¹**, which is 93 % of the pair radius. An assumed centre
would displace every experimental vector by nearly the whole tolerance the
match is judged on.

**5 — Only 39 % of detected vectors are explained by the best Al orientation**
at one-pixel tolerance. On a specimen whose matrix is aluminium, that is a
statement about the **peak set**, not about the matcher: a synthetic 2.5 px
kernel with default spacing on a 4×-binned 64 px detector is finding maxima
that are not all Bragg disks. Phase mapping on this cube needs the app's own
calibrated detection first — a measured probe kernel, a fitted origin map and
the ellipse — which is exactly the path the UI takes and the probe does not.

**6 — And the crystallographic conclusion in (3) is OVER-DETERMINED, corrected
after Gate B.** At 0.045741 Å⁻¹ per detector pixel, **half a detector pixel is
0.0229 Å⁻¹ — larger than the entire 0.02 Å⁻¹ pair radius the match is judged
on** — and the best Al fit's own mean, 0.0333 Å⁻¹, is 3.3× the 0.01 Å⁻¹
not-indexed threshold. At default settings **nothing on this cube could be
indexed, for any library, at any zone axis.** The ⟨110⟩Al / β″-needle argument
may well be true and it is checkable; this run does not isolate it. The pair
radius itself was derived for "a typical calibration ~0.008 Å⁻¹/px", and the
only real dataset here is **5.7× coarser** — which is the owner's own point
about this cube being strongly binned, now with a number on it.

**What this run does NOT show:** that the method works on real data. It shows
that on this cube it **refuses**, that the refusal has at least two sufficient
causes and the measurement separates neither, and that the three numbers a user
would need to see the problem — the resolution budget, the matrix zone axis,
and the chance-match fraction — are all computable before any map is drawn.

## Step 5 — the UI, and the two decisions in it

The AI Analysis room gains a second task beside diffraction grouping. Two
choices carry more than presentation:

**The phase list IS the legend.** One row per phase, carrying the swatch the
map is drawn with and, after a run, the fraction of the scan it claimed. There
is no second legend to fall out of step with the first, and the row a user
edits is the row they read the answer off.

**Every position can be taken apart.** The panel's `Evidence` row names the
phase, how many of the surviving vectors it explained, the mean distance in
Å⁻¹, how many the matrix took, and what came second — for the position under
the cursor. That line is the whole argument for the colour, in physical units.
`PhaseVectorResult` keeps every count for exactly this reason.

Plus: "not indexed" is drawn as a **diagonal hatch**, not a colour, so it can
never be read as one more phase; the palette is **Okabe-Ito**, so two phases
are never red and green; and the matrix is a **neutral dark**, because it is
most of the scan and it is not the finding.

**Unseen on screen.** No part of this has been driven. That is the owner's
(`CLAUDE.md`; Track B retired 2026-09-03), and a defect he finds enters
through `/diagnose`.

## Every test that could not be broken first time

Five of the nineteen unit tests passed against the mutation they named. Each
is recorded in the test itself, because each is a trap that will recur:

1. **The pair-radius clamp is unreachable through a radial probe.** The
   length-band prune refuses the reference before the clamp is consulted, so
   only a probe at the same |q| and a different azimuth reaches it.
2. **The not-indexed threshold is unreachable through vectors pointing
   nowhere.** The eligibility guards refuse them first; what reaches the
   threshold is a pattern offset *inside* the pair radius and *above* the
   not-indexed distance.
3. **β″'s cell content does not pin its coordinates.** Changing Si3's z from
   0.617 to 0.671 — a transposed pair of digits — left all 22 atoms, both
   element counts, every cell parameter and the gated harness passing, because
   |q(h0l)| depends on the cell and not on where the atoms sit in it. The six
   published sites are now pinned directly, plus a shortest-contact band.
4. **`map` has two cancellation guards and they are redundant.** Removing
   either alone changes nothing; the test names both.
5. **"Refused before any work" is not observable by timing.** 44 640 entries
   build in under a second, because each is a rotation of an already-projected
   set. That assertion is labelled a smoke bound instead of pretending to be
   the ordering check it was written as.

## Gate B — 13 mutations, 11 survived

An independent refuter, briefed to refute, on the committed tree. **Eleven of
thirteen mutations left all 21 checks green.** What it found, and what was done:

**Fixed in Core, each with a regression test broken first:**

1. **The β″ C2/m expansion was pinned by nothing.** Changing the centring
   translation from (½,½,0) to (½,½,½) — C-centred to I-centred — left all 22
   atoms, both element counts, every cell parameter, the shortest interatomic
   contact (2.2700 Å, *identical*, because the shortest pair is in-layer and
   the translation only moves the y = ½ layer) and all 21 checks passing, while
   changing the reflection condition and therefore **half of β″'s reference
   vectors**. The gate now asserts the extinction conditions themselves, whose
   ground truth is the space group and not this code: β″ h + k even, fcc all
   even or all odd. Under the mutation, 712 of 1428 reflections violate it.
2. **`gcd(0, 0)` returned 1**, because `gcd` floored itself, so `[0 0 2]` never
   reduced and `lowIndexZoneAxes` held it beside `[0 0 1]` — 50 entries for 49
   directions, and 180 redundant library entries per phase at the default step.
3. **One distant spurious peak weakened the chance guard.** The accessible
   radius was `max |u|`, so a single far maximum inflated the area the chance
   expectation is computed over and turned refusals into labels — 10 false
   positives in 1024 random patterns, measured. It is the second-largest now,
   which is exact whenever the outermost peak is real and cannot be moved by
   one outlier.
4. **The number shown to the user was not the number the guard used** — the
   provenance and the panel computed the chance-match percentage at the
   library's full reach while `classify` used each position's own outermost
   vectors. Two quantities under one name. The key and the label now say which
   radius they mean.

**Assertions added, each verified to fail under the mutation it names:**

5. **The published contrast was never asserted positive.** Ranking phases by
   matched count instead of by distance leaves P6 green and makes the reported
   contrast **negative** (−0.00045 Å⁻¹ at σ = 2 px) — the winner then scored
   worse than the phase it beat, and the number shown to the user means
   nothing.
6. **P5a printed a reconciliation it never asserted** — a transposed rotation
   printed 62.3° instead of 0.3° and still passed.
7. **P8 proved the prune, not `nearest`.** Returning the *first* reference
   inside the radius instead of the closest passed all 60 000 probes, because
   no two references in either shipped library lie within one pair *diameter*.
   The new fixture is five references 0.008 Å⁻¹ apart inside a 0.02 Å⁻¹ radius
   — the long-axis case where the two rules diverge.
8. **The gate never ran the shipped library defaults** — Part A overrode
   `minimumIntensityFraction` to 0.02 against a shipped 0.05. And the check
   added for it was **itself vacuous** on the first try, comparing the default
   to the default; it pins the literals now.

**One remedy was broken before it was trusted, and rejected.** Gate B also
called `chanceMatchFraction`'s whole-count numerator a 12× overestimate and
proposed restricting it to the references the data can reach. That was
implemented and **measured**: with the numerator restricted, the new
outlier-sensitivity test went red on its FIRST assertion — random vectors in a
narrow annulus were indexed **with no outlier at all** — because a lower chance
estimate is a lower bar for eligibility. Reverted, and the reason is now in the
source: the uniform-disc model puts most of its area at large r while real and
spurious peaks cluster at small r, so it *understates* the true chance for the
distributions that matter; counting every reference pushes the other way, and
an overestimate of chance demands more evidence, which is the safe direction
for a guard whose job is refusing uninformative matches. It is an upper bound,
and the comment no longer calls it a probability. (This is the 2026-08-31
precedent: a refuter that finds a real defect can still be wrong about the fix,
and re-running its own experiment against the remedy is what catches it.)

**Recorded, not fixed** (each an entry in `open-items.md`): the harness shares
`ACOMOrientation.detectorBasis` with the code under test, so a handedness flip
mirrors both and stays green — the L3 trap, still open here, and covered only
by the separate `tools/acom-convention-test`; `Crystal.reflections` under-tiles
oblique monoclinic cells above β ≈ 110°, losing reflections silently;
`matrixToleranceInvAngstrom` and `pairRadiusInvAngstrom` are both 0.02, so
conflating them is invisible; and both distance thresholds sit within a factor
of two of a cliff.

**Two claims it re-derived and confirmed independently:** the Al/Au contrast
+0.00618 Å⁻¹ (from the mean |g| of the Al [001] set times the lattice-parameter
ratio, rather than from the harness), and β″'s closest kept pair 0.136774 Å⁻¹
= 2.990 px = 2a*. **One number was stale:** the unit test's "44 640 entries" is
2 × 49 × 360 = **35 280** after the gcd fix.

**What Gate B could not test:** anything on screen, the app's own detection
path, and the method against external truth — which is step 3.

## Gates

| gate | result |
|---|---|
| `run-tests.sh unit` | see `docs/status.md` — reconciled against `func test` in source |
| `tools/phase-vector-matching` | **27** gated checks, exit 0, in `scientific` (21 before Gate B) |
| `run-tests.sh core` | exit 0, both packages |
| `run-tests.sh inventory` | exit 0; AppState + ResultExport under HEAD |
| `run-tests.sh all` | **not run** — it needs 8 GB free and this machine ended at 5.7 |

## A trap paid here

`tools/run-tests.sh` was edited **while a gate was running**, and the running
`inventory` re-read the half-written file and died with `parse error near ';;'`
at a line that was syntactically fine before and after. The gate looked like a
failure of the tree. Do not edit the gate script, or any source it compiles,
while a gate is in flight — the same rule `/adversarial-review` already states
for committing during a refuter's mutation window, for the same reason.
