# Development process

The operating model since v2.5 step 1 (2026-09-02); drafted 2026-08-31 from
the v2 review as the "v3 development process" proposal and adopted as written.
The v2-era process doc is `archive/v2/development-process-v2.md`.
Evidence: [interrupted-review recovery](archive/v2-session-records/review-recovery.md)
and [review inventory](archive/2026-08-31-review/README.md).

## What should remain

Keep the release contract and scope boundary; Gate D's experiment before a fix;
independent Gate B review for scientific changes; analytic or external reference
fixtures; negative controls; human visual acceptance; and explicit unverified
work. These caught errors in v2. The aim is to make them easier to execute and
harder to misreport, not to lower the bar.

## One compact task, one evidence record

Each task should have one current record containing:

| Field | Required content |
|---|---|
| Outcome | Observable user or scientific result; explicit non-goals |
| Scope | Files/responsibilities, dependencies, release claim affected |
| Gate | A, B, D; who supplies independent judgement |
| Inputs | Exact fixtures, data paths/hashes, permissions and toolchain |
| Evidence | Commands, source revision and dirty-diff fingerprint, exit status, artifact paths |
| State | Planned, running, blocked, implemented, verified, accepted; explicit outstanding obligations |
| Handoff | Last completed step, failed step, safe next command, owner decision if any |

The entry point should contain standing invariants and links. A small current
queue points to task records; dated investigation belongs in the archive. Do
not repeat numerical test counts across the entry point, release plan and README.
A public claim links to one dated run record whose exact source state is known.
Make this migration once at v3 kickoff; do not launch another perpetual tidy pass.

## Complete small review batches

The interrupted workflow launched 11 reviews, 11 intended refutations and three
audits. It lost nine refutations and all three audits to the usage limit. Its
completion message used the planned count and its returned arrays removed missing
results. Recovering work required reading individual transcripts.

For v3:

1. Finish a bounded review/refutation batch before expanding the campaign.
2. Checkpoint each initial result before asking a refuter to examine it.
3. Assign stable finding IDs and retain a disposition for every ID. Refuted is
   an outcome; absent is incomplete. Never return only survivors as the evidence.
4. Give the refuter complete evidence through a file reference. Do not truncate
   serialized findings to a fixed character limit; that can cut off the very
   claim the verifier was meant to assess.
5. Report planned, completed, failed and unresolved counts separately. Missing
   outputs must prevent a complete status, even if the orchestration tool exited
   successfully. The recovery's record checker demonstrates this boundary.
6. At a batch boundary, assess remaining work and resources. Preserve room for
   verification and closeout instead of spending everything on discovery.

Roles matter more than brand names: inexpensive location/mechanical work,
implementation, and an independent capable scientific reviewer. Use available
configured models; do not claim a prescribed model ran when it was unavailable.
Additional reviewers need different evidence or questions, not extra votes.

## Separate evidence levels

Use explicit labels: **reported**, **source-confirmed**, **reproduced**,
**regression-protected**, **visually accepted**. They answer different questions.
A review may be complete with unresolved findings if every finding is accounted
for; a release cannot treat those unresolved scientific risks as verified.

For a scientific task, write the independent expected result before implementation.
Choose the oracle deliberately: analytic truth, a pinned external forward model,
or a measured real dataset with stated uncertainty. Sharing code between the
fixture's inputs and expected outputs tests consistency, not correctness.
The ACOM fixture demonstrated why: a shared projection swap passed the old gate.

Negative controls must have a predicted semantic failure, not merely an exit code.
Mutation builds use isolated source copies, never the checkout that another
agent might save, stage or compile. Test the reviewer's remedy too. Keep all
expected cases, reject empty comparisons, and include asymmetric geometry.

## Make scientific state own its interpretation

The review repeatedly crosses the same boundary: a new image is published while
old units/provenance survive, a calibration parameter changes while a cached
plan survives, or display-normalized pixels are labelled as physical values.
For v3, prioritize a coherent result value that owns pixels, units, frame,
sampling, validity and provenance together. Cache keys should carry the inputs
that determine the result, rather than depend only on scattered invalidation.

This is a design direction, not authorization for a big rewrite. Retain v2's
`AppState` seam requirement while v2 is active. At v3 kickoff, assess whether
the extraction should own the responsibility the task actually changes; do not
pay the rule with unrelated refactoring. Each extraction still needs a green
boundary and tests of meaningful state transitions, including save/reopen.

## Shorten the visual feedback loop

Deliver small runnable workflows before accumulating a long acceptance queue.
Prepare the exact signed development build, staged data and short action list.
Agent screenshots/UI checks provide development feedback; they do not silently
replace the owner's acceptance or the clean-account run.

Start a sitting with an unprompted playthrough, then run the remaining explicit
contract checks. Record build identity including uncommitted changes, dataset,
steps, expected/observed result and a full-window screenshot. Free exploration
does not prove unattended replay, export/reopen or foreign-sidecar handling.
Map observations onto existing checks rather than deleting those obligations.

For S22, first resolve which proposed findings are correctness, destructive
interaction, or workflow friction. Cosmetic polish must not hide wrong scales,
ambiguous trust labels or irreversible result deletion.

## Isolate work and choose gates by evidence

