# v2.0 on-ramp — what a second development phase starts from

**Written 2026-08-05, at the close of the v1.0 development phase.** This is the
handover document. It says what v1.0 is, what it deliberately left out, what is
still open and why, and which working methods earned their keep and should be
repeated. It is *not* a plan — v2.0's scope is a decision the release owner has
not made yet, and nothing here is committed to.

Read this with [`docs/post-v1-ideas.md`](post-v1-ideas.md) (the parking lot for
ideas that need `Core/` changes) and
[`docs/ui-workflow-backlog.md`](ui-workflow-backlog.md) (the item-level record).

## Where v1.0 ended

- `tools/run-tests.sh all` — **exit 0, 30 harnesses**: `unit` (105) +
  `scientific` (28) + `real-data-acceptance` + `package-test`.
- The frozen v1 workflow (Prepare → Image / Map / Reconstruct → Results) is
  implemented, with calibration provenance and task-scoped readiness.
- Distribution is verified up to the credentialed step: hardened, sandboxed,
  self-contained, no Homebrew dylib. Developer ID signing, notarization, and a
  clean-account launch remain release-owner actions.
- **Not yet code-reviewed, and not yet tagged.** Review range
  **`a9e4268..9c940d1`** — the 2026-08-05 UI session plus the backlog #14 CIF
  fix. The tag goes on after that review.

**One verification debt crosses the line into v2.0:** the QC playthrough
acceptance re-run. See "The one thing to do first" below.

## The one thing to do first

**Run `tools/ui-qc-playthrough/run.sh` (no argument) and diff against
`References/training_runs/run_2026-08-03_1404/`.** It has not produced a clean
comparison since 2026-08-04, across roughly nine landed tasks.

It was blocked for two different reasons in succession, and only the first is
gone:

1. **Accessibility permission** — resolved 2026-08-05. The grant must go to the
   process that *spawns the shell*, which is the lowercase `claude` entry
   (`~/Library/Application Support/Claude/claude-code/<version>/claude.app`),
   not the `Claude` desktop app. Restart the app after toggling.
2. **Backlog #16/#22** — still open. The playthrough now fails at step 3b on
   every dataset, so it reaches neither Bragg disks nor ACOM nor strain. Fixing
   #16 is the prerequisite for the acceptance diff, not a parallel task.

What the diff must show: **ACOM numbers should move** (the §10.2 radial-kernel
and reliability fixes postdate that baseline); **peak counts, Q pixel sizes and
strain diagnostics should not**. Anything else that moves is a regression from
the 2026-08-05 UI work.

## Open threads, grouped by what they actually need

### Blocking a confident v1.0.x, not v2.0 features

- **#16 / #22 — layout collapses on a task switch.** Trigger isolated
  2026-08-05 to a single click (Virtual imaging → DPC & iDPC in the Image
  workspace, on a real dataset). The whole window's content lays out ~52 pt too
  high, as if the titlebar safe-area inset collapsed. The earlier "sidebar
  scroll view" diagnosis is a symptom, not the cause — a sidebar offset cannot
  move the detail column, and the captures show both moving together. Evidence:
  `References/training_runs/run_2026-08-05_2012/*/ERROR_state.png` against
  `03_virtual_df.png` in the same folder.
  **Six in-process reproductions have now failed.** Real synthesized input
  reproduces it every time; mutating `AppState` never has. Do not spend a
  seventh attempt on a hosted test before trying the XCUITest.

### Scope decisions, not engineering

- **#11 — WS₂ crystal model.** Governed by ROADMAP P1.3, which already sets the
  admission bar (explicit lattice, atomic basis, symmetry reduction, structure
  factors, expected-orientation fixture, fit-overlay acceptance). The CIF
  importer now provides the generic path, but WS₂ is hexagonal-family and the
  importer's symmetry verification would have to admit it honestly — this is a
  decision about evidence, not a UI task.
- **New datacubes.** The release owner brought additional example datasets
  specifically for v2.0. They are not in the v1.0 manifest and must not be
  retro-fitted into the v1.0 acceptance gate; treat them as v2.0 scoping input,
  and add them to `real-data-acceptance` only with goldens of their own.
- **`docs/post-v1-ideas.md`** — cropping and partial/binned loading. Both touch
  `Core/`, both were deliberately kept out of the UI backlog so that backlog
  stays safe to hand out as implementation prompts.

### Deferred by an explicit, recorded scope change

- **VoiceOver runtime verification.** Removed from the `docs/v1-scope.md` "Mac
  experience" gate on 2026-08-05 because no current or near-term user needs it.
  The procedure is parked in
  [`docs/voiceover-verification-checklist.md`](voiceover-verification-checklist.md)
  so v2.0 starts from a checklist rather than from scratch.
  **Do not delete the accessibility identifiers** — they are the surface
  XCUITest matches on and `mac4DSTEMUITests/Support/AXDriver.swift` depends on
  them. They are not screen-reader features.
  Worth keeping as ordinary UI review rather than a gate: the checklist's
  Part 4 (increased text size), a cheap layout stress test for exactly the
  truncation/overlap class this UI keeps producing.

