# ACOM zone-axis excess — the nine refuted hypotheses, archived 2026-09-16

Moved out of `open-items.md` at the 2026-09-16 closeout: the entry had grown to
141 lines against that file's own ≤ 20-line rule, and the file is loaded by
every session. The live finding, and the one experiment still worth running,
stay there. This is the record behind it.

### ACOM returns a zone axis up to 12.8° beyond what its bank forces — MEASURED 2026-09-15
**Science, live, no fix, cause narrowed to the score itself. One entry for the
whole investigation** — the separate "bank predicts rings the demo cube cannot
contain" entry is folded in here.
**Where it started.** The demo cube's grain A is aluminium exactly on [001] and
the matcher returned a template 3–5° away. An independent refuter established
that the cube's exporter writes reflections at kMax 0.9
(`tools/demo-dataset/export_reflections.swift`) while the bank is built at 1.2
(`AppState.swift`), so the bank predicts two rings the data cannot contain —
and on an IDEAL complete plant the offset is 0.000°. That is inherited from
py4DSTEM, not a port bug: a transcription of theirs picks the same template.
**The "one `tools/` line" (export at 1.2) is refuted by geometry, 2026-09-15:**
a scratch build of the exporter at kMax 1.2 adds twelve Al [001] reflections
({400} at 0.988, {420} at 1.104 Å⁻¹), and at grain A's 12° rotation none of
them lands on the 128-px detector (half-width 0.762, corner 1.086 Å⁻¹). It
would add two {400} spots in grain B's corners and four weak β″ [010] spots,
nothing on [001], so it cannot move the [001] result and is not taken; the
bank predicting rings past the detector's edge is every real detector's
situation, and the matcher's to handle.
**But it is not the whole story**, because on the cube's own detected peaks no
bank kMax fixes it (0.768, the detector's own reach, leaves grain A at 2.2–6.7°
and makes grain C worse), and the same offsets appear on axes with no phantom
rings at all. So the app has never had a number for how accurately it orients,
and this is that number. `tools/acom-groundtruth/orientation-accuracy.py`
(new, diagnostic) plants known zone axes — reflections from the fcc rule by
hand, the zone by `g·n = 0`, the 2D frame by Gram-Schmidt here, so the plant
shares nothing with the code it gates — and sweeps the in-plane rotation across
two azimuthal bins. 136 patterns, Al, shipped settings.
**The bank is a Fibonacci sampling of the fundamental zone, not a list of
low-index axes**, so part of any error is the distance to the nearest entry the
bank actually holds. That floor is measured from the bank the harness reports
and subtracted; what is left is the defect.

| planted | spots | floor | worst | **beyond the floor** |
|---|---|---|---|---|
| ⟨100⟩ ⟨111⟩ ⟨012⟩ ⟨112⟩ | 6–20 | 0.00–1.09° | = floor | **0.00°** |
| ⟨011⟩ | 22 | **0.00** | 1.88° | **1.88°** |
| ⟨123⟩ | 8 | 0.97 | 3.50° | **2.53°** |
| ⟨122⟩ | 6 | 0.79 | 13.61° | **12.82°** |

So the matcher is exactly as good as its bank allows on half the axes tried,
and on the others it returns an answer up to **12.8° further away than it had
to** — on ⟨011⟩, which is a seeded vertex of the bank and therefore present
exactly. **Which answer you get depends on the in-plane rotation**: ⟨122⟩
alternates 0.8° (the floor) and 13.6° as the specimen turns, and ⟨011⟩ is right
at 3 of 17 rotations and 1.88° off at the other 14.
**This is the same family as the self-recovery failure recorded above** and
probably the same cause; it is separated because this one is measured against
planted truth rather than against the templates themselves, and because it
gives the size. It also explains the demo cube's grain B, which is ⟨011⟩ and
came back 7.0° and 3.6° off.
**THE SCORE PREFERS THE WRONG ORIENTATION — it is not the search.** Measured
2026-09-15 by exposing every template's score (`OrientationMatcher.templateScores`,
diagnostic): at its worst rotation each failing axis has the winner beating the
best available bank entry by a real margin — ⟨013⟩ 0.6 %, ⟨011⟩ 3.5 %, ⟨122⟩
4.9 %, ⟨123⟩ 10.0 %. The search finds the true maximum of the score; the score
is simply higher on the wrong template. That is why every knob failed, and it
means the fix is in what the score measures, not in how finely it is sampled.
**EIGHT HYPOTHESES ARE SPENT, each refuted by its own experiment and each
recorded so nobody retries it:** radial binning; the bank's kMax; the intensity
power; the azimuthal deposition rounding (its py4DSTEM-matching fix improves
how OFTEN but not how BADLY, and makes two axes worse); the azimuthal blur
(reducing it makes three axes worse); more azimuthal bins (fixes most cases at
512–1024, so resolution is a factor but not the mechanism); parabolic
interpolation of the correlation peak (changes almost nothing — which is what
proved the sampling is not at fault); and py4DSTEM's own `power_radial`, whose
default is measurably worse.
**THE MECHANISM IS FOUND (2026-09-15), by looking at the pictures instead of
guessing.** `OrientationMatcher.experimentalPolarImage` and the harness's
`dumpTemplates` now expose the experimental polar image and any template's, so
the inner product the score computes can be read. For a ⟨122⟩ plant at 0.35°
where the matcher is 13.6° wrong, the per-ring correlation peaks are:

