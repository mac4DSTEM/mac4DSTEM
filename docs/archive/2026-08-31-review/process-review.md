# Independent review of recovery accounting and v3 proposal

2026-08-31. Reviewed `tools/review-record-check/run.py`, the recovery manifest,
`docs/v3-development-process.md`, and the in-progress recovery record. The
reviewed checker source is retained as
`/tmp/review-record-validator-refutation/reviewed-run.py`.

No shared file edits, builds, app interaction or commits. Executed the checker
against 13 isolated JSON fixture variants and the real incomplete archive.
Raw results: `/tmp/review-record-validator-refutation/results.json` and
`live-incomplete-result.json`. Expected failures were counted by each child
process's actual return code, not the surrounding shell exit.

## Checker verdict: accounting core holds, malformed evidence is accepted

The real incomplete archive correctly returns **exit 1** because findings.json
is absent. A minimal complete baseline returns exit 0; omitted finding,
duplicate finding, omitted session and invalid finding disposition all return
exit 1. This guards the most direct repeat of the interrupted workflow.

Three actionable holes were reproduced:

1. **[P2] Evidence accepts whitespace and non-text values.**
   `run.py:39-41` only tests truthiness. A finding with evidence `"   "`, evidence
   `true`, or verificationMethod `{"no":"proof"}` passes. Claim fields at
   `:53-55` have the same weakness. Minimal fix: schema-check these fields as
   strings whose stripped length is positive; validate the outer list/object
   shapes first. This does not attempt to judge the factual truth of prose.

2. **[P2] Failed/unknown audit statuses count as completed audit evidence.**
   An audit claim with status `"usage_limit_no_review"` passes because `:54`
   accepts any truthy status. Minimal fix: define an explicit audit-disposition
   set consistent with the assembled record (including `unverified`, which is
   an honest historical disposition), and reject unknown/operational failure
   states. If a worker failed, a new reviewer can explicitly account for that
   claim as unresolved/unverified with evidence; absence of review cannot be
   smuggled through as an arbitrary status string.

3. **[P2] Duplicate/empty expected rosters are silently accepted.**
   Duplicate manifest areas collapse into the expected dict at `:26`, and
   duplicate expected sessions collapse into a set at `:44`. Both pass with the
   deduplicated counts. Empty areas/findings/sessions and initialEntries=0 also
   pass. Minimal fix: require nonempty unique area and session rosters, string
   names, and positive integer finding counts/total (reject Boolean integers).
   Validate original finding titles and list shape. The current real manifest
   correctly lists 11 areas / 75 entries / 15 sessions; the failure is in the
   validator accepting a malformed substitute.

The validator **trusts the manifest** to enumerate the intended scope. Removing
S1 from both expectedSessions and the audit passes; this is a scope limitation,
not something generic JSON validation can solve. Retain the initial manifest
with source-session identity and review its amendments. If the claim is
"all planned work accounted", expected worker IDs/scope must be fixed before
execution, not reconstructed from whichever outputs returned. A hash pin would
protect accidental scope drift, but cannot establish truth by itself.

A non-object list member currently can raise AttributeError outside the caught
exceptions. That still exits nonzero (not fail-open), but explicit schema checks
would give a readable FAIL instead of a traceback.

Do not promise that this tool verifies source citations, completed independent
reviews, original audit claim completeness, or scientific truth. It validates
one disposition per manifested finding plus at least one shaped claim per
manifested session. Its final message properly says **accounted**, and explicitly
permits unresolved findings. Keep that distinction in the proposal and final
closeout: accounting complete is not risk closure or release approval.

## V3 proposal: safeguards retained, two clarifications recommended

The proposal explicitly preserves Gate D, independent Gate B, external/analytic
oracles, negative controls, asymmetric geometry, refutation of proposed remedies,
owner visual acceptance, clean-account acceptance, free-space preflight and
runtime isolation. It explicitly does **not** replace active v2 rules or authorize
a rewrite. AppState's current seam rule is retained at lines 90-94; owner Track B
is retained at 98-107. No dropped safeguard was found in those areas.

Two small clarifications would protect against accidental weakening:

