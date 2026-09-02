# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff (start here)

**After v2.0 ships: [`docs/v2.5-plan.md`](docs/v2.5-plan.md)** (2026-09-02) —
the consolidation train (naming, merged UI findings, package split, product
model, sequence, owner decisions). v3 is reserved for the feature plan.

**Shipping v2? Start at [`docs/v2-ship-plan.md`](docs/v2-ship-plan.md)** (drafted
2026-09-01) — the sequenced path from here to a tagged release, with the two
owner decisions it waits on. It supersedes nothing; it orders what §9 already
lists.

**v1.0.0 is tagged, signed and public. The v2 release was planned 2026-08-18**
— the contract and session plan are `docs/v2-release.md`: §1 the claim, §7 the
gates, §8 the session briefs, §9 the live status checklist. **The one
canonical kickoff prompt is §8's copy-paste block.** In Claude Code, type
**`/pickup`** (or `/pickup S7` for a specific session) instead of pasting it.
The other standing skills — `/track-b`, `/diagnose`, `/adversarial-review`,
`/closeout` — each encode one of this repo's disciplines; they live in
`.claude/skills/` and point at the docs rather than restating them.

Standing cautions, each of which has burned this repo before:

- **Do NOT set `ResidencyAdmission.measuredWorkingSetFraction`** — nil by
  decision, not oversight; `.automatic` residency was DROPPED (S3), not tuned.
- App-code changes follow `docs/development-process.md` (Explore on Haiku to
  locate code, implement on the default model) and take the gate the session
  names — A, B or D, defined in §7 of the release plan. Gate D writes the
  diagnosis, the refuting observation and the predicted outcome, then runs
  the experiment, BEFORE touching code.
- Anything touching `Core/` or the science needs an adversarial review *and*
  a `tools/` fixture. **Never let the model that wrote a science-affecting
  change be the only one to approve it; review the diagnosis, not just the
  code.** Three times (2026-08-05, 2026-08-06, 2026-08-18) a fix passed every
  test written for it — including one verified to fail without it — and a
  second reader of the same evidence refuted it.
- A session touching `AppState` extracts one seam first. A change to what the
  app draws queues Track B rows and is unverified until the owner drives them.
- **Break every new test before trusting it** — three green-but-worthless
  suites were caught that way on 2026-08-17 alone.
- **Open the app.** Tag day: all 30 harnesses green, and ten minutes of
  driving by hand found two defects the suite could not see; the
  clean-account run found three more. Track B
  (`docs/visual-acceptance-checklist.md`) exists because nothing else catches
  that class. You cannot run it yourself — write the checklist and ask.

## What this is

**mac4DSTEM** — a native macOS (Swift / SwiftUI / Metal) app for interactive
4D-STEM analysis on Apple Silicon. The mission is feature parity with
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), which is vendored here as the
reference implementation and validated against.

## Where things stand

**v1.0.0 — tagged 2026-08-06; signed, notarized and public since 2026-08-14**
at `github.com/mac4DSTEM/mac4DSTEM` (GPL-3.0, stapled DMG linked from
mac4dstem.com). What it is: [`CHANGELOG.md`](CHANGELOG.md). **Distribution is
done.**

