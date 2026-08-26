# M1 — the tidy session (planned 2026-08-25, evening; owner-requested)

Maintenance, not release scope: it makes the discipline **cheaper, never
thinner**. Gate A. No app code, no science, no test changes, no gate
widening — `mac4DSTEM/` is untouched except by nothing at all. Runs
**before S10**; archive this file on completion.

**The measure of success is a number:** report the combined line count of
`CLAUDE.md` + `docs/v2-release.md` + `docs/open-items.md` before and after.
That sum is the tax every session pays at kickoff.

## T1 — `tools/free-space.sh` (do first; it may unblock T7)

Report-only by default; `--clear` deletes. Targets, and nothing else:
XcodeBuildMCP workspace debris (`~/Library/Developer/XcodeBuildMCP/
workspaces/*` — result-bundles, test-products, logs; 2026-08-25 alone left
~15 bundles), and this project's isolated DerivedData (see
`tools/run-tests.sh` for the path). **Never** `References/`, never the
repo, never anything it cannot name. Print `df -g /` before and after.
Not added to any gate.

## T2 — §9 compression (move, never reword)

For S1–S8: move each record **verbatim** to
`docs/archive/v2-session-records/s<N>.md`; leave ≤ ~12 lines in §9 —
date, two-line ship statement, gate + outcome, deviation count, the Track A
exit codes, "not verified" in one line, and the archive pointer. The
records are frozen history: compression is relocation, not editing. A
future claim question resolves at the archive file, so lose nothing.

## T3 — open-items pruning (enforce the file's own §1 rule)

Move struck-through/closed entries to
`docs/archive/closed-items-2026-08.md`. Where a live item leans on a
closed one, leave a one-line tombstone with the archive pointer. Live
entries byte-preserved.

## T4 — CLAUDE.md refresh

Rewrite "Where things stand" as current truth instead of stacked
amendments: v1.0.0 public; S0–S8 done; the honest test claim as of
2026-08-25 — `scientific` exit 0 over **36** harnesses, MCP app suite
363/2 (S17 sidebar intermittent + retired UI target), `all` still never
run end-to-end on this machine, sidebar → S17. Fix stale counts (35→36).
De-duplicate the kickoff block against `/pickup` + §8 — keep ONE canonical
copy, point the others. Net length must go DOWN.

## T5 — promote the S8 test lesson into shared process

One paragraph in `docs/development-process.md` (gates section) and one
line in `.claude/skills/adversarial-review/SKILL.md` step 1b:
*mutation-passing suites can still be collectively blind at symmetric test
constants — geometry/rotation tests pin sign-discriminating angles (37.2°,
not 90°) and carry an in-test guard proving the wrong variant differs on
the fixture* (S8, 2026-08-25: three reviewer mutations survived a
15-mutation pass this way).

## T6 — resequencing note in `docs/v2-release.md`

One dated line: S10's dependencies (S5, S8) are met; chosen order
**S10 → S21 → S17**, S9 when NAS access and disk allow, TB1 sittings 2–4
whenever the owner sits. No other §8 edits.

## T7 — the owed `unit` re-run (only if T1 freed ≥ 8 GB)

`tools/run-tests.sh unit`, exit code read directly, full log retained.
Expected honest outcomes per the closeout skill: exit 0, or exit 65 with
exactly the S17 intermittent (add the heights to S17's observation log),
or exit 69 recorded if space is still short. Never touch the floor.

## Refusals standing for this session

- History is moved, never reworded — a compression that edits a frozen
  record is a falsification, not a tidy.
- No "while I'm here" fixes: anything discovered goes to
  `docs/open-items.md` with an owner, exactly as Track B findings do.
- The kickoff-tax number goes in the closeout summary, before/after.