### Harness confidence — the tests, not the app

- **#18** — the campaign cannot reproduce the app's strain result on Si_SiGe,
  even from a peak-identical input. Until this is closed, past "app produced no
  strain map" campaign records are evidence about the harness, not the app.
- **#19 / #20** — whether `Particle_1` has Bragg reflections on the detector at
  all, and a re-measurement of the Bragg spacing distribution without the gate
  floor. Both need the release owner's acquisition parameters.

### Found by hands-on use, 2026-08-05 — the class a code review will not catch

**#33–#37**, all reported by the release owner driving the app by hand while
the v1.0 phase closed. Worth reading as a group, because they make a point
about method: none of them is visible in a diff. A reviewer reading
`a9e4268..9c940d1` would not notice that a tick appears before its step ran, or
that a cancelled run leaves a map on screen. **Hands-on use and code review find
disjoint defect sets** — budget for both.

- **#33** — the green task tick means "prerequisites met", but the app uses ✓
  for "completed" elsewhere on the same screen. Confirmed in code.
- **#34** — a cancelled Bragg detection still displays a Bragg vector map,
  contradicting the documented cancel contract. Establish whether it is a stale
  previous result or a partial one *before* fixing; the answer changes the fix.
- **#35** — double-click in the diffraction pane moves the detector cursor
  instead of panning/zooming like real space.
- **#36** — no progress indication while a datacube loads; the first thing a
  new user meets is an unexplained wait.
- **#37** — cancelling the virtual detector takes a long time and shows stalled
  progress meanwhile.

### Small and known

- **#15** — `classifyFamily` admits a metric band that `validationIssues` then
  rejects with a different message. A correct rejection carrying a less specific
  message; no wrong results.
- **#31** — `CrystalModel.validationIssues` is O(n²) and is read from a SwiftUI
  view body. Bounded and accepted knowingly (76 ms at 10 000 atoms; real ACOM
  phase models are tens of atoms). Fix by precomputing in the model rather than
  per read.
- **#32** — `CIFImport.isSymmetry`'s bijection guard survives mutation testing,
  and the counterexample its comment cites does not exercise it. Either build a
  case that kills the mutant or delete the claim.
- **#29 / #30** — recorded investigations: disk detection "going bad" is the
  origin fit, not the detection; origin calibration over a NAS runs at ~3 MB/s.

## Methods that earned their keep — repeat these

- **Adversarial review is not a formality.** It refuted the *first* version of
  the #14 fix, which had already passed all 30 harnesses. Three regressions —
  a rounding-only error bound that broke on truncated CIF coordinates, a
  precision-derived tolerance that let a coarse file widen its own point-group
  gate, and a merge cap that silently deleted an atom. Never let the model that
  wrote a science-affecting change be the only one to approve it.
- **The generalizable rule that came out of it:** *a too-tight tolerance fails
  loudly, a too-loose one fails silently — so never widen a gate whose failure
  mode is a fabricated result.* Use a file's precision to **explain** a
  rejection, never to grant an admission.
- **Run a gate before judging it.** Performance and distribution were both
  assessed as "stale" from reading docs on 2026-08-05, and both were wrong.
- **Real input is not the same input path as mutating state.** SwiftUI layout
  demonstrably behaves differently. Interaction bugs need XCUITest with
  Accessibility granted; a hosted `NSWindow` test catches geometry regressions
  but will not reproduce them.
- **A probe that cannot see its target must not be left behind as a passing
  test.** One was written and deleted the same evening for this reason.
- **Fixtures must sweep the axis that hides the bug.** #14 survived the first
  CIF fixture because every "must admit" case supplied its cell contents
  explicitly, so the symmetry-expansion path never ran. The fixture now sweeps
  precision (2/3/4/6/7 decimals) in both the rounded and truncated spellings.

## Where the record lives

| Question | Doc |
|---|---|
| What is the app, how do I build it | [`README.md`](../README.md) |
| Standing priorities + scope rule | [`ROADMAP.md`](../ROADMAP.md) |
| The frozen v1 release contract | [`docs/v1-scope.md`](v1-scope.md) |
| Item-level UI/workflow record | [`docs/ui-workflow-backlog.md`](ui-workflow-backlog.md) |
| The implementation phase's task prompts + status | [`docs/ui-implementation-prompts.md`](ui-implementation-prompts.md) |
| The finished evaluation phase + how the harness is driven | [`docs/qc-playthrough-prompts.md`](qc-playthrough-prompts.md) |
| Pipelines, app-vs-py4DSTEM findings, run findings | [`docs/py4dstem-pipelines.md`](py4dstem-pipelines.md) |
| Model tiers, review gates, delivery conventions | [`docs/development-process.md`](development-process.md) |
| Ideas that need `Core/` changes | [`docs/post-v1-ideas.md`](post-v1-ideas.md) |
