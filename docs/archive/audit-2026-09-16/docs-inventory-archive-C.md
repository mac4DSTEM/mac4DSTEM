# Docs inventory — archive C: `docs/archive/*.md` (top level, no subfolders)

Scope: the 16 tracked `.md` files directly under `docs/archive/` — confirmed
by `git ls-files 'docs/archive/*.md' | grep -v '/.*/.*/'` (not 18 as the
brief estimated; 16 files, 8 352 lines, matching the ~8 350 estimate almost
exactly). Read-only audit, one of four covering the repo's markdown. Other
agents cover the live docs and every `docs/archive/` subfolder (`v1.0/`,
`v2/`, `v3/`, `2026-08-31-review/`, `2026-09-09-review/`, `fresh-eyes/`,
etc.) — this file cites into those only where an in-scope file links there.

**Context read first:** `CLAUDE.md`, `docs/status.md`, `docs/architecture.md`
(full), `docs/development-process.md` (full), `docs/open-items.md` (full,
including its heading structure), `docs/decisions.md` (headings from
`grep -n '^##'`, which only finds entries from 2026-09-11 on — earlier
decisions back to 2026-08-17 are bold-prose paragraphs, not headers, so those
were read directly wherever an in-scope file's content needed checking
against them).

**Method.** `cited-by` was built by grepping the 33 live `.md` files (every
tracked `.md` outside `docs/archive/`, including `AGENTS.md`, `CHANGELOG.md`,
`README.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `docs/v3-*.md`, `docs/ai-ml/*`,
`tools/*/README.md`) and the four `.claude/skills/*/SKILL.md` files for each
in-scope file's basename, then a second pass over all 121 tracked `.md` files
repo-wide to catch archive-to-archive citations (including the out-of-scope
`docs/archive/v2/`, `v3/` folders). A shell gotcha cost real time here and is
worth recording: this environment's `grep` is a zsh function wrapping
`ugrep`, and bare `$var` expansion in zsh does **not** word-split (unlike
bash) — an unquoted multi-line variable passed to a for-loop or to `grep`
silently became one argument instead of many, at first making every citation
check report zero hits. Fixed with `${(@f)$(...)}` array expansion and
`command grep` throughout. Table 5's broken-citation check resolves relative
links (`../open-items.md` from a file under `docs/archive/`) and tries a
`mac4DSTEM/` prefix before calling a path broken, to avoid false positives
from the common informal convention of citing Swift files relative to the
app-source root.

## Table 1 — one row per file

| path | lines | class | cited-by | duplicate-of / superseded-by | verdict | note |
|---|---|---|---|---|---|---|
| `2026-08-18-trackb-036-and-followups.md` | 673 | status/history | — (archive only: `archive/v2/open-items-2026-09-02.md`, `archive/v2/v2-ship-plan.md`) | none — unique full record; live residuals were extracted into `open-items.md` without a direct link back | →archive (stays as is) | 2026-08-18 Track B pass on the 4.25 GB `036` cube plus every follow-up appended through 2026-08-29. Self-declared "everything here is history and evidence. Do not tick or amend." |
| `2026-08-31-comparator-gate-b.md` | 127 | gate-evidence | — (archive only: `archive/v2/open-items-2026-09-02.md`, `archive/v2/v2-release.md`) | none | →archive (stays as is) | Small and dense. Three-refuter Gate B campaign on `compare.py`/`main.swift`. Carries two rules not captured live — Table 3. |
| `2026-09-01-trackb-playthrough.md` | 681 | status/history | in-scope archive: `archive/qc-run-findings-2026-08.md` (cites it in its own preamble, verified not a false match); also `archive/v2/open-items-2026-09-02.md`, `archive/v2/v2-release.md` | live residuals summarized (and since closed) under `open-items.md`'s now-archived "Track B playthrough — 2026-09-01" entry | →archive (stays as is) | Nine session entries kept verbatim on purpose — several record *how a diagnosis converged or was retracted*, which the live log format cannot hold. |
| `2026-09-11-ai-port-analysis.md` | 313 | decision | **`docs/decisions.md:900`** ("Plan and evidence: `archive/2026-09-11-ai-port-analysis.md`") — live, required to exist; also `archive/v3/ai-port-2026-09-11.md` | none — its "Step 0" three pending owner decisions are all fully recorded live, immediately after the citing line (`decisions.md:890-920`, three 2026-09-11 entries) | →archive (stays as is) | Required by the hard rule. Checked for an ADR gap and found none: every decision this file posed as open was decided and logged the same day, including one where the owner explicitly overruled the file's own recommendation (sixth "AI Analysis" workspace vs. the analysis's recommended (b)). |
| `audit-master-prompt-fable5.md` | 1105 | stale | — (archive only, mutual with `v2-onramp.md`; also `archive/v2/post-v1-ideas.md`) | its evidence-tag model (`[ran]`/`[read]`/`[blocked]`/`[not-run]`/`[inferred]`) superseded by `development-process.md`'s "Separate evidence levels" (reported/source-confirmed/reproduced/regression-protected/visually-accepted); its audit/roadmap purpose superseded by `docs/v3-plan.md` | →archive (stays as is) | Self-declared obsolete ("ARCHIVED 2026-08-06 — do not run this"). Its own header argues explicitly for archiving over deletion: its "Precedence over repository documents" section asserts authority over `CLAUDE.md` itself, and an unreferenced, un-warned copy loose in `docs/` would be "the single most misleading file for anyone... opening the repo cold." Verdict respects that reasoning. |
| `closed-items-2026-08.md` | 1127 | status/history | — (in-scope archive: `archive/open-items-2026-09-07.md`, `archive/tidy-session-plan.md`; out-of-scope: `archive/v2/README.md`, `archive/v2/open-items-2026-09-02.md`, `archive/v2/v2-release.md`) | none — unique verbatim record, not restated | →archive (stays as is) | Largest closed-item ledger by item count: 28 items, all Aug 2026. 8 broken evidence-path citations (Table 2/5). |
| `closed-items-2026-09.md` | 1008 | status/history | `CHANGELOG.md`, `docs/decisions.md`, `docs/open-items.md`, `docs/status.md` — live, required to exist | none | →archive (stays as is) | Required by hard rule. 25 items, Sept 2026 through the v3.0.0 closeout. Cleanest of the three lineage files: 0 broken evidence-path citations found. |
| `code-review-2026-07-19.md` | 270 | decision | — (in-scope archive: `archive/implementation-prompts-2026-07-19.md`, its companion) | none | →archive (stays as is) | Full-codebase v1-era review; "Execution record" closed out by the companion prompts file. All items executed, v1.0.0 shipped. |
| `consolidation-plan.md` | 697 | gate-evidence | `CLAUDE.md`, `docs/decisions.md` (×3), `docs/status.md`, `docs/v3-plan.md` (×2), `.claude/skills/pickup/SKILL.md`, `.agents/skills/pickup/SKILL.md` — live, heavily required | none — the C0–C8 gate detail (exit criteria, what each closed on, evidence pointers) exists only here | →archive (stays as is) | Required by hard rule. **§7 verified checked line by line — see summary.** The most-cited file in scope by a wide margin. |
| `implementation-prompts-2026-07-19.md` | 228 | howto | — (in-scope archive: `archive/code-review-2026-07-19.md`, its companion) | none | →archive (stays as is) | Companion pair; all 4 prompts executed in order, each a fresh session. |
| `open-items-2026-09-07.md` | 691 | status/history | `docs/open-items.md` — live, required to exist | its tail section, "Working methods that earned their keep" (lines 622–691, 11 sub-entries), is verbatim-duplicated in `docs/development-process.md` — it was moved there by the very C1 session this file is a pre-image of | →archive (stays as is) | Required by hard rule. The "before the C1 trim" snapshot. See Table 2 and Table 4. |
| `qc-run-findings-2026-08.md` | 585 | status/history | `docs/py4dstem-pipelines.md` §9–10 (now a two-line stub pointer) — live, required to exist | is itself the verbatim relocation of `py4dstem-pipelines.md`'s old §9/§10 (held until 2026-09-07); the live doc no longer has that content at all, only the pointer | →archive (stays as is) | Required by hard rule. Cites in-scope `archive/2026-09-01-trackb-playthrough.md` in its own preamble. |
| `s1-sidecar-under-the-sandbox.md` | 385 | gate-evidence | — (in-scope archive: `archive/closed-items-2026-08.md:149`, "A sidecar that opens fine could fail to restore — closed 2026-08-19 (S1)," the condensed twin of this full investigation) | `closed-items-2026-08.md:149-164` (short form); this file is the full investigation, kept because "the method is the valuable part" | →archive (stays as is) | **Notable finding:** line 31 calls its refuted concurrency-race hypothesis "a third instance of this repo's documented failure mode, and the reason the rule is *review the diagnosis, not just the code*" — this file is very likely the primary evidence behind CLAUDE.md's "three confident wrong diagnoses" Gate D rationale, even though nothing live cites it by path. Its own internal citation to `docs/v2-release.md §9` is now broken (file moved to `archive/v2/v2-release.md`) — Table 5. |
| `tidy-session-plan.md` | 77 | howto | — (archive only: `archive/v2/v2-release.md`) | T5's lesson is now live verbatim in `.claude/skills/adversarial-review/SKILL.md:31` ("pin sign-discriminating angles (37.2°, not 90°)..."); T1–T4, T6–T7 are completed one-off maintenance tasks recorded elsewhere (`closed-items-2026-08.md`, git history) | **delete** | Fully executed 2026-08-25 maintenance checklist ("archive this file on completion" — its own instruction). T5 explicitly asked for a paragraph in *both* `development-process.md`'s gates section *and* the skill; only the skill got it — `development-process.md` never received its copy, a minor loose end but not one this uncited 77-line file needs to stay alive to fix. |
| `training-dataset-evaluation-2026-07-15.md` | 98 | gate-evidence | — (archive only, out-of-scope: `archive/v2/development-history.md`) | none found; superseded in spirit by the later, broader `qc-run-findings-2026-08.md` and by ongoing `tools/performance-baseline/` work, but no doc restates its specific numbers | →archive (stays as is) | Oldest and smallest file in scope. Unique record of the first optimization pass (148.20 s → 18.90–33.28 s; the 125×125 Au Bragg path 111.01 s → 2.92–3.49 s). |
| `v2-onramp.md` | 287 | status/history | — (in-scope archive, mutual: `archive/audit-master-prompt-fable5.md`; out-of-scope: `archive/v1.0/ui-implementation-prompts.md`, `archive/v1.0/ui-workflow-backlog.md`) | its own header: superseded for status by `docs/open-items.md`, for planning by `archive/v2/load-pipeline-plan.md`; "kept for its scope decisions and its account of working methods, both still current" | →archive (stays as is) | v1→v2 handover doc. The "still current" self-claim checks out for the tolerance-direction lesson (Table 3) but not for much else — most of its scope decisions are superseded by later plans. |

## Table 2 — Closed-items lineage

| File | item count | appears in 2+ of these files / live `open-items.md` (same id or title) | closed items citing evidence paths that no longer exist |
|---|---|---|---|
| `closed-items-2026-08.md` | 28 (`##`-level entries; one heading, "Compaction, 2026-08-28," is a group label for four of the other 27, not a 29th item) | 0 — Aug items were all closed and archived before the 2026-09-07 snapshot existed, so there is no overlap window with the other two files or with current `open-items.md` | ~8 (see Table 5: `App/SessionSidecarLocator.swift` ×1, `References/training_dataset/sim_Au_data_all_binned.h5`, `UI/ScaleBarView.swift`, `UI/ProductWorkspaceViews.swift`, `mac4DSTEM/App/ContentView.swift`, `mac4DSTEM/Platform/HDF5/H5Reader.swift`, `mac4DSTEM/Core/Export/ResultExport.swift`, `docs/load-pipeline-plan.md`) |
| `closed-items-2026-09.md` | 25 (`##`-level entries, including 3 group labels — "Four entries archived 2026-09-07," "Verification debt," "Closed at the v3.0.0 closeout" — whose members are counted individually via their `###` sub-headings) | 11 — every item under the "(archived 2026-09-07)" tag (S17 sidebar, sidebar drag crash, unit-level column-width gate, presentation-contract residuals, columns' material, cross-frame recipe export, S1's crop restore, sidecar contents to LEFT sidebar, status-bar elapsed/throughput/ETA, UI review labels, four Python scripts) also appears by the same title in `open-items-2026-09-07.md` — expected, since C1 closed them out of that exact snapshot the same day | 0 — the one candidate (`../open-items.md` at five lines) resolves correctly as a relative link to `docs/open-items.md` and is not actually broken |
| `open-items-2026-09-07.md` | 46 dated defect/debt items (49 `###` headings total, minus the 3 "Working methods" process entries at the tail, which are methodology, not items) | ~42 of 46 — roughly 31 persist under the same or near-same title in the live `docs/open-items.md` (still open), and 11 were closed into `closed-items-2026-09.md` the same day (C1). This is the expected shape of an unclosed-items snapshot, not a documentation defect: items don't duplicate, they *persist* until closed. A small number evolved rather than matching exactly (e.g. "ACOM omits py4DSTEM's `power_radial` weighting" → live's "`power_radial` is absent from the port, with no DEVIATION note"; the `.icns` item was explicitly reopened with a new title per the C1 record) | ~2 (`App/SessionGates.swift`, `real-data-acceptance/run.sh`) |

## Table 3 — Rules or decisions that live ONLY in your scope

| rule/decision | archive path#section | why it might still be load-bearing |
|---|---|---|
| A too-tight tolerance fails loudly, a too-loose one fails silently — **never widen a gate whose failure mode is a fabricated result**; use a file's precision to *explain* a rejection, never to *grant* an admission. | `v2-onramp.md` §"Methods that earned their keep" | Sharper than the live rule it's a special case of (`development-process.md`'s "Never widen a gate that fails silently," itself promoted from `open-items-2026-09-07.md`). Verified absent from every live doc by grep on "fabricated result" and "too-tight" / "too-loose." Directly useful the next time someone is tempted to loosen an `abs_tol`/`rel_tol` to make a suite pass. |
| A gate that stops at the first red cannot tell you how many others are red — `run-tests.sh all` aborting at the first failing harness hid a second, independently-broken harness (`package-test`) for an entire commit whose message claimed "40 harnesses, zero FAIL lines." | `2026-08-31-comparator-gate-b.md` §"The second red harness, hidden behind the first" | Verified absent from every live doc (grep "stops at the first red"). Directly relevant to CLAUDE.md's own pipe/exit-code discipline (three swallowed-gate incidents are named there) but names a distinct failure mode — an aggregate gate's early-abort behavior masking unrelated breakage — that the live rule doesn't cover. |
| **Why** archival moves must be verbatim, not reworded: "a compression that edits a frozen record is a falsification, not a tidy." | `tidy-session-plan.md` §"Refusals standing for this session" | The *practice* (every archive file in this repo says "moved verbatim," "History, not guidance") is followed with total consistency across all 16 in-scope files and beyond, but the explicit reasoning for why is stated only here. Verified absent live (grep "falsification," "moved, never reworded"). Worth promoting if `development-process.md` or `CLAUDE.md` ever needs to justify the rule to a new agent tempted to "clean up" an archive file's prose while moving it. |

## Table 4 — Live facts repeated in your scope

| fact | live path#section | archive path#section |
|---|---|---|
| Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` — nil by decision, not dormant. | `CLAUDE.md` §Hard rules | `open-items-2026-09-07.md:242-246` ("Dropped by decision (v2 S3, 2026-08-19), not dormant — do not set `ResidencyAdmission.measuredWorkingSetFraction`...") — this is the fuller original statement the terse CLAUDE.md line was distilled from. |
| The eleven "working methods" — read the gate's own exit line never the wrapper's; resume a lost session from its scratchpad; count a gate's tests by name and reconcile; cost a UI change before designing it; adversarially review anything touching the science; never widen a gate that fails silently; open the app; a green suite can be green about the wrong thing; a test written for your own fix proves nothing until it fails without it; do not drive the app while `unit` is running; break every new test before trusting it. | `docs/development-process.md` §"Working methods that earned their keep" (its own header: "Moved here from `docs/open-items.md` on 2026-09-07 (C1)") | `open-items-2026-09-07.md:622-691` — the verbatim pre-move source; essentially byte-identical to the live section. |
| **Review the diagnosis, not the diff/code** — the model that wrote a change never approves it alone; this repo has shipped confident wrong diagnoses that passed every test written for them. | `CLAUDE.md` §Hard rules ("Review the diagnosis, not the diff... this repo has shipped three confident wrong diagnoses...") | `s1-sidecar-under-the-sandbox.md:29-32` ("...a third instance of this repo's documented failure mode, and the reason the rule is *review the diagnosis, not just the code*") — one of the three concrete instances behind the live rule's "three" count. |
| Break every new test before trusting it. | `CLAUDE.md` §Hard rules; `development-process.md` item 8 of the working-methods list | `open-items-2026-09-07.md:689` (source of the working-methods copy above) and independently re-invoked as standing practice in `2026-09-11-ai-port-analysis.md:216` ("Break every new test before trusting it, including the ported ones..."). |
| Gate D: diagnosis, refuting observation, predicted outcome, experiment, before the fix; independent refuter after; a fixture. | `CLAUDE.md` §Hard rules; `development-process.md` | `2026-09-11-ai-port-analysis.md:214` restates the sequence verbatim while applying it to a specific `isFinite` guard decision, and `s1-sidecar-under-the-sandbox.md` is a full worked example of the same sequence (five hypotheses, a pre-registration, a Gate B correction). |

## Table 5 — Broken citations inside your scope

**Total: 66 repo-rooted-looking paths cited in-scope that do not resolve** (as
literal text, with `mac4DSTEM/` prefix, or as a relative link from the citing
file's own directory). None of these violate the CLAUDE.md hard rule, which
binds **live** truth docs only — every one of the 66 sits inside a file whose
own header already says "History, not guidance" / "ARCHIVED." They fall into
five clean categories, illustrated below (40 of 66 rows; the rest repeat the
same four patterns):

1. **Archival path drift** (the large majority): old docs cite `docs/X.md`,
   which has since been moved to `docs/archive/v2/X.md` by the very
   consolidation these files describe. Expected decay in a historical
   document, not a defect.
2. **Self-flagged as absent, by the citing document itself**
   (`2026-09-11-ai-port-analysis.md`'s `fix-a/gateD-A2.md` etc.): the doc is
   quoting broken citations it found on another branch as a *finding*, and
   says so in the same sentence ("neither exists in either tree").
3. **Pre-rewrite source files**: `UI/ScaleBarView.swift`,
   `UI/ProductWorkspaceViews.swift` etc. name files from before the
   2026-09-04 SwiftUI rebuild (`architecture.md`: "`UI/` was rebuilt from
   scratch... the AppKit-hosted window it replaced was deleted the same
   day"). Confirmed gone via `find`.
4. **A retired test target**: `mac4DSTEMUITests/...` paths — that target no
   longer exists (confirmed: `ls mac4DSTEMUITests` → no such directory),
   consistent with Track B/QC-playthrough retirement dated in
   `development-process.md`.
5. **Gitignored data**: `References/training_dataset/*.h5` — `References/`
   is deliberately gitignored (`CLAUDE.md`'s own front matter); these are
   dataset filenames in prose, not tracked-repo evidence paths.

| cited path | citing file:line |
|---|---|
| `docs/visual-acceptance-checklist.md` | `2026-08-18-trackb-036-and-followups.md:63` |
| `App/SessionGates.swift` (now `mac4DSTEM/Session/SessionGates.swift`) | `2026-08-18-trackb-036-and-followups.md:248` |
| `package-test/run.sh` | `2026-08-31-comparator-gate-b.md:108` |
| `docs/visual-acceptance-checklist.md` | `2026-09-01-trackb-playthrough.md:27` |
| `docs/v2-release.md` (now `docs/archive/v2/v2-release.md`) | `2026-09-01-trackb-playthrough.md:48` |
| `App/SessionSidecarLocator.swift` (now `mac4DSTEM/Session/SessionSidecarLocator.swift`) | `2026-09-01-trackb-playthrough.md:63` |
| `docs/v2-triage-2026-09-01.md` (now `docs/archive/v2/v2-triage-2026-09-01.md`) | `2026-09-01-trackb-playthrough.md:596` |
| `fix-c/gateD-C3.md` *(self-flagged: "neither exists in either tree")* | `2026-09-11-ai-port-analysis.md:63` |
| `fix-b/gateD-P6.md` *(self-flagged)* | `2026-09-11-ai-port-analysis.md:63` |
| `References/training_runs/.../fix-c/gateD-C1.md` *(self-flagged gitignored)* | `2026-09-11-ai-port-analysis.md:64` |
| `fix-a/gateD-A2.md` *(self-flagged: "matches neither" branch)* | `2026-09-11-ai-port-analysis.md:67` |
| `docs/archive/2026-08-31-review/independent-acom-mutations/results.json` (actual path has an extra `test-evidence/` segment) | `2026-09-11-ai-port-analysis.md:87` |
| `docs/v1-scope.md` (now `docs/archive/v2/v1-scope.md`) | `audit-master-prompt-fable5.md:3` |
| `docs/audit/EXECUTIVE_SUMMARY.md` *(deliverable template path for the obsolete prompt's own future output)* | `audit-master-prompt-fable5.md:51,56,1019,1048` |
| `docs/audit/AUDIT.md` *(same)* | `audit-master-prompt-fable5.md:239,328,407,463,1017,1022` |
| `docs/VERSION_1_ROADMAP.md` *(same)* | `audit-master-prompt-fable5.md:1018,1036` |
| `docs/DEVELOPMENT_SPECIFICATION.md` *(same)* | `audit-master-prompt-fable5.md:1020,1061` |
| `App/SessionSidecarLocator.swift` | `closed-items-2026-08.md:156` |
| `References/training_dataset/sim_Au_data_all_binned.h5` *(gitignored)* | `closed-items-2026-08.md:632` |
| `UI/ScaleBarView.swift` *(pre-rewrite)* | `closed-items-2026-08.md:726` |
| `UI/ProductWorkspaceViews.swift` *(pre-rewrite)* | `closed-items-2026-08.md:745` |
| `mac4DSTEM/App/ContentView.swift` (now `mac4DSTEM/UI/ContentView.swift`) | `closed-items-2026-08.md:1044` |
| `mac4DSTEM/Platform/HDF5/H5Reader.swift` (now under `Core/Data/`) | `closed-items-2026-08.md:1045` |
| `mac4DSTEM/Core/Export/ResultExport.swift` (now `mac4DSTEM/Support/ResultExport.swift`) | `closed-items-2026-08.md:1045` |
| `docs/load-pipeline-plan.md` (now `docs/archive/v2/load-pipeline-plan.md`) | `closed-items-2026-08.md:1076` |
| `Shaders/DiskCorrelation.metal` (now `mac4DSTEM/Shaders/DiskCorrelation.metal`) | `code-review-2026-07-19.md:116` |
| `tools/ui-smoke-test/run.sh` *(deleted; per `consolidation-plan.md` C2, this tool was removed)* | `code-review-2026-07-19.md:268` |
| `Models/DiskDetector/disk-detector-heatmap-b32.json` (directory exists; this exact filename does not) | `consolidation-plan.md:163` |
| `App/SessionGates.swift` | `open-items-2026-09-07.md:454` |
| `real-data-acceptance/run.sh` (actual path is under `tools/`) | `open-items-2026-09-07.md:573` |
| `tools/ui-qc-playthrough/run.sh` *(deleted; QC playthrough retired 2026-08-17)* | `qc-run-findings-2026-08.md:189` |
| `mac4DSTEMUITests/Support/ParityRecords.swift` *(retired test target)* | `qc-run-findings-2026-08.md:315` |
| `docs/v2-release.md` | `s1-sidecar-under-the-sandbox.md:14` |
| `docs/load-pipeline-plan.md` | `s1-sidecar-under-the-sandbox.md:96` |
| `References/training_dataset/sim_Au_data_all_binned.mac4dstem.h5` *(gitignored)* | `s1-sidecar-under-the-sandbox.md:305` |
| `App/SessionSidecarLocator.swift` | `s1-sidecar-under-the-sandbox.md:333,351` |
| `docs/v2-release.md` | `tidy-session-plan.md:9,58` |
| `docs/load-pipeline-plan.md` | `v2-onramp.md:7` |
| `docs/post-v1-ideas.md` (now `docs/archive/v2/post-v1-ideas.md`) | `v2-onramp.md:20,167,287` |
| `docs/v2-scope.md` (now `docs/archive/v2/v2-scope.md`) | `v2-onramp.md:47` |
| `docs/visual-acceptance-checklist.md` *(deleted; retired 2026-09-03 per `architecture.md`)* | `v2-onramp.md:51` |

*(26 more rows omitted, all repeats of the five categories above — mostly
further `docs/v1-scope.md` / `docs/post-v1-ideas.md` hits in `v2-onramp.md`,
and further `mac4DSTEMUITests/`, `UI/TaskPrerequisiteChecklist.swift`
pre-rewrite hits.)*

## Table 6 — Totals

| | files | lines |
|---|---|---|
| **Total in scope** | 16 | 8 352 |
| →archive (stays as is) | 15 | 8 275 |
| delete | 1 (`tidy-session-plan.md`) | 77 |
| →ADR | 0 | 0 |
| keep→CLAUDE.md | 0 | 0 |
| keep→ARCHITECTURE.md | 0 | 0 |

No file in this scope qualifies for `→ADR`: every decision embedded in these
16 files that is still load-bearing was checked against `docs/decisions.md`
and found recorded there (most thoroughly for `2026-09-11-ai-port-analysis.md`,
whose three "owner decisions, no code" are all logged the same day, one of
them overruling the file's own recommendation). No file qualifies for
`keep→CLAUDE.md` or `keep→ARCHITECTURE.md`: the three standing rules found
only in-scope (Table 3) are refinements/rationale for rules that already
exist live, not missing rules those documents lack entirely — promoting them
is a judgment call for the owner, not a mechanical fix this audit performs.
