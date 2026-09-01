# Interrupted review recovery — 2026-08-31

Status: IN PROGRESS. This record is updated as evidence arrives; it is not a
release approval. Owner explicitly authorized continuation and file edits.

## Scope and baseline

Finish the interrupted v2 code review and session audit, preserve its evidence,
close the demonstrated ACOM projection/matrix coverage gap, prepare the requested
v3 development-process proposal, and give S22 its recovered UX survey.
New app defects are findings for separately diagnosed work, not permission to
silently change the release scope. No commit, push, release, or Track B acceptance
is part of this run.

Baseline: `24c13d3` on `main`, with ten pre-existing modified files. They are
preserved: W4b's second sitting, its docs/skill changes, S22 scheduling, and the
README count correction. No file under `mac4DSTEM/` was modified on entry.

Claude session `a93b966c-6a1e-4d09-92bf-2223042e44b6` stopped at 20:04 CEST.
The seven-agent scope/ACOM/UX survey finished. The code-review workflow completed
11 initial reviews (75 entries), but only two verification passes (nine entries);
nine verifiers and all three session-audit agents failed at the usage limit.
Its “complete” message used the planned area count and its output filtered out
missing results. Completion of the workflow was not completion of its work.
The last README amendment succeeded; the subsequent open-items amendment hit
an assertion before its write. No claim from that failed write is treated as
recorded.

## Gates and evidence protocol

- Review recovery: independent source refutation, with an explicit disposition
  for every original entry, including refuted, narrowed, resolved and unresolved.
  A source-confirmed hazard is not described as a reproduced crash.
- Session audit: inspect checkable claims against code and history. Later changes
  do not refute dated evidence. Missing historical logs mean unverified history,
  not proof that a run never happened.
- ACOM fixture: Gate B. Production science remains unchanged. A different agent
  must attack the independent oracle and run discriminating mutations against
  copies of source, never the shared checkout.
- Track B remains owner acceptance. Recovered code-based UX leads are not scores.

## ACOM experiment registered before adding the gate

**Hypothesis:** the shipping projection convention is internally correct, but
the existing matching fixtures cannot detect a shared projection error because
they synthesize input through the production projector. The earlier survey's
independent probes support this hypothesis; it is not a newly discovered app fix.

**Refutation:** the shipping matcher fails independent orientation truth, or the
new fixture accepts an x/y projection swap, a y reflection, or substituting the
wrong template basis into the exported orientation matrix.

**Predictions:** analytic FCC Au and hexagonal WS2 patterns built from a local
right-handed basis (not `OrientationPlan.project` or `detectorBasis`) recover
orientations near the sampling floor. The retained probe measured median
misorientation 1.25° (Au) and 0.79° (WS2). Its generic cases number 144 and 240.
Frozen py4DSTEM 0.14.17 patterns give a separate cubic cross-check with median
2.06°, with substantial outliers explicitly retained. This is convention
coverage, not a universal ACOM accuracy claim and not equivalence to the newer
vendored reference version.

The gate bounds will be written before its first run: analytic medians <3°
(Au), <2° (WS2); at least 120/144 Au in-plane errors <20° and every WS2 case
<20°; frozen py4DSTEM median <5° and at least 24/40 within 5°. These are regression
discriminators informed by the retained control/mutant separation (mutant
medians 31–63°), not scientific acceptance thresholds for user datasets.
Every case must execute, return a finite proper rotation, and carry nonempty
peaks. No failed match may be skipped. The independent oracle itself will have
identity/symmetry/non-equivalence checks.

## Results and remaining work

Pending: remaining source refutations, session audit, ACOM gate and mutations,
Gate B, documentation integration, applicable test runs and final closeout.

Not verified: app visuals, clean-account acceptance, all unscheduled defect
reproductions, release signing/notarization, and the external living board.
