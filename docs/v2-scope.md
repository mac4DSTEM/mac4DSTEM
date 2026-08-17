# mac4DSTEM v2 — priority, refusal rule, and the decisions behind them

**Decided 2026-08-17** in the phase-2 planning session. Supersedes
`docs/v2-planning-draft.md`, which was written 2026-08-06 as a set of proposals
and is now deleted; every proposal in it was accepted, changed, or rejected
here.

**Why this file is not shaped like [`docs/v1-scope.md`](v1-scope.md).** That was
a *freeze*, and its job was to defend a release date by saying no. There is no
date to defend now. Copying its shape would manufacture a constraint that does
not exist and would make "is this in scope?" a paperwork question instead of a
real one.

So this is a **priority order plus a refusal rule**. The order decides what a
session picks up. The refusal rule is the only part that actually says no — and
it is not about features.

---

## 1. What v2 is aiming at

> *An analysis validated on a cropped, binned view re-runs unchanged on the full
> dataset, with every calibration re-referenced for you.*

That is the release owner's own workflow, stated 2026-08-06: today, in py4DSTEM,
you bin a 50–60 GB cube, work out the analysis locally on the binned file, then
take the notebook to the HPC and re-run on the full dataset — *"which usually
involves resetting values for the centre of the diffraction patterns, etc."*
That manual re-referencing step is the thing the app removes.

It is a genuine advantage over the reference implementation, and it is
**testable**: same analysis, two load specifications, compare. It needs L2
through L6 to be true, which is why the load pipeline is the phase's spine
rather than one feature among several.

---

## 2. Priority order

A session opening cold takes the highest band with work left in it.

### A — The load pipeline (L2 → L6)

[`docs/load-pipeline-plan.md`](load-pipeline-plan.md) is the executable plan and
the single source of truth for its status. Sized at **9–11 sessions**, which is
realistically the whole phase. This band gets the sessions.

### B — Verification debt

The claims this repository makes that a reader cannot currently reproduce.
This band exists because the repo went **public on 2026-08-14**, and a
verification claim that fails on the current OS costs credibility with exactly
the people who check it. Live items are in
[`docs/open-items.md`](open-items.md) under *Verification debt*; the two that
matter most are the `README.md` / `CHANGELOG.md` "exit 0, 30 harnesses" claim
(true at the tag, red today on macOS 27) and the absence of any visual
acceptance baseline.

### C — UI/workflow backlog

[`docs/open-items.md`](open-items.md) under *Known, scoped, not blocking*.
**This band does not compete with A** — it touches no `Core/` and no
`AppState` scientific state, which is exactly what makes that list safe to hand
out as implementation prompts. It is legitimate filler for a session that
cannot start an L-stage, not a reason to delay one.

### D — Deferred until after L6

A second *science* workstream is the only thing that genuinely competes with A:
not for files, but for fixture campaigns and adversarial-review capacity, which
are this project's scarce resources. See §3.

---

## 3. What is deferred, and what would open it

Named with entry conditions, so picking one up later is cheap rather than a
fresh investigation.