| | rings 15–22 peak at shift | rings 25–31 peak at shift |
|---|---|---|
| the TRUE template | 57 | **58** |
| the winner | 13 | 13 |

**The true template's inner and outer ring groups disagree by one azimuthal
bin, so no single shift aligns both.** The score is `max over shift of the SUM
across rings`, so the truth is charged for a misalignment it did not have: at
57 the outer group is a bin off, at 58 the inner group is. The winner's rings
all agree, and wins by 4.88 % while being 13.6° wrong. The cause is the
azimuthal ROUNDING, acting on the RELATIVE phase between ring groups rather
than on any ring alone — which is why every hypothesis that looked at one ring,
one knob or one statistic missed it.
**Demonstrated:** with linear azimuthal deposition the true template's rings
converge on shift 57 and it **wins this case**, 0.56852 against 0.56114.
**But it is not a clean fix, and that is the owner's call.** Across the full
136-pattern sweep, against the bank's own floor:

| | wrong answers | total worst-case excess |
|---|---|---|
| shipped (rounding) | 40 / 136 | 18.79° |
| linear deposition | **28 / 136** | 20.10° |

It cuts wrong answers by 30 % and matches py4DSTEM, removing an undocumented
deviation. It also makes ⟨012⟩ and ⟨112⟩ — exact at every rotation today —
wrong at 2 and 4 rotations, and it does **not** touch the headline 12.82° on
⟨122⟩.
**The regression was chased and is NOT what it looked like.** It clusters at
HALF-bin rotations (⟨012⟩ at 1.40° and 4.20°, against a 2.8125° bin), which
looks exactly like the amplitude error of splitting a spot 50/50 between two
bins. So the azimuth was deposited instead as a **Gaussian centred on the exact
fractional bin** — what the radial axis already does, with the separate blur
pass subsumed — which preserves phase AND shape. It gives the same answer:
30 wrong of 136, and ⟨012⟩ and ⟨112⟩ still regress by the same amounts. The
shape hypothesis is refuted; both variants are reverted.
**And that experiment was run, and refutes the explanation.** The pattern
suggested the regression was the bank's own coarseness — every regressing axis
had a non-zero sampling floor, every zero-floor axis improved — so the sweep was
re-run at **1 000 templates**, where the floors shrink. Linear deposition gets
WORSE, not better: **68 wrong of 136 against the shipped 48**, and ⟨111⟩, exact
at every rotation under both schemes at 200 templates, becomes wrong at 10 of
17. The bank-coarseness explanation is dead.
**A second thing fell out of it, and it is worth more than the hypothesis it
killed: MORE TEMPLATES MAKE ACOM WORSE.** Shipped deposition at 1 000 templates
is 48 wrong and 20.83° of excess against 40 wrong and 18.79° at 200. Raising
the bank is the obvious thing a user or a future session would reach for, and
it is the wrong lever — recorded here so nobody spends a day on it.
**Owner: the deposition fix stands as a trade with no explanation for its own
regression** (30 % fewer wrong answers at 200 templates, two exact axes made
sometimes-wrong, worst case untouched). Take it, leave it, or send it back for
a mechanism. Eleven hypotheses are now spent and every one is written down.
**NINE HYPOTHESES WERE SPENT BEFORE THE PICTURES. The whole-image L2
normalisation was the last of them and it is refuted too:** per-ring L2 on both sides makes the total worse
(⟨122⟩ 12.82° → 12.93°, ⟨112⟩ 0.00° → 2.51°, ⟨013⟩ 1.56° → 2.93°). Reverted.
**So the next step is not another knob, and anyone who reaches for one should
read this list first.** What has never been done is to LOOK at the two polar
images for a failing case: dump the experimental image and both templates —
the winner's and the true axis's — for ⟨122⟩ at a rotation where it fails, and
find what the winner has that the truth does not. The score is a number over
those two pictures; nine attempts to guess the difference have failed, and the
pictures are three lines of harness away (`plan.templates` and the matcher's
`expRe`/`expIm` are already `package`). Until someone does that, a fix is a
guess. The honest statement for a user — good to a few degrees on most axes,
up to 13.6° off on ⟨122⟩ (the total, floor included: a user cannot subtract
the bank's spacing), more templates measured worse — is on the ACOM panel
since 2026-09-15 (a static caption with its date and scope, unverified on
screen); the "Best" preset no longer calls 400 templates the finest sampling.

