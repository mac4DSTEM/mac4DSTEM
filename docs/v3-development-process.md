# v3 development process — proposal from the v2 review

Prepared 2026-08-31 at the owner's request. This is the proposed v3 operating
model, not a replacement for the active v2 gates or a new feature commitment.
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
