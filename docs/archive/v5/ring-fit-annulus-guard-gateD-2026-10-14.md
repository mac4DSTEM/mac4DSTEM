# A ring fitted outside its annulus — the annulus guard, Gate D (registered 2026-10-14)

ADR 069 (card M3, the owner's **b**): after two starts and the floor guard land, this item registers the one failure they
leave on the owner's data. Tier 1 (the b/a and θ the app applies to every Bragg vector can move). Registered before any run;
the Results section is added after. Nothing lands without its gate and a card if it changes the owner's numbers.

**Trigger.** Gate D: a defect observed on real data whose cause is established only by one case.

**Diagnosis (to be refuted).** On the Au_ref mean pattern, annulus [29, 39] px, the profile fit returns a = 57.6, b = 55.0
px (mean 56.3) with its inner ring σ at the 2 × outer ceiling (78 px) and b/a 0.955 against 0.971–0.985 on the pattern's
other annuli (`ring-fit-two-start-gateD-2026-10-14/step-i/runs/au-head.log`): the ring term has left the annulus the user
drew and fits something outside it, so a, b and θ say nothing about the ring inside. The residual cap (0.078 against 0.22)
and the floor guard do not refuse it; two starts keep it. The trap set's brighter-neighbour rings land outside their
annulus the same way (step 2's refuter, +75 % at the axis ceiling).

**The candidate (g):** inside `refine(start)`, after the floor guard, refuse a profile fit whose mean radius (a + b)/2 lies
outside [inner, outer], the annulus the fit was given (`ringOutsideAnnulus`); the Fit falls back to the conic, or refuses
when the conic is over its 0.2 cap. No threshold to set.

**Refuting observations** (any one refutes):
- R1: on the step (ii) sets (2009 rows), cb + g refuses a fit cb returns within 0.1 %.
- R2: on the real sources — step (i)'s annuli and step (ii)'s refuter's 726 shifted annuli — cb + g refuses a fit whose b/a
  lies within the source's spread of unflagged fits (Au_ref 0.971–0.985 at step (i)'s annuli).
- R3: cb + g does not refuse Au_ref [29, 39].

**Predictions:** P1 cb + g refuses Au_ref [29, 39] and nothing else on step (i)'s real annuli; P2 0 right fits refused on
the 2009 rows; P3 wrong ≤ cb's 79 and accepted b/a errors > 0.01 ≤ cb's 59; P4 `ellipse-calibration-test` passes; P5 on the
shifted annuli every refusal is a fit with its mean radius outside its annulus by construction, and none agrees with its
source's unflagged b/a spread.

**Sets and gates.** As step (ii) of `ring-fit-two-start-gateD-2026-10-14.md` (A, B, C, P, N, T, S3, S4; the real sources;
the tool), plus the shifted annuli; variants cb (landed by then) and cb + g. A fixture plant whose profile ring leaves its
annulus (synthetic: the Au_ref data are the owner's), red on cb; unit + core; a fresh refuter.

## Results (2026-10-14 night; `ring-fit-annulus-guard-gateD-2026-10-14/` — `g.patch`, `src/`, `logs/`, `analysis.txt`)

Lane AG (Sonnet) built cb (HEAD `88e12743`, ADR 069 as landed) and cb + g (`g.patch`: `FitError.ringOutsideAnnulus` after the
floor guard in `refine(start)`) in isolated copies and ran step (ii)'s harnesses on every set, the real sources at step (i)'s
annuli, RF3's 726 swept annuli and the 50-annulus shifted grid (40 runs, every exit 0). cb reproduces the committed rows
(wrong 79, right 1814, right lost 11, b/a > 0.01 59, refused 19; 1944 of 2009 rows byte-identical, the other 65 differ in
unscored fields only).

| over 2009 rows | cb | cb + g |
|---|---|---|
| wrong (> 1 %) | 79 | 68 |
| right (≤ 0.1 %) | 1814 | 1815 |
| right lost against HEAD | 11 | 11 |
| accepted with b/a off > 0.01 | 59 | 52 |
| refused | 19 | 20 |

- **P1 held:** at step (i)'s annuli g changes only Au_ref [29, 39]: cb's profile fit (mean radius 56.3, b/a 0.9545) becomes
  the conic (32.8, 0.9855).
- **P2 held:** 0 right fits refused. **P3 held:** wrong 68 ≤ 79, b/a > 0.01 52 ≤ 59 (26 rows change: 22 in P, all wrong under
  cb; 1 in N, wrong → right; 4 T-neigh traps; one new refusal, a P plant cb had 33 % wrong).
- **P4 held:** `ellipse-calibration-test` all passed under cb + g.
- **P5 not held:** of the 776 shifted annuli g changes 10, each to the conic: 7 Au_ref A4/W4 (cb b/a 0.949–0.966, outside
  the source's spread), and 3 WS2 mean-pattern R2 annuli ([26.5, 32], [27.5, 32], [28.5, 32]) whose cb fit has mean radius
  32.7–33.2 px against outer 32 px **and b/a 0.9996–0.9997, inside WS2's 0.9979–0.9998**. Those three cb fits carry their
  outer width at the 64 px ceiling (`sout=64`; one inner width at the 0.25 px floor); the conic seed (31.6 px) lies inside.
- **R2 met as worded** (a refused profile fit whose b/a lies within its source's spread), so **g is refuted as registered**;
  R1 and R3 not met. The fixture (`test.patch`) and the gates were not run: a refuted candidate does not land.

**Outcome.** Nothing lands; the item closes (ADR 050). What it showed: a mean-radius check catches the Au_ref ring outside
its annulus and every P and T case it touched, but on WS2 it also replaces fits that sit just past the outer radius with a
width at its ceiling — fits whose b/a agrees only because the pattern is near-isotropic, which R2 did not separate. A new
item (a margin, or the width-at-ceiling flag, registered against fresh plants) is the owner's call: card on the board.
