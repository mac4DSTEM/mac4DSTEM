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