| Deferred | Entry condition |
|---|---|
| **WS₂ crystal model (#11)** — blocks `polycrystal_2D_WS2` from ever reaching ACOM | The full model contract in `ROADMAP.md` P1.3: explicit lattice, atomic basis, symmetry reduction, structure factors, an expected-orientation fixture, and fit-overlay acceptance. Constraints already captured in [`docs/post-v1-ideas.md`](post-v1-ideas.md). Not a model file — a campaign. |
| **ML / MLX disk detection** | The feasibility spike in `docs/development-process.md` §3 *first* — a Plan subagent and a short `docs/` note weighing cost against the validated correlation path. Prior art: `References/MigrationSource/Core/Compute/MLXEngine.swift`; parity reference: py4DSTEM's FCU-Net. Decide before building. |
| **Cropping a dataset that is already open** | Under the view model (§6.1) this is a reopen with a different specification, not a "crop what I am looking at" gesture. If the gesture is wanted it is its own stage, not a detail of L3. |
| **Real-space binning or thinning** | Never asked for. py4DSTEM has `bin_data_real` / `thin_data_real` if it ever is. |
| **Writing a reduced cube out as its own file** | An additional *export*, not a change to the view model. Cheap to add once L6 carries the specification. |
| **Screen-reader (VoiceOver) usability** | Moved out of v1 deliberately on 2026-08-05; the verification procedure is already written at `docs/archive/v1.0/voiceover-verification-checklist.md`. Opens when a real user needs it. |

---

## 4. The refusal rule

Two clauses. Everything else in this file is an ordering preference; **this is
the part that says no.**

**1. Nothing ships that can fabricate a scientific result, and no gate is
widened to make something pass.**

This is not abstract — it is the failure mode this repository has actually
produced. A too-tight tolerance fails loudly; a too-loose one fails silently.
So: use precision to *explain* a rejection, never to grant an admission
(the #14 CIF fix, where deriving the tolerance from the file's own precision let
the coordinate breaking the symmetry excuse the break, admitting a 0.163 Å
distortion as `m-3m` cubic). A calibration value that cannot be re-referenced is
**invalidated with a named reason**, never carried. A gate whose miss path calls
`recordError` and continues is not a gate.

Its operational form: **never let the model that wrote a science-affecting
change be the only one to approve it, and review the diagnosis, not just the
code.** Twice — 2026-08-05 and 2026-08-06 — a fix passed every test written for
it, *including one verified to fail without it*, and was still wrong. Both times
the refuting evidence was already sitting in a log nobody re-read.

**2. No claim in `README.md`, `CHANGELOG.md` or `docs/` that a reader cannot
reproduce on a current machine.**

New as of this phase, because the repository is public. If a claim goes stale,
the fix is to change the claim or fix the gate — not to leave it standing
because it was true once.

---

## 5. Version policy

Phase name and version number are independent axes. "Phase 2" is how much work
it is; semver is about **compatibility**.

| Ships | Version |
|---|---|
| Load pipeline L2–L5 — resident cube, crop/bin on open | **`v1.1.0`** — features, backward compatible |
| L6, *if* crop/bin provenance changes the session sidecar or export format such that `v1.0.0` cannot read them | **`v2.0.0`** |
| Bug fixes, doc/claim corrections, the red-gate resolution | `v1.0.x` |

**The `v2.0.0` question is decided at L6, on the evidence of whether the format
actually breaks — not in advance.** It is currently the only plausible trigger
on the roadmap.

---

## 6. Decisions taken 2026-08-17

Recorded with their reasons, because a decision without its reason gets
re-litigated.

1. **A cropped/binned cube is a *view* of the source file** — not a new dataset,
   not py4DSTEM's in-place mutation. Settles `load-pipeline-plan.md` §7.1 and
   unblocks L3, which could not start cleanly without it. The reason is the
   workflow in §1: if the reduced cube were a new dataset, "re-run at full
   extent" would mean redoing the analysis from scratch — precisely the manual
   step the app exists to remove. As a view, *removing* the specification **is**
   the promotion to full extent. Consequence: `LoadSpecification` is a
   first-class, re-applicable, serializable object, not a memory-saving trick.

2. **The XCUITest QC playthrough is retired as the acceptance test.**
   Verification splits into two tracks, written up in
   `docs/development-process.md` §6. Reasons, all verified: it has **never**
   produced screenshots (every run used `--no-screenshots`), so its visual
   acceptance role was always nominal; it touches **no** disk-detection control
   — no `minRelative`, no `minPeakSpacing`, no correlation power — and records a
   peak *count* without judging it, so a run detecting only the central beam
   produces a number and a green step; and it can read a **stale** count
   (`polycrystal_2D_WS2`: 16,384 logged against the app's own later 213,441).
   It also needs a Screen Recording grant it has never had.

3. **Track B — human visual acceptance — becomes a real, written procedure**, at
   [`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md).
   It has now outperformed the full automated suite **twice**: two defects on
   tag day with all 30 harnesses green, and three more in the 2026-08-14
   clean-account run, none of them reachable by any harness in the repo.

4. **`AppState` decomposition becomes a binding per-stage rule.** Every L-stage
   that touches `AppState` extracts **one** seam before it lands, at a green
   test boundary. The extracted type is **itself `@Observable`** and `AppState`
   holds it — real separation, view code changes at each extraction. Thin
   forwarding properties were rejected: they preserve the view API but keep the
   property that caused the problem, which is that every piece of code can reach
   every piece of state. Order and rationale in `docs/development-process.md`
   §7.

5. **Two primary datasets:** `sim_Au_data_all_binned` (simulated, known answer,
   the parity anchor) and `downsample_Si_SiGe_exp` (experimental, where the real
   problems live — #46, #29 and #18 are all on it). `Particle_1…bin8` and
   `polycrystal_2D_WS2` run on demand when a change plausibly touches what makes
   them different. A coverage argument, not a speed one.

6. **`tools/run-tests.sh` gets a free-space preflight** that fails immediately
   with "need N GB free, have M". On 2026-08-06 three consecutive full-suite
   runs produced three *different* failure sets, none related to the code, all
   caused by a full disk, and they were nearly diagnosed as real regressions.
   `xcodebuild test` writes a ~300 MB system log archive to `/var/tmp` per run
   and `References/` is 3.3 GB on a 256 GB machine.

7. **A second science workstream stays shut until L6 lands** (§3).

8. **Version policy as in §5.**

---

## 7. When this phase is done

- L2 through L6 are ticked in `load-pipeline-plan.md` §5.
- The claim in §1 has a fixture behind it: the same analysis, run under two load
  specifications, compared — not a self-consistency check.
- `tools/run-tests.sh all` is green **on the current OS**, and `README.md` /
  `CHANGELOG.md` state a claim a reader can reproduce (refusal rule, clause 2).
- A visual acceptance baseline exists, per
  [`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md).
- `AppState` has five or six fewer responsibilities than it started with, each
  extracted at a green boundary rather than in one refactor.
