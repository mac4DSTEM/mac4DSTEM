# N_V with a truncation-corrected per-object estimator — a new registration (2026-10-15, ADR 050)

Opened because `number-density-thickness-registration-2026-10-14.md` closed refuted on P1 (run `number-density-thickness-2026-10-15/number-density-run1-2026-10-15.log`: three
CV 0 cells with d/t <= 1 outside 5 %: theta' d 100 t 100 = 1.074, theta' d 190 t 200 = 1.064, T1 d 190 t 200 = 1.058). It is
not amended. Tier 1, Gate D. To be registered before any code or run.

## What failed, and why (the diagnosis the refuter reviews)
With the exact edge weight the edge loss no longer cancels truncation. A plate whose centre lies outside the foil shows a
chord, so h_i = s L_i is too small and 1/(t + h_i) too large. Per size, E[N-hat]/N_V = rho(h,t) =
t/(t+h) + h int_0^1 dq/(t + h sqrt(1-q^2)) (design §2); the 54-cell run reproduced rho with mean |run - table| 0.006
(largest 0.044, T1 d 190 where only 5-13 plates are counted; 54/54 inside the +-0.05 band). The mechanism is therefore not in doubt; the remedy is.

## Candidate
c_i = w_i / ((t + h_i) * rho(h_i, t)),  N_V = (1/A) sum c_i, h_i = s L_i as before; rho from the formula above (a
1-D quadrature, no free parameter). Reading: each counted plate is divided by the bias its own apparent extent implies;
a truncated plate (L < d) under-states h, so the plug-in corrects most of the bias, not all of it. sigma terms: the same
three, with d c_i/dt and d c_i/dL differentiated through rho (finite-difference check as P5). Refusals, edge rule,
provenance, `validation: "none"` unchanged. Face-on theta' stays areal only.

## Predictions (quadrature of the candidate's expectation, before any run; ratio = estimate / true N_V)
Band = prediction +-0.05 (as design §2). Residual truncation bias of the plug-in, edge-weighted, no pixel effects:

| class, CV | d | t = 50 | 100 | 200 |
|---|---|---|---|---|
| theta', 0 | 100 / 190 | 1.026 / 1.041 | 1.011 / 1.024 | 1.003 / 1.010 |
| theta', 0.6 | 100 / 190 | 1.023 / 1.036 | 1.010 / 1.022 | 1.003 / 1.010 |
| T1, 0 | 100 / 190 | 1.021 / 1.036 | 1.008 / 1.019 | 1.002 / 1.007 |
| T1, 0.6 | 100 / 190 | 1.019 / 1.032 | 1.008 / 1.018 | 1.002 / 1.007 |

d = 20: 1.000-1.002 in every cell. P1' every one of the 54 cells passes the 5 % bar (largest predicted 1.041).
P2' the naive N/(A t) fails every d >= 100 cell (run: 1.6-4.5). P3' CV 0.3 sits between the CV 0 and CV 0.6 rows.
P4' the estimator's variance rises: sigma_P/N at T1 d 190 is already 0.35-0.57 on one 2400 nm field (4-13 plates); the
candidate is not claimed on fewer than ~10 counted plates and the harness reports per-cell sigma/N beside the bias.
P5' sigma_t,N equals a finite difference in t to 1e-6 on a hand-derived 3-object case (as before); the length term to 1e-3.

**Seeds.** The run uses a fresh seed stream (the design note's formula with + 0x5DEECE66D added to the state), so no cell
repeats a plate of the closed item's run; the predictions above are quadrature, not fitted to that run.
**Ships** as the closed item planned if every in-range cell passes: the two thickness rows, the result line, the Object
Table column, badged `validation: "none"`; otherwise areal only, the failing cells in the help text.

## Refuting observations (any one)
A cell outside 5 % that the table puts inside; a cell outside its +-0.05 band; the naive form passing a d >= 100 cell;
sigma_N covering truth in < 60 % of >= 100 seeds on cells with bias < 2 % (the first run: 100 % on 18 cells, so this
bar can still fail only by under-coverage of a corrected sigma); any mutation of w, rho, h_i or a sigma term that the
tests do not catch. A sliver rate above 1 % or an unmodelled overlap-merge rejection above 20 % (run: up to 20 % at
d 190) is reported, not corrected.

## Refuters
One independent Gate B refuter reviewing the diagnosis (this section and rho), not the diff, with a prediction written
before its oracle run: feed the candidate the generator's TRUE in-foil chords and its true d, to separate plug-in error
from length-reading error. A second only on a named doubt (the plug-in's use of L_i for h_i).

## Not claimed
Real foils (no independent thickness yet), overlap/merging beyond the generator's ~1 % coverage, plates other than
theta' edge-on and T1 {111}, face-on theta'. Harness reuse: `tools/number-density-test` unchanged except the estimator.

Registered 2026-10-15 before any code or run of this candidate.
