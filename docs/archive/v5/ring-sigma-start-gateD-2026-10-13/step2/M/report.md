# Lane M report — ring-fit Gate D step 2: P3 / R2 / P4 / P6 on plant sets A and B (2026-10-14)

Record: docs/archive/v5/ring-sigma-start-gateD-2026-10-13.md (registered at e402373b; step 1 at 58d4e2ac).
Variants: head, a (half-maximum ring-sigma start), b (refuse ring sigma <= 0.30 px), ab (both). Harness: scan-{head,a,b,ab}
(harness/scan/main.swift), 275 plants per set, tier `all`. "Wrong" = accepted profile fit off by > 1 % in (a+b)/2;
"right" = within 0.1 %. Rescued (my definition for R2) = accepted profile within 1 %.

## Predictions (copied verbatim from the record, written before any variant run)

- R2: a ring-sigma start read from the seed (below) rescues fewer than 90 % of them, or turns a right fit wrong.
  (refuting observation; R2 is refuted/does-not-hold if >= 90 % rescued and no right fit turns wrong — see my definition above)
- P3, candidate (a), the ring sigmas started from a width measured on the seed ellipse's radial profile (half maximum,
  no truth): 0 such fits on both sets; no fit within 0.1 % before is outside it after; on macTEM's 84 clean plants and
  `tools/ellipse-calibration-test`'s 48-ring sweep and existing cases, no model choice is lost and every profile fit kept
  both ways moves by <= 0.01 % of R in (a + b)/2 and <= 1e-3 rad in θ.
- P4, candidate (b), a profile fit with a ring sigma ending within 0.05 px of its bound is refused (the fit falls back to
  the conic): it catches >= 10 of the P1 fits and refuses no fit that was within 0.1 %.
  (as built in step 2: refuse a smaller ring sigma <= 0.30 px; lower bound only)
- P6, both (a + b): 0 accepted profile fits off by > 1 % on either noisy set; no fit within 0.1 % before is refused
  or outside it after; on the clean sets and the 48-ring sweep, as P3.

Lane-brief restatement of what this lane decides: P3 wrong count 0 on both sets (a); fits within 0.1 % on head not
accepted-profile-within-0.1 % on a: none; R2: of head's wrong fits >= 90 % rescued, no right fit turned wrong;
P4 (b): refuses >= 10 of head's wrong fits on each set, refuses 0 of head's within-0.1 % fits; P6 (ab): 0 wrong,
0 head-within-0.1 % fits refused or outside 0.1 % on ab. Clean tier: no model choice changes; kept-both-ways profile
fits move <= 0.01 % of R in (a+b)/2, <= 1e-3 rad in theta. The 48-ring sweep is lane T's, not run here.

## What was run

