# 030 — Lessons promoted from the archive

Dates: 2026-08-25 through 2026-09-16 (as recorded in the cited files); promoted 2026-09-16
Status: live

## Decision
Eleven rules found only in archive files, with no live doc restating them,
promoted here in substance. **A** (`v2/development-process-v2.md`,
`v2/v2-scope.md`): (1) mutation-tested suites can be *collectively* blind at
symmetric constants — pinning exactly 90° let a wrong sign and a dropped
transpose both survive a 15-mutation suite; pin sign-discriminating values
(37.2°, not 90/45/0) with a guard proving the variant differs. (2) the
model tier table — Haiku locate/search, Opus design/adversarial review,
Sonnet implementation — "never let the model that wrote a science change be
the only one that approves it." (3) the fabrication clause: "nothing ships
that can fabricate a scientific result, and no gate is widened to make
something pass." (4) `AppState` extraction ranks by state ownership, not
MARK-line count (refuted same-day: 172 of ~188 stored properties predated
the first MARK).

**B** (`v3/ai-gateD-2026-09-06/gateD-C1.md`, `gateD-A2.md`;
`v3/phase-mapping-2026-09-12.md`; `v3/step3-2026-09-16.md`): (5)
`Swift.max(0, .nan) == 0.0` silently breaks any threshold check assuming NaN
propagates — bitten twice (FFT2D, PCA eigensolver). (6) `nonisolated` on a
class does not extend to a member in a *different file's* `extension` —
stays `@MainActor`, caused a real freeze. (7) never edit `run-tests.sh` (or
a source it compiles) while a gate runs elsewhere — a half-written file
reads and dies looking like a tree failure. (8) the matrix explained-fraction
fall-back stays off (0) by default; ship the reported quantity, not a
verdict-changing threshold.

**C** (`v2-onramp.md`; `2026-08-31-comparator-gate-b.md`;
`tidy-session-plan.md`): (9) a too-tight tolerance fails loudly, a too-loose
one fails silently — never widen a gate whose failure mode is a fabricated
result. (10) a gate stopping at the first red cannot tell you how many
others are red — an early-abort hid a second broken harness for a whole
commit. (11) archival moves must be verbatim: "a compression that edits a
frozen record is a falsification, not a tidy."

## Why
Each is a refinement or distinct failure mode of a rule already live, not a
missing rule those docs entirely lack — reasons given inline above.

## Governs
`Core/` numerical routines (rule 5); cross-file `extension`s under
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (rule 6); Gate D mutation
testing; `docs/archive/` moves; `tools/run-tests.sh all`/`campaign`.

## Sources
`docs/archive/v2/development-process-v2.md` §2,§7 (1,2,4); `v2/v2-scope.md`
§4 (3); `v3/ai-gateD-2026-09-06/gateD-C1.md` §1 (5); `gateD-A2.md` §1,§5 (6);
`v3/phase-mapping-2026-09-12.md` §"A trap paid here" (7);
`v3/step3-2026-09-16.md` §"The matrix explained fraction is reported…" (8);
`v2-onramp.md` §"Methods that earned their keep" (9);
`2026-08-31-comparator-gate-b.md` §"The second red harness…" (10);
`tidy-session-plan.md` §"Refusals standing for this session" (11). All
under `docs/archive/`.