- **[P2] Do not remove safety gates based on three quiet tasks.** Lines 128-133
  propose measuring the first three tasks then simplifying/removing steps that
  do not improve observed outcomes. An independent scientific review may catch
  a rare severe defect; zero catches in three tasks does not show no value.
  Specify that these measurements optimize overhead and sequencing; removing
  standing scientific/acceptance gates needs a separately reviewed replacement
  with equivalent evidence. The current opening "What should remain" strongly
  suggests this, but an explicit limit would prevent a later literal misreading.

- **[P3] State gate obligations at integration explicitly.** Lines 121-124
  distinguish focused iteration, affected science tests and aggregate integration.
  This is sensible, but can be read as permission to call a Core task done after
  a hand-selected subset. Say required v2 gates remain unchanged; under any v3
  policy, completion/integration must use the declared gate against the final
  source state (including app unit evidence when app code changed), rather than
  allowing an author to select only green tests. The proposal already says it
  is not active policy, so this is clarification rather than a current violation.

The task/evidence layout and completed/failed/unresolved reporting are useful
responses to concrete recovery failures. The single source record, source/diff
fingerprints, original finding retention, and explicit missing-worker results
should remain. The record checker demonstrates structural accounting only;
wording should not elevate it to proof of review quality.

## Scope and outcome

This review does not approve app defects or the new ACOM gate. Those remain
separate scientific tasks. Checker hardening should be re-tested against these
same accepted-invalid fixtures: all should turn red while the valid unresolved
baseline remains green. Keep a negative-control runner or the fixture results
so this regression protection is reproducible after the scratch directory is
removed.


## Addendum — fixes re-refuted against the assembled archive

The parent hardened the checker and added the proposal caveat about rare-failure
safeguards. Re-ran the same **13 fixture variants** against checker SHA-256
`927abf330da6d920d59cc7a8b491349c4a11f048f55983825a7ec9f9ffe9ddde`:

- Valid unresolved baseline: **exit 0**.
- All **12 negative variants: exit 1**, including the formerly accepted
  whitespace/non-text evidence, arbitrary audit status, duplicate rosters and
  empty rosters. No unexpected outcome.
- The earlier three checker findings are therefore **resolved for the tested
  schema classes**. This is not a proof against every possible malformed file.

The rerunnable driver is
`/tmp/review-record-validator-refutation/probe.py`. It accepts an optional path
to the checker, retains the checker source and results under its SHA-256 prefix,
and itself exits nonzero if a negative case passes or the valid control fails.
For example, from any working directory:

```sh
python3 /tmp/review-record-validator-refutation/probe.py /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/tools/review-record-check/run.py
```

Fixed-version output and source are retained in
`/tmp/review-record-validator-refutation/927abf330da6d920/`. The initial
`results.json` / `reviewed-run.py` paths were replaced when the original driver
was reused; this addendum uses the versioned results, and the driver now avoids
that provenance ambiguity. The initial observed outcomes remain described above.

Independently reconstructed the complete expected ID/title map from every
archived initial review, without calling the checker: **75 expected / 75 actual /
75 unique**, no omitted IDs, no extra IDs and no changed original titles. All
11 archived initial JSON objects are identical to the recovered scratch inputs.
The integrated findings retain all 22 dispositions/evidence entries from this
reviewer's three areas without any field changes. All **15 expected session
names** appear once, with **208 claims** total. The actual assembled archive now
returns **exit 0**. File hashes and detailed independent comparison results are
in `/tmp/review-record-validator-refutation/assembled-accounting-result.json`.

The proposal now explicitly says that three quiet tasks cannot establish a
scientific gate, independent review or visual acceptance is unnecessary, and
replacement requires independently reviewed evidence of retained failure-class
coverage. The P2 safeguard-weakening concern is resolved. The P3 suggestion to
state integration gate obligations explicitly remains optional clarification;
the document already says it is a proposal and retains active v2 rules.

Final scope: **all manifested findings are accounted for**, not all findings are
fixed, reproduced, or scientifically approved. The manifest remains the trusted
scope input; this checker cannot verify whether every historical audit claim
was listed or whether evidence prose is true.
