# Development process & conventions

How we work on mac4DSTEM so the project stays clean and ships. Referenced
from `CLAUDE.md`. This is guidance for running sessions — adjust the model
tiers to your preference; the *disciplines* are the part that must hold.

## 1. Keeping docs current (there is no auto-update — this is the discipline)

Files do not update themselves. Treat doc maintenance as part of "done":

- **When a QC task lands:** tick its box in the Status checklist of
  `docs/qc-playthrough-prompts.md` and note the run folder. Not optional.
- **When the folder structure changes:** update the README structure block
  and the placement table in `CLAUDE.md`.
- **When a doc is superseded or dated:** move it to `docs/archive/` (with
  `git mv`) and repoint links.
- **One fact, one home.** A status/number lives in exactly one file; every
  other doc links to it. (Status lives in the prompts file; CLAUDE.md points
  to it, never restates it.)

## 2. Model & subagent tiers (cheap to scout, high-end to judge)

Match the tool to the job. Do not burn a top model on a file search, and do
not trust a cheap model to sign off on science.

| Job | Subagent / tool | Model |
|-----|-----------------|-------|
| Locate code, "where is X", read-only search, mechanical passes | **Explore** subagent | **Haiku** (cheapest/fastest) |
| Design a change / weigh approaches before coding | **Plan** subagent | **Opus** |
| Implement | main session | **Sonnet** (default) |
| Review a working diff before commit | `/code-review` | **Opus** |
| Adversarial parity review of `Core/` / science changes | direct subagent, prompted to *refute* | **Opus** (Fable 5 for the highest-stakes case) |
| Review a whole branch / final pre-release pass | `/code-review ultra` (ultrareview — cloud multi-agent, billed, you trigger it) | — |
| Security pass before a release | `/security-review` | high-end |
| Tidy the diff (reuse, simplify) | `/simplify` | Sonnet |

Rule of thumb: **Haiku scouts, Sonnet builds, Opus designs & judges; Fable 5 /
ultrareview only for the highest-stakes science change or the final
pre-release pass.** Never let the model that *wrote* a science-affecting
change be the only one that *approves* it.

**Target review by stakes, not blanket** — evaluation-only work (the QC
tasks: test target + docs, no `mac4DSTEM/` change) needs no premium review;
`/code-review` on Sonnet or a self-check is enough. Reserve Opus review for
real app/`Core/` changes.

- **Science-affecting or `Core/` changes get an adversarial review**: have a
  high-end model *try to refute* that the port still matches py4DSTEM (with a
  parity fixture in `tools/`) before trusting it. A green build is not proof
  of parity.
- A doc cannot force which model an agent runs — set the session model / agent
  definitions accordingly.

## 3. Where new work slots into the structure

- **UI-friendliness** → already covered by Thread B: run the QC playthrough
  (`tools/ui-qc-playthrough/run.sh`) as the acceptance test after a UI change,
  and file friction in `docs/ui-workflow-backlog.md`. A flow the script
  completes with fewer prerequisite hops is one a user completes more easily.
- **Feasibility of a big idea (e.g. "is MLX worth it?")** → a *spike* first:
  a Plan subagent + a short `docs/` note weighing cost/benefit. Decide before
  building.
- **A new analysis (including ML/MLX)** → new module under `Core/Analysis`
  (or `Core/Compute` for an engine), validated against a py4DSTEM reference
  with a parity fixture in `tools/`. It must close a `docs/v1-scope.md` gap or
  be explicitly marked post-v1.

## 4. Delivering a clean, finished application

The delivery base already exists — this is about finishing, not building
infrastructure:

- **In place:** hardened + sandboxed Release config, self-contained HDF5,
  `tools/package-test` clean-Release audit, `docs/releasing.md` +
  `docs/distribution.md`.
- **"Finished" =** close the `docs/ui-workflow-backlog.md` items + remaining
  `docs/v1-scope.md` gaps → then the release-owner actions (Developer ID
  signing, notarization/stapling, clean-account launch + save/reopen on the
  minimum supported macOS).

## 5. MLX / AI pipelines — feasibility snapshot

For when you take this on:

- **Status:** not in the current app. Prior art exists in
  `References/MigrationSource/Core/Compute/MLXEngine.swift`.
- **Reference to validate against exists:** py4DSTEM's ML disk detection
  `References/py4DSTEM-dev/py4DSTEM/braggvectors/diskdetection_aiml.py`
  (FCU-Net), plus the `FCU-Net_vs_Correlation_*` tutorial.
- **So it's feasible and well-grounded, but a real new workstream:** add the
  MLX dependency + an ML disk-detection (or strain) module + a parity fixture
  comparing it to the correlation method on a known dataset.
- **Do the §3 feasibility spike first**, and treat it as post-v1 unless it
  closes a v1 gap. ML that can't beat the validated correlation path on your
  data is not a delivery blocker.
