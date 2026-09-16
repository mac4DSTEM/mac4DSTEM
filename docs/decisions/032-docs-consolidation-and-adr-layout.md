# 032 — Docs consolidation and the ADR layout

Dates: 2026-09-16 (audit and consolidation), 2026-09-17 (closeout)

Status: live

## Decision

The live documentation is five files plus reference specs: `CLAUDE.md` (one
page, only the rules code cannot enforce), `docs/status.md` (the handoff and
the dated gate table), `ROADMAP.md` (the feature plan, absorbing `v3-plan.md`),
`docs/open-items.md` (defects and debts, ≤ 12 lines each), and
`docs/decisions/` — one file per decision with `docs/decisions.md` as its
index — replacing the append-only `decisions.md` log. `docs/architecture.md`
and `docs/releasing.md` keep their paths and roles. Every record that left a
live doc went to `docs/archive/` verbatim, with one header line, diff-proven
against `git show HEAD:`.

## Why

The 2026-09-16 audit (`docs/archive/audit-2026-09-16/REPORT.md`) found the
Gate D trigger stated in nine places, the refuter rule in eight, three stale
facts at the top of `CLAUDE.md`/`ROADMAP.md`/`architecture.md` (v3.0.0 "not
yet cut" after it shipped; the overruled C5 form), two skills contradicting
the 2026-09-16 commit rule, and 41 of 77 open items over their own 12-line
rule. A fresh-eyes read of the code alone recovered every rule a gate holds
(layering, UI greps, manifest, NOTICE hashes, size report) and none of the
process rules, which is the line `CLAUDE.md` now draws. A 1 579-line log
cannot be cited, superseded or reviewed one decision at a time; a folder can.

## Consequences / what it governs

- A new decision is a new `NNN-*.md` and one index row; the pre-2026-09-16
  log is `docs/archive/decisions-log-2026-08-17-to-2026-09-16.md`.
- `run-tests.sh inventory` counts `docs/decisions/*.md` in the live-markdown
  metric and its dead-path check (added the same day), so the folder cannot
  escape measurement. Live markdown 7 106 → 5 072; cold-start set 2 148 → 978.
- Paths deliberately kept: `docs/architecture.md` (not a root
  `ARCHITECTURE.md`), the reference specs stay directly under docs/ (no reference subfolder) —
  the citation churn and gate edits were not worth a cosmetic move.
- The audit's evidence lives at `docs/archive/audit-2026-09-16/`; its refactor
  list §3.2 rows 4–13 are the open code-hygiene queue (`docs/open-items.md`).

## Sources

- Commits `0d7470d` (docs consolidation) and `e415929` (hygiene slice), 2026-09-17.
- `docs/archive/audit-2026-09-16/REPORT.md` §1 (the plan applied), §2 (fresh-eyes diff), §3 (metrics).
