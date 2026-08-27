---
name: adversarial-review
description: Run mac4DSTEM's Gate B adversarial review on a science-affecting or Core/ change. Use whenever a change touches Core/, calibration, py4DSTEM-ported math, or anything that could alter a scientific number — before it is called done, and always when a session brief names Gate B. Never let the model that wrote such a change be the only one to approve it.
---

# Gate B — adversarial review + fixture

The rule: a separate agent briefed to REFUTE, plus a `tools/` fixture.
Twice a fix here passed every test written for it — including one verified
to fail without it — and was still wrong. The reviewer's job is not
approval; it is refutation, and a review that finds nothing must say what
it *tried* and failed to break.

1. Spawn a fresh agent — never the one that wrote the change. Its brief:
   refute that the change matches py4DSTEM (source-locked in
   `References/py4DSTEM-dev`; cite file:line) and that its stated claims
   hold. Hand it the diagnosis and the primary evidence, not just the diff
   — review the diagnosis, not only the code.
1b. **When the change IS the fixture, ask the one question that pays:
   "what transformation of the app's code leaves every check green while
   producing wrong science?"** Name it explicitly in the brief and require
   the reviewer to actually apply and run its candidates. On 2026-08-19 that
   single question produced the two best findings of the S2 review — a
   vertical flip of the binned detector output, and a constant bias in the
   measured origin, both invisible to a harness of 201 checks. "Does the
   fixture look thorough" produces nothing; "here is the mutation that
   survives it" produces the missing assertion. Watch in particular for a
   check that is *vacuous on this fixture* — comparing background to
   background — and require an anti-vacuity guard rather than a comment.
   Mutation-passing suites can also be collectively blind at symmetric test
   constants — pin sign-discriminating angles (37.2°, not 90°) and prove the
   wrong variant differs on the fixture (`docs/development-process.md` §2,
   the S8 lesson).
2. The fixture lives in `tools/` and joins `run-tests.sh scientific` when
   it should gate. Ground truth is analytic or py4DSTEM itself — never the
   code under test's own output. Self-consistency proves nothing: the L3
   harness passed a transposed decode because both sides transposed
   together.
3. Negative controls: each one names the line it breaks and why the failure
   follows. "It went red" is not evidence — L4 carried a control everyone
   believed had teeth, and it could not fail.
4. Port deviations from py4DSTEM get an inline `DEVIATION` note with the
   reason (repo hard rule).
5. Record what the review could and could not refute. A claim the review
   corrects gets corrected in the docs — not defended.