- 8 runs, tier `all`, 275 plants each, run concurrently: logs/{head,a,b,ab}_{A,B}.log (exit files logs/*.exit all 0, 275 ROW lines each).
  Binaries: harness/bin/scan-{head,a,b,ab} (not rebuilt). Plant sets data/plantsA, data/plantsB.
- compare.py (stdlib python3) joins the variants per plant name; its full output is compare-out.txt; every number below is from it.
- Reproduction check first: head noisy tier, accepted profile fits off by > 1 %: set A 35, set B 32 (step 1: 35 and 32). Reproduced.
- Not run in this lane: the 48-ring sweep and existing cases of tools/ellipse-calibration-test (lane T), the Au_ref P5 (lane P5),
  the fixture (lane F), any refuter. The clean-tier clause of P3/P6 is therefore decided here only on the 84 clean plants.
- Clean, printed and refusal tiers are byte-identical files in sets A and B (md5 checked: all 84 clean, all 38 printed, all 9
  refusal plants; only the 144 noisy plants differ). Their results are one measurement, shown twice in compare-out.txt.

## Results

Noisy tier (144 plants per set). Wrong = accepted profile fit off by > 1 % in (a+b)/2.

| variant | set | profile / conic / threw | wrong | max abs dR | max abs d(b/a) | max dtheta (eps>0) | max centre err |
|---|---|---|---|---|---|---|---|
| head | A | 128 / 16 / 0 | 35 | 48.42 % | 0.508 | 1.564 rad | 34.83 px |
| head | B | 125 / 19 / 0 | 32 | 42.81 % | 0.468 | 1.460 rad | 40.29 px |
| a    | A | 144 / 0 / 0 | 0 | (all within 0.107 % incl. conics) | 0.0033 | 0.113 rad | 0.130 px |
| a    | B | 144 / 0 / 0 | 0 | (all within 0.099 %) | 0.0035 | 0.154 rad | 0.159 px |
| b    | A | 113 / 31 / 0 | 20 | 22.75 % | 0.508 | 1.480 rad | 34.83 px |
| b    | B | 109 / 35 / 0 | 16 | 25.82 % | 0.468 | 1.372 rad | 40.29 px |
| ab   | A | 144 / 0 / 0 | 0 | identical to a | | | |
| ab   | B | 144 / 0 / 0 | 0 | identical to a | | | |

(The a rows give the worst error over every returned fit; the app applies the fit whichever model it is.)
ab equals a on all 275 plants of each set (0 of 275 differ in status, dR or dtheta): once a's start is in, b's refusal never fires.

### R2 (a rescues >= 90 % of head's wrong fits, turns no right fit wrong): HELD on both sets
Rescued = accepted profile within 1 %. Set A: 35 of 35, all 35 within 0.1 %. Set B: 32 of 32, all within 0.1 %.
No right (<= 0.1 %) head fit turned wrong, and no head profile fit within 1 % turned wrong, on either set. (compare-out.txt section (c).)

### P3, candidate a
- 0 wrong fits on both sets (pred 0): HELD (A 0, B 0; a returns 143 within 0.1 % plus 1 at -0.107 % on A, 144 within 0.1 % on B; that one A plant, noisy-512x512-r80-e0-tNA-g60-s10-p2, is the same -0.107 % fit on head).
- No fit within 0.1 % on head is outside it on a: HELD. Head accepted-profile fits within 0.1 %: 92 (A), 93 (B); lost: 0 and 0.
  With the registered wording (any status, so head's conic fits count) 97 and 101 head fits within 0.1 %, 0 outside after. No tier
  (clean, printed, refusal) has a head fit within 0.1 % that is outside it on a.
- Clean-tier clause (84 clean plants): NOT HELD as the lane brief states it, and NOT HELD for the movement bound.
  - Model choice: 25 of 84 clean plants change model, all conic -> profile (head's "residual over cap" fallbacks, residuals 0.235-0.336);
    0 are lost (profile -> conic). The record's wording "no model choice is lost" holds; the brief's "no change" does not.
  - Movement of the 59 profile fits kept both ways: max change in (a+b)/2 = 0.131 % of R (pred <= 0.01 %), 10 plants over 0.01 %;
    max change in theta (eps>0) = 0.128 rad (pred <= 1e-3), 7 plants over 1e-3; max centre change 0.110 px.
    The 10 movers are 7 gap-60 r80 plants and one gap-60 r200 (eps 0) plant, whose fit cost on the pixels falls to x0.90-0.91 on a (lower or equal on all 10), and 2 gap-0 r80
    e3-t112.5 plants that become exact (cost ~0, |dR| 0.019 % -> 0.000 %). Against truth, a is closer in |dR| on 6 of 10 but closer in theta
    on only 2 of 9 (eps>0; the two are the gap-0 plants): on all 7 gap-60 eps>0 plants theta error goes from 0.001-0.027 rad to 0.011-0.155 rad, |d(b/a)| from <= 0.0005 to <= 0.0033, centre error from ~0.02 px to ~0.12 px.
    I do not claim a mechanism; the observation is that the lower-cost optimum is farther from the planted geometry on these partial-ring plants.
  - The 25 conic -> profile plants against truth (head conic | a profile): mean |dR| 0.073 % | 0.017 % (a closer on 25 of 25), but max |d(b/a)| 0.00017 | 0.0016,
    max theta error (eps>0) 0.0098 | 0.078 rad, max centre error 0.025 | 0.086 px.
  - Noisy plants right on both head and a (92 / 93): max change in (a+b)/2 0.0146 % / 0.0139 % of R, theta 0.0017 / 0.0019 rad (informational; also slightly over the clean bounds).
  - The 48-ring sweep and existing cases: not run here.
- 16 (A) and 19 (B) noisy plants that head returned as conic (fallbacks) are returned as profile fits on a, all within 0.03 % (A) / 0.01 % (B), max:
  mean |dR| 0.187 % -> 0.007 % (A), 0.150 % -> 0.0025 % (B).

### P4, candidate b
- Refuses >= 10 of head's wrong fits: HELD on both sets: A 15 of 35, B 16 of 32 (all refusals carry the ring-width reason).
  The refusals are exactly head's profile fits with min(sin, sout) <= 0.30 px on all 275 plants of each set (set equality checked).
- Refuses no fit that was within 0.1 %: HELD: 0 of 92 (A), 0 of 93 (B); also 0 of the head mid fits, 0 in any other tier; b changes none of the 47 printed/refusal plants,
  none of head's conic plants, and none of the 84 clean plants (b is bit-identical to head there).
- What b does not do (not a registered prediction): 20 of 35 (A) and 16 of 32 (B) wrong fits stay accepted, bit-identical to head, with live ring sigmas
  (smaller ring sigma 2.1-23.9 px (A) / 2.1-6.4 px (B), I1/dyn 0.061-0.595 (A) / 0.056-0.571 (B)) and errors up to 22.7 % (A) / 25.8 % (B) in R, 0.51 / 0.47 in b/a, 35 / 40 px in centre. And 3 (A) / 4 (B) of the refusals fall back
  to a conic that is itself > 1 % off (max 1.23 %), 12 / 12 to a conic within 1 %.

### P6, both (a + b)
- 0 wrong fits on both sets: HELD (A 0, B 0).
- No head fit within 0.1 % refused or outside 0.1 % on ab: HELD (0 of 92, 0 of 93; 0 under the registered wording).
- Clean-tier clause: same result as P3 (ab is bit-identical to a): model choice 25 of 84 changed (all conic -> profile, none lost), movement 0.131 % of R and 0.128 rad: NOT HELD as stated.
- 48-ring sweep: not run here.

### Printed and refusal tiers (not decided, printed)
a and ab differ from head on 7 of 47 plants (same 7 each; b on 0): annulus-20-e1-t20 (conic +0.109 % -> profile 0.000 %), annulus-40 (profile +0.142 % and +0.018 % -> 0.000 %),
neighbour-1.155 (profile -0.277 % and -0.259 % -> +0.050 % and +0.024 %), radius-40 (profile -0.045 % and -0.051 % -> 0.000 %). All seven move closer to truth in dR.
The 9 refusal plants return the same result (same error or same model) on all four variants.

### Wrong fits that remain (noisy)
a and ab: none on either set, so there are no sin/sout/I1/cerr to report. The 20 + 16 that remain on b are listed with sin/sout/I1/cerr in compare-out.txt section (h).

## Predictions that did not hold, plainly
1. P3's and P6's clean-tier clause, as the brief states it ("model choice changed — pred none"; movement <= 0.01 % of R and <= 1e-3 rad): not held. 25 of 84 clean plants change from conic to profile (none lost); 59 kept profile fits move up to 0.131 % of R and 0.128 rad.
2. Nothing else in R2, P3 (noisy), P4 or P6 (noisy) failed on either set.

## Surprising or worth the owner's attention
- (a) does more than rescue the 35 / 32: it also turns every head conic fallback on the noisy tier (16 / 19, mostly "residual over cap") into a right profile fit,
  so the residual-cap fallback never fires on any of the 288 noisy plants under a. The cap is therefore not exercised by these sets under a; the refusal tier (9 plants) is unchanged.
- Head's 25 clean conic fallbacks (residual 0.235-0.336 on noise-free rings) are start-trap local minima, not noise-inflated residuals: a's start escapes all 25.
- On seven clean gap-60 r80 plants a reaches a ~10 % lower cost yet a theta and centre farther from truth than head (above). Whether that matters depends on whether the app's users need theta at eps ~ 0.01; the applied b/a error there is <= 0.0033 against an ellipticity of 0.01.
- Wall time: a and ab finished their 275 plants in about 155-160 s, head and b in about 243-247 s (all 8 started together on a shared machine; indicative only).
- b alone catches 15 / 16 of the 35 / 32 and leaves the drifting kind; only the ring-sigma start (a) removes them. ab adds nothing over a on these sets.