Separate worktrees protect source edits, not shared preferences, containers,
Metal resources or the GUI test host. Give each run unique logs and scratch
directories, and reserve shared runtime resources explicitly. Do not drive the
app during the unit gate. Keep the free-space preflight and fail clearly on a
missing fixture or permission.

Use focused checks while iterating; run the affected scientific gates after the
independent review, and the aggregate at integration/release boundaries. State
exactly which source state each run covers. A docs-only task does not need a
ritual app build, but a changed fixture still has to be executed and broken.

## Measure whether this helps

For the first three v3 tasks, record time spent implementing, verifying,
recovering context and waiting for the owner; defects caught before versus after
the running-app review; and how much work a new agent repeats. Compare these
with the v2 recovery evidence. Do not optimize number of agents, tests or tokens
as a proxy for correctness. Use these measurements to reduce overhead, not to
remove safeguards for rare failures. Three quiet tasks cannot establish that a
science gate, independent review or visual acceptance is unnecessary. Replacing
one requires independently reviewed evidence that its failure classes remain
covered.

Decisions for v3 kickoff: adopt the compact task/evidence layout; choose the
first scientific-result ownership seam; and agree the cadence of owner visual
reviews. No change to v2 release promises is implied by this proposal.

## Working methods that earned their keep

Moved here from `docs/open-items.md` on 2026-09-07 (C1): these are process,
not defects. Kept because they changed outcomes, not because they are tidy.

### Read the gate's own exit line, never the wrapper's
A backgrounded `run-tests.sh` reported exit 0 while the gate's own `GATE_EXIT`
line said 1 (2026-09-04, the fourth time). Redirect to a log, `echo $?` on its
own line, grep the log. A `| tail` pipe reports `tail`'s status. The same day,
`git push … | tail` printed `PUSH_EXIT=0` over a failed push. And a green gate
row outlives the commit that broke it: on 2026-09-05 `scientific` was red from
02:09 (a harness check committed against a reader that never satisfied it) and
from 12:55 (a harness that no longer compiled) until the evening's rerun —
five commits quoted the morning's 43-harness green. A commit that touches a
harness's inputs reruns that harness before it quotes any gate.

### Resume a lost session from its scratchpad, not from memory
A session died mid-Gate B on 2026-09-05. Its scratchpad
(`/private/tmp/claude-501/<project>/<session-id>/scratchpad`) survived
with the pre-registration, every log and the refuter's half-run harness; the
review was finished from those, and the `git diff` was the only other truth.
Look there first; never re-derive a number a retained log already holds.

### Count a gate's tests by name, and reconcile against the expected delta
`run-tests.sh unit` passes `-quiet`, so xcodebuild prints no summary and the
count has to be grepped out of the log. The parallel runners interleave and a
`Test case '…' passed` line gets CHOPPED mid-name — twice on 2026-09-04, in
different places. `grep -c` on the whole line undercounts. Counting
`Class.method` undercounts too when the chop lands in the class name (it did:
`dedOriginSubtractsTheCropOffset…`). **Count the method alone —
`grep -oE "[a-zA-Z0-9_]+\(\)' passed" log | sort -u | wc -l` — and then
reconcile it against what you expected to change (prior total, minus deleted,
plus added).** When the two disagree, `comm` the two runs' rosters: both times
the "missing" test was a chopped duplicate of one that ran. Never conclude a
test vanished from a count alone. Same family as the `| tail` trap: the gate
was green, the number was wrong.

1. **Cost a UI change before designing it.** Measure the shape change
   (pt/rows) before choosing between options — makes it a measurement,
   not taste.
2. **Adversarially review anything touching the science, and review the
   diagnosis, not just the code.** Three times a fix has passed every
   test written for it — including one verified to fail without it — and
   still been wrong. The refuting evidence was already in a log nobody
   had re-read.
3. **Never widen a gate that fails silently.** A miss path that calls
   `recordError` and continues, or a control hidden behind a disclosure,
   turns a failure into a finding nobody reads.
4. **Open the app.** Ten minutes of driving on a day with every harness
   green has twice found defects the suite could not see. The owner's
   driving sessions replace the retired checklist because nothing else
   catches that class.
5. **A green suite can be green about the wrong thing.** Check what
   calling convention a suite actually exercises (absolute vs. relative
   paths, `$0`-relative sourcing after a `cd`) and whether that's the one
   anyone uses. Search harness runners by basename, never by path prefix
   — the same path gets spelled multiple ways across `tools/*/run.sh`.
   A backgrounded pipeline's `${pipestatus[1]}` reports the last
   command's exit code, not the gate's — put the exit code where you
   will actually read it.
6. **A test written for your own fix proves nothing until it fails
   without it.** In-process SwiftUI `Picker` menus render blank to
   automation (built lazily for a real assistive client) — a rendering
   assertion can pass while testing nothing; assert the decision instead,
   and say why at the call site.
7. **Do not drive the app while `run-tests.sh unit` is running.** Both
   suites inject private `AppStorage` into the same defaults domain; a
   live instance can spuriously redden a layout/sidebar test.
8. **Break every new test before trusting it.** Confirm each new
   assertion actually goes red on the mutation it claims to catch —
   three green-but-worthless suites were caught only this way.
