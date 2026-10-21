---
name: adversarial-review
description: The one review a mac4DSTEM change gets before it is committed, by a second lane (Sonnet) that did not write it. Use whenever a change touches Core/, calibration, py4DSTEM-ported math, or anything that could alter a scientific number, and before any commit of such a change.
---

# One review by a second lane

The suite process (`../CLAUDE.md`, "How we work") replaced Gate B on 2026-10-15: one review per change, correctness, the tests and the docs touched. For a change that can move a scientific number the reviewer's job is still refutation, not approval; a review that finds nothing says what it tried and failed to break.

1. Spawn a fresh lane (Sonnet), never the one that wrote the change. Hand it the diagnosis and the primary evidence (logs, fixture output), not only the diff. Brief it to check the change against the pinned py4DSTEM (`References/py4DSTEM-dev`, cite file:line) and the claims in the commit message and docs.
2. Ask the one question that pays: "what transformation of the code leaves every test green while producing wrong science?" Have the reviewer apply and run its candidates (a flipped axis, a constant bias, a transposed decode). Watch for a check that is vacuous on its fixture (background against background) and for a suite blind at symmetric constants: pin sign-discriminating values (37.2 degrees, not 90).
3. Ground truth is analytic or py4DSTEM, never the code under test's own output; self-consistency proves nothing (a transposed decode passed because both sides transposed). Tolerances are written per function and not widened to hide a bug (`CLAUDE.md`, Numbers).
4. Break the reviewer's proposed remedy before trusting it: a recommendation is a hypothesis.
5. A claim the review corrects is corrected in the docs, not defended.
6. A reviewer that mutates the tree makes the tree dangerous to commit: stage named paths, never `git add -A`, read the diff you commit, and while the change under review is uncommitted give the reviewer byte copies to restore from instead of `git checkout`, `restore` or `stash`.