**The v2 release is mid-flight: S0–S8, S9a, S9b, S10, S11, S12, S13, S17, S18,
S19, S21, W4a (S14+S15, merged by owner decision 2026-08-31) and W4b (S16)
are done**, plus a **review recovery + Track B playthrough (2026-08-31/09-01)**
that changed **no app code**: the interrupted whole-codebase review was finished
(**75 findings dispositioned, 15 session records audited** —
[`docs/archive/2026-08-31-review/`](docs/archive/2026-08-31-review/)), triaged
into a v2/v2.x recommendation
([`docs/v2-triage-2026-09-01.md`](docs/v2-triage-2026-09-01.md), **owner decision,
not scheduled**). Its first Group A item, **`core-analysis-physics-01`, is now
resolved**: Gate D confirmed the DPC angle's exact 2π unit error, the repair
migrates legacy sidecars, and a separate Gate B refuter cleared it after five
corrections ([record](docs/archive/v2-session-records/dpc-angle-units.md)).
Also, **six Track B rows were driven green** — **Done criterion 8
is met on screen**, and **`app-appstate-01` is the first review finding reproduced
at runtime**. Track B now stands at **31 passed / 9 partly / 19 unverified /
1 blocked** (F1.47–F1.50 queued by the 2026-09-01 repair/UI sessions; F1.51
scored PARTLY by the owner's evening drive; F1.52 scored PARTLY by the S22
consolidated drive; **F1.53 is the owner's single final-playthrough row**)
(plus the M1 tidy and the M2 gate repair) — **S13 was MERGED to `main` and
pushed (fast-forward to `bab5e07`); `s13-q-calibration` still exists and points
at the same commit. Corrected 2026-08-31**: this file and §9 both still said
"NOT merged to `main`; the merge is the owner's call", which was true when
written on 2026-08-29 and stopped being true when the owner merged. Neither
summary noticed. The evidence is `git reflog show main` —
`main@{0}: merge s13-q-calibration: Fast-forward` — not either doc.
— the load pipeline closed as a product, the promote run with unattended
recipe replay, the error-honesty and strain-frame trust fixes, and the
reduced-file export with the recipe frame mapping — with the full session
records in
[`docs/archive/v2-session-records/`](docs/archive/v2-session-records/).
**S18 is ticked `[x]`. Its Gate B debt was cleared 2026-08-28** — a separate
refuter attacked both `Core/` changes (`pattern(ry:rx:)` from the resident cube,
the staging-copy elimination) and **both survived**, twelve mutations each
producing a distinct red. It also exposed a fixture blind spot, now closed by
`tools/resident-cropped-view`. **What is still owed from S18 is only the
`mac4DSTEMUITests` deletion**, which the environment refused rather than
declined; that needs the owner.

*Read this before trusting either summary again:* on 2026-08-27 a session found
this paragraph disagreeing with §9's S18 stub and **resolved it the wrong way**,
rewriting this text to defer to the stub — which claimed a Gate B review that
S18's own record does not contain. The record's *Not verified* section says the
second read did not run, and its only review section is `Gate A — 14 agents`.
Corrected 2026-08-28. **When a stub and this file disagree, neither wins by
default — open the session record in `docs/archive/v2-session-records/`, which
is the evidence both are summarising.**
Sequencing (§9's checklist and resequencing line are the authority): the
S10 → S21 → S17 run is complete; **TB1 sitting 1 is COMPLETE (2026-08-27)** and
sittings 2–4 wait on the owner — sitting 3 needs a multi-GB/NAS cube, sitting 4
a clean account. **S11 was run ahead of them on 2026-08-28** rather than after,
because it needs neither; that reordering is stated in its stub, and **S12 ran
ahead of them on 2026-08-28 for the same reason**. **S9b ran 2026-08-28** and
needed no NAS after all — the axis is
`MNT_LOCAL && !MNT_REMOVABLE`, not local-vs-network. Its mechanism is confirmed
and scoped to DM4/DM3; the 2026-08-18 death itself is **still unexplained**, and
the reader fix is owed to a later session. **#37 moved to S9**, since S18's
measurement showed the cancellation cost is I/O, not check granularity. The
cut line and the severable block (now **S14–S16, TB2** — S11–S13 landed)
are §2 of the release plan. **S13 implemented
[`docs/q-calibration-design.md`](docs/q-calibration-design.md) on the owner's
§6(a) decision (2026-08-28, Gate B with four refuters)** — but the review cut
all three estimator thresholds (derivation refuted), so the estimator
**measures and reports** the shell ratio rather than refusing on it, and the
origin-fit gate stays on the full-scan RMS: **which statistic should gate that
fit is OPEN** (`docs/open-items.md`). The demo-fixture and probe-radius
findings (`probeSize` over-measures 2.15×, Gate D owed) came out of the same
session. F1.40 and F1.41 passed on 2026-09-01; F1.42–F1.43 remain queued.

**Later on 2026-09-01, three more sittings landed** (all in §9 and sequenced
by the ship plan): **Step 0 is DECIDED by the owner** — all five remaining
Group A items ship fixed, the probe radius and the CIF pair joined Step 1,
the "hand a colleague"/"promote overnight" claims are DISCARDED (S19
restates §1; the clean-account and bounded promote runs stay), two
owner-promoted UI changes ride, and the working split is
assistant-implements / cheap-subagents-explore / independent refuter per
gate (full record: `open-items.md` §Owner decisions). The **docs tidy**
archived the 661-line Track B thread (tax 3689 → 3307). The **CIF pair**
(`core-crystal-02`/`04`) and the **probe radius** (max-union over-measure —
14.1/19.1 px were `probeSize(maxDP)` to the digit; both call sites now feed
meanDP) are **DONE, each through Gate D reproduction and an independent
Gate B refuter that materially corrected its author** (records:
[`cif-pair.md`](docs/archive/v2-session-records/cif-pair.md),
[`probe-radius.md`](docs/archive/v2-session-records/probe-radius.md)).
**Track B rows F1.47–F1.50 are queued** (DPC angle units, CIF refusal dialogs,
the honest radius + stricter origin gate, scan navigation without the redundant
sliders); **F1.51 (permanent colormaps) was scored PARTLY the same evening** —
visible and working, refused on the redundant colormap submenu. **The UI pair
is DONE 2026-09-01 but HELD uncommitted** (owner decision — he will not finish
Track B in the current UI state), and his evening playthrough opened S22's
evidence with a "not a good v2" verdict (seven findings, one of them science:
bullseye disk detection, Gate D owed). **Decided the same evening: S22 moves
ahead of the remaining fix queue.** The design ran, the owner approved it
("go as deep as needed"), and **all five slices S22a–e are DONE the same
night** — system inspector column, menu/task-pane idioms, the spine re-cut
to **Prepare / Imaging / Strain & ACOM / Phase / Results** (the third step
renamed from "Bragg" by owner decision D1; `WorkspaceNavigation` seam
extracted first), sidebar wrapping + the 144pt-restore clamp, and six
of eight backlog-polish items (`ui-04` and `core-data-09` deferred with
reasons). A consolidated assistant drive verified the changes on screen and
caught two more defects the green gates could not (the stale demo greeting;
sidebar wrapping needing `lineLimit(nil)` against the list style's inherited
one-line limit). **[`docs/s22-ux-design.md`](docs/s22-ux-design.md) is the
single S22 thread** — evidence, design, per-slice records, gate counts.
**The owner's real playthrough that night rejected the state — and the
whole feedback queue was then closed the same night** (16 findings R1–R16,
all in `docs/s22-ux-design.md` §5.5): the width-bounds regression, welcome
cards, overprint, duplicate Show row, produced-state task glyphs, pan
clamping. **P1 (frozen Detect All Disks) closed by full Gate D** — owner
reproduced, agent sampled mid-hang, refuter confirmed with corrections: the
main thread was conscripted by `concurrentPerform`, the mechanism predates
v1, and the true slowness is the 250-px detector falling to
`FFT2D.executeDFT`'s O(n²) fallback — **replaced 2026-09-02 by an exact
Bluestein transform, Gate B passed, Detect All Disks on the 250-px cube
14 m 09 s → under 15 s in Release with the same 83929 peaks**
(`docs/s22-ux-design.md` §6, 2026-09-02 entry). Fix = detached execution; **owner verified live: progress
painted, Cancel worked.** **P2 (stale-frame sidecar calibration) closed by
full Gate D** — session calibration now goes through
`SessionCalibrationFramePolicy` (identity / re-reference / refuse) and the
engine; the refuter corrected the fix twice (double-application avoided;
identity-restore map sizing pinned red-first). **D1–D4 landed**: the third
workspace is **Strain & ACOM**; `StatusFooterView` is the permanent
status/progress/facts footer; colormaps moved onto each pane's colorbar
chip (`ColormapChipMenu`, sidebar Display row retired); "Reopen Without
This Session"/"Ignore…" skip a sidecar one-shot, file untouched. **Feedback rounds 3–4 landed the same night** — the colorbar chip rebuilt
as a popover (the owner caught the Menu-label build losing its gradient),
the footer stacked so it can cover nothing, region sums scoped to Current
mode, flat auto-advancing reconstruction stages, ACOM preview advancing to
the full run, produced-state circles for virtual/DPC, linear-default
histograms, and a stateful Phase requirements line. **27 owner findings
R1–R27 total, 24 fixed and gated** (`docs/s22-ux-design.md` §5.5 is the
ledger; its HANDOFF block in §6 is the open queue, and **§6.1 carries the
owner-requested copy-paste kickoff prompts for the FFT speedup session and
the colormap-chip fix** — R23 is **FIXED AND VERIFIED ON SCREEN 2026-09-02** — the popover rebuild
was right; `ScalarColorbarView`'s `allowsHitTesting(false)` made the chip
button unclickable, moved to its one plain use site; both colormaps change). Last full suite:
**429 passed / 0 failed / 2 skipped, 2026-09-02** on the FFT tree (the S22
final was 417; warm MCP runs — the fresh gate
refuses exit-69 at the ~6 GB disk floor; the layout gate re-pins the
sidebar width per measurement because a live app instance's width autosave
otherwise leaks into the harness). The recorded lesson stands:
verification drives must use real data, both divider extremes, a full
compute, and a sidecar dataset. A
standing **token-conservation directive** landed with it: lower-tier models
when possible and safe, terse docs, heavy gates reserved for science
(`docs/open-items.md` §Owner decisions 7–8).

**The honest test claim — each number dated to its own run:**
`run-tests.sh scientific` — **exit 0, 42 started / 42 completed, zero FAIL and
zero SKIP lines** (inside the 2026-09-01 aggregate run, observed to completion
rather than trusting an exit code). **`tools/acom-convention-test` joined the
array** in the 2026-08-31 review recovery and passed inside the gate for the
first time in this run (Au median 1.25°, WS₂ 0.78°); it was 41 at the W4a/W4b
closeouts, 39 at S13, and the docs said 38 for three days after that. Do not
quote a harness count from memory — `run-tests.sh` is the only thing that knows
it.
`run-tests.sh unit` — **409 passed / 2 skipped / 0 failed, exit 0**
(2026-09-01 S22 final closeout, counted from the retained log; parallel runs
garble about one `Test case` line per run, so grep undercounts by one and the
exit code is authoritative for failures). The S22 slices ran SEVEN full gates
that evening (a/b/c1/c2-caught-one-red/c3/d/e/final), each counted from its
own retained log; the earlier closeouts' 401 and 393 stand as their own dated
runs, and 393 is what settled 2026-08-31's unexplained 390-vs-391
discrepancy.
`run-tests.sh scientific` also re-ran green on the probe-radius tree the
same day — **42 started / 42 completed, zero FAIL, exit 0**, counted from
the retained log. The two skips are unchanged: the
unmounted-volume bookmark probe and S17's explicit uncalibrated-Prepare geometry
quarantine. Two former data-probe
skips (including `TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes`)
now PASS because their staged data is present. **Two recordable non-green outcomes
from that sitting, both environmental:** one `unit` run refused with **exit 69**
(the S0 preflight — scratch DerivedData from repeated app builds; cleared, then
green) and one reported a single spurious failure in
`SidebarDensityMeasurementTests` because the app was being driven for Track B
against the same defaults domain while the gate ran. **Do not drive the app
during `run-tests.sh unit`** — see `docs/open-items.md`.
MCP `test_macos` — **378 passed / 1 failed** (2026-08-26, S10; the
now-diagnosed sidebar test — the retired UI target skipped), retained as its
own dated run. **`run-tests.sh all` — GREEN END TO END, exit 0, 2026-09-01**
(DPC angle-unit closeout): **44 harnesses started and 44 completed**, unit stage
**393 passed / 2 skipped / 0 failed** (the unit count is from the standalone
retained xcresult), with **zero failing harnesses and no exit-69 refusal** in
the direct, unpiped aggregate run. Four scientific `SKIP`s, all correct: the four
`.mac4dstem.h5` sidecars beside the training data, recognised as sidecars rather
than read as datacubes (#43). One `UNPINNED` line names four real cubes that
`expected.json` does not cover — advisory by design, see `docs/open-items.md`.

**The previous aggregate claim — "exit 0, 40 harnesses, 2026-08-28" — was not
reproducible, and it took two fixes to make one true again.** `real-data-acceptance`
failed on a report-count mismatch, and behind it `package-test` had been red
since S19 raised the macOS floor without updating the assertion that pins it.
The second was invisible until the first was fixed, because the run aborts at
the first failing harness. Both are in `docs/open-items.md` with their evidence.

**S19's blocking dependency is therefore met**, and the README/CHANGELOG
aggregate claim can be restated against this run rather than retired. Do not
quote an aggregate you did not just run — **and note the aggregate has NOT
been re-run since that DPC-closeout tree**: three commits landed after it
(`87e6c45` docs tidy, `4b99971` CIF pair, `349a2c8` probe radius); unit and
scientific both re-ran green on the newest tree, `all` itself has not.

**Verification runs in two tracks** (`docs/development-process.md` §6):
Track A is `tools/run-tests.sh`; Track B is the human visual pass at
[`docs/visual-acceptance-checklist.md`](docs/visual-acceptance-checklist.md).
The XCUITest QC playthrough was retired 2026-08-17; its eval-only rule
carries over unchanged: never change app code to make an acceptance step
pass — that is a finding, not a bug fix.

## Where things are written down

- **[`CHANGELOG.md`](CHANGELOG.md)** — what v1.0.0 is, and what it was *not*
  verified by. Start here for scope.
- **[`docs/open-items.md`](docs/open-items.md)** — everything still live, and
  the working methods that earned their keep. **The only maintained status
  doc.**
- **[`docs/v2-release.md`](docs/v2-release.md)** — **the v2 release contract
  and session plan**, decided 2026-08-18. The claim, the five workstreams, the
  cut line, the refusal rule, the version evidence, the three gates (A/B/D —
  D is the structural guard against a confident wrong diagnosis), the numbered
  sessions S0–S21, and the live status checklist. **The single entry point.**
  Consult it for "what do I pick up?" and "is this in scope?".
- **[`docs/q-calibration-design.md`](docs/q-calibration-design.md)** — **S12's
  design, 2026-08-28**: what the origin-fit residual gate actually measures
  (#29, answered), the sane-origin / measure-Q split, the estimator-internal
  plausibility checks, and the coarse-step in-or-out call with its measurement.
  Read it before touching Q calibration, `OriginCalibration` or
  `Shaders/OriginMeasure.metal`; S13 implemented from it (2026-08-28, with
  Gate B's threshold cut recorded in
  [`s13.md`](docs/archive/v2-session-records/s13.md)).
- **[`docs/v2-scope.md`](docs/v2-scope.md)** — the 2026-08-17 phase-2
  priorities. **Superseded by `docs/v2-release.md`**; kept for the eight
  decisions and their reasons. *(It replaced `docs/v2-planning-draft.md`,
  which is deleted.)*
- **[`docs/visual-acceptance-checklist.md`](docs/visual-acceptance-checklist.md)**
  — **Track B**, the human visual pass, with the standing checklist and the
  known traps behind each row. The assistant writes the specific list; the
  release owner drives the app and sends screenshots.
- **[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md)** — how L1–L6
  were built and reviewed, stage by stage, with the invariants and the
  py4DSTEM deviations. **Superseded 2026-08-18, kept as the authoritative
  history of that work.** Do not add stages or tick anything there.
- **`docs/py4dstem-pipelines.md`** — the pipelines step by step, the
  app-vs-py4DSTEM findings (§7), scope/roadmap (§8), empirical run findings
  (§9).
- **`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/run.sh`** — **retired
  2026-08-17, unmaintained, still in the tree.** Do not spend a session
  repairing it and do not cite its numbers; see `docs/v2-scope.md` §6.2 for why.
  Whether to delete it is an open item.
- **[`docs/archive/s1-sidecar-under-the-sandbox.md`](docs/archive/s1-sidecar-under-the-sandbox.md)**
  — S1's full investigation, archived 2026-08-19. **History, not guidance**, but
  the *method* is the reusable part: a pre-registration written before its answer
  was known, and a Gate B correction that stopped one wrong errno sending the
  diagnosis the other way.
- **[`docs/archive/v2-session-records/`](docs/archive/v2-session-records/)**
  and **[`docs/archive/closed-items-2026-08.md`](docs/archive/closed-items-2026-08.md)**
  — the verbatim S1–S8 session records and the closed open-items entries,
  moved out of the live docs by M1 (2026-08-26). **History, not guidance.**
- **[`docs/archive/v1.0/`](docs/archive/v1.0/)** — the v1.0 phase's working
  memory: 46 numbered findings, the design passes, the QC-evaluation prompts.
  **History, not guidance.** Nothing current points into it; consult it for
  *why* a decision was made, never for what to do next.
- Session memory (direction + gotchas):
  **`~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/memory/`**
  — the directory for THIS checkout, and it is the live one: 14 files as of
  2026-08-28, `MEMORY.md` being the index a session loads.
  **Corrected 2026-08-28.** This entry used to name
  `…-GitHub-mac4DSTEM/memory/` and warn that a session started from the current
  checkout "gets a *different*, empty memory directory". That was true when the
  repo moved; it is not true now, and a fresh agent reading it would go looking
  in the wrong place and conclude it had no memory. Three stale siblings exist
  from earlier checkout paths — `…-GitHub-mac4DSTEM` (6 files, pre-move),
  `…-Claude-Projects-mac4DSTEM` (4, older still) and
  `…-GitHub-mac4DSTEM-Organization` (empty) — all history, none loaded.

## Standing references

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities, the version policy, and the
  scope rule.
- **`docs/v1-scope.md`** — the **frozen** v1 release contract, kept as the
  record of what v1.0.0 promised. Superseded as the live contract by
  `docs/v2-scope.md`; consult it for what was in v1 and why, not for what to do
  next.
- **`docs/archive/v2-onramp.md`** — the phase-2 handover, archived 2026-08-18;
  everything it tracked is superseded by `docs/open-items.md` and
  `docs/v2-release.md`.
- **`docs/post-v1-ideas.md`** — parking lot for ideas that are out of v1 scope
  *and* would touch `Core/` (cropping, partial/binned loading). Deliberately
  separate from `docs/open-items.md` — whose original UI/workflow-only rule
  no longer holds: check an item's owning session and gate before handing it
  out as a prompt. Nothing here is committed to; entries record the
  non-obvious constraints so a later session doesn't rediscover them.

## Where things go (file-placement rules)

The Xcode project uses **synchronized folder groups**: any file placed under
`mac4DSTEM/` auto-joins the app target, and `.metal` files auto-route to the
Metal compile phase. So placement *is* wiring — put files in the right folder
and they build.

| Putting in… | goes under… |
|-------------|-------------|
| App entry, window/workflow state (`AppState`), recovery | `mac4DSTEM/App/` |
| Readers (H5/DM4/vendor), calibration model, EMD writer, product model | `mac4DSTEM/Core/Data/` |
| GPU/Metal engine, FFTs, multicorr, cancellation | `mac4DSTEM/Core/Compute/` |
| Analysis algorithms (virtual detector, calibration solvers, disks, strain, DPC, parallax, ptycho) | `mac4DSTEM/Core/Analysis/` |
| Crystal models, scattering factors, ACOM matching | `mac4DSTEM/Core/Crystal/` |
| Operation-lifecycle controllers | `mac4DSTEM/Core/Workflow/` |
| Metal kernels (`.metal`) | `mac4DSTEM/Shaders/` |
| SwiftUI views, viewers, controls, inspectors | `mac4DSTEM/UI/` |
| Export, system monitor, bridging header | `mac4DSTEM/Support/` |
| Fast unit / workflow-contract tests (logic, invisible, in-process) | `mac4DSTEMTests/` |
| UI automation / visible QC playthrough (whole app, on-screen) | `mac4DSTEMUITests/` |
| Standalone parity / dev / packaging harnesses | `tools/<name>/` (add to `tools/run-tests.sh` if it should gate) |
| Human design/scope/process docs | `docs/` (dated or superseded → `docs/archive/`) |
| CI workflows (the `unit` + `scientific` gates on every push; S21) | `.github/workflows/` |
| Vendored external material + machine-local data (`References/` is gitignored — **except** the py4DSTEM Python source lock, which is tracked on purpose so `DEVIATION` notes can cite it by file and line; see `.gitignore`) | `References/` |

## Hard rules

- **Views describe UI only.** Loading/parsing/compute live in `Core`.
  `AppState` (`@Observable`) is the single source of truth.
- **Acceptance is evaluation only** — never modify app logic under `mac4DSTEM/`
  to make a Track B step pass. If the app blocks the pipeline, that's a
  *finding* for `docs/open-items.md`, not a code change. (Inherited from the
  retired QC playthrough, which the rule originally named.)
- **A stage that touches `AppState` extracts one seam before it lands**, at a
  green test boundary, the extracted type itself `@Observable`. Binding since
  2026-08-17 — `docs/development-process.md` §7. Splitting the file into
  `extension AppState { }` does not count.
- **No claim stands that a reader cannot reproduce.** If a number in
  `README.md`, `CHANGELOG.md` or `docs/` goes stale, change the claim or fix the
  gate. The repo is public.
- **Metal parameter structs in `MetalEngine.swift` must stay byte-for-byte
  identical** to the matching `.metal` structs (all 4-byte fields).
- **Don't widen scientific-state mutation access** just to reduce line counts
  (ROADMAP P3.2). Extract only at a green test boundary.
- **Don't add `CODE_SIGNING_ALLOWED=NO` to an app build you intend to launch**
  — use `tools/run-tests.sh unit` for unsigned XCTest work.
- **Port deviations from py4DSTEM get an inline `DEVIATION` note** with the
  reason.
- **Keep docs current as part of "done"** — no file self-updates. When a task
  lands, update **`docs/open-items.md`** (add, amend, or delete the item) and
  any reference doc it affects. Do **not** edit `docs/archive/v1.0/` — it is a
  frozen record of the v1.0 phase. **`AGENTS.md` is generated from this file** —
  if you edit `CLAUDE.md`, run `tools/sync-agents-md.sh` (`--check` exits 1 when
  stale); it was hand-maintained until 2026-08-28 and drifted six sessions.
  Full conventions (model/subagent tiers, review gates, where new work goes,
  delivery, and **§9 what keeps a session agent-runnable** — the grants and
  attached disks that turn owner-only rows into work an agent can run):
  **`docs/development-process.md`**.
- Commit/push only when asked; this is a solo-dev repo with linear `main`.

## Build / test / run

```sh
# build (needs full Xcode toolchain, not just Command Line Tools)
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build

tools/run-tests.sh unit          # fast XCTest suite (isolated DerivedData)
tools/run-tests.sh scientific    # py4DSTEM-parity harnesses
tools/run-tests.sh all           # Track A, the aggregate gate
tools/free-space.sh              # exit-69 remedy: report build debris; --clear deletes
```

Track B (visual acceptance) is not a command — it is a person driving the app
against `docs/visual-acceptance-checklist.md`.

## Long-term goals

Three standing priorities (full text in `ROADMAP.md`): **(1) scientific
interpretation** — every result keeps its model/scale/units/validity through
display, export, and reopen; **(2) product clarity** — task-scoped controls,
persistent result labels, visible diagnostics; **(3) incremental architecture**
— shrink the `AppState` facade, one seam per stage, at green test boundaries.
Whether a new feature is picked up now is answered by `docs/v2-release.md`:
its workstreams, its cut line, and its refusal rule.
