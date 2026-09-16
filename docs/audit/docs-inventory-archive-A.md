# Docs inventory — archive A: `docs/archive/v1.0/` + `docs/archive/v2/`

Scope: every tracked `.md` under `docs/archive/v1.0/` and `docs/archive/v2/`
(23 files, 12 169 lines — close to the 12 200 estimate). Read-only audit, one
of four covering the repo's markdown. Context docs read first: `CLAUDE.md`,
`docs/status.md`, `docs/architecture.md`, `docs/development-process.md`,
`docs/open-items.md`, `docs/decisions.md` (headings + full read of the parts
overlapping this scope's era, 2026-08-17 through 2026-09-06).

**Method.** `cited-by` was built by grepping every live `.md` (outside
`docs/archive/`), the four `.claude/skills/*/SKILL.md` files, and the six
top-level `.md` files for each archive file's basename. A second pass grepped
all 88 tracked files under `docs/archive/**` for the same basenames, to catch
archive-to-archive citations. `docs/decisions.md` turned out to log real
decisions back to 2026-08-17 in bold-prose entries (`**2026-08-17 — …**`),
not markdown headers, so a header-only grep undercounts it — it was read in
full for the date range this scope covers.

## Table 1 — one row per file

| path | lines | class | cited-by | duplicate-of / superseded-by | verdict | note |
|---|---|---|---|---|---|---|
| `v1.0/qc-playthrough-prompts.md` | 236 | howto | — (archive: `ui-implementation-prompts.md`, `qc-run-findings-2026-08.md`, `v2-onramp.md`) | superseded by `ui-implementation-prompts.md` (file says so at line 55: "The active phase is now…") | →archive (stays as is) | Eval-only QC harness prompts, all four ticked done. Unique run-folder pointers, not restated live. |
| `v1.0/ui-design-pass-2026-08-05.md` | 415 | decision | — (archive: `ui-implementation-prompts.md`, `ui-workflow-backlog.md`) | outcome folded into `ui-workflow-backlog.md` §"Design-pass items"; investigated bug moot since the AppKit shell it diagnoses was deleted 2026-09-04 (`decisions.md`) | →archive (stays as is) | Unique measured investigation (sidebar scroll-offset mechanism); not restated anywhere, just moot now that the code is gone. |
| `v1.0/ui-implementation-prompts.md` | 839 | howto | — (archive: `qc-playthrough-prompts.md`, `ui-design-pass-2026-08-05.md`, `v2-onramp.md`, `load-pipeline-plan.md`) | its Status checklist duplicates `ui-workflow-backlog.md`'s item list | →archive (stays as is) | Session-kickoff prompts for v1's fix phase; superseded process-wise by `v2-scope.md`/`v2-release.md` but content is unique history. |
| `v1.0/ui-workflow-backlog.md` | 2680 | status/history | — (archive: `ui-design-pass-2026-08-05.md`, `open-items-2026-09-02.md`) | superseded by `docs/open-items.md` (live open items) and `docs/decisions.md`; findings resolved in code, not in another doc | →archive (stays as is) | **Largest file in scope.** ~46 numbered items, nearly all ✅ Done. Pure closed-item history; not restated verbatim elsewhere so it fails the "delete" bar even though it is fully closed. |
| `v1.0/voiceover-verification-checklist.md` | 165 | howto | — (archive: `ui-implementation-prompts.md`, `ui-workflow-backlog.md`, `v2-onramp.md`, `v1-scope.md`, `v2-scope.md`) | decision restated live: `docs/decisions.md` 2026-09-11 ("owner: *i dont care about VoiceOver*"); checklist procedure itself not restated | →archive (stays as is) | Parked-not-cancelled checklist; the "deferred" decision it records is now current-restated but the procedure has no live duplicate. |
| `v2/README.md` | 23 | status/history | — (archive: `development-history.md`, `development-process-v2.md`, `distribution.md`, `load-pipeline-plan.md`, `open-items-2026-09-02.md`, `post-v1-ideas.md`, `s22-ux-design.md`, `v1-scope.md`, `v2-release.md`, `v2-scope.md`, `v2-ship-plan.md`, `v2-triage-2026-09-01.md`, `v2.5-plan.md`) | none | →archive (stays as is) | Local index for this very folder — high archive-internal fan-in, zero live citations. Useful in place; not a delete candidate (nothing "restates" an index). |
| `v2/development-history.md` | 20 | status/history | — (archive: `code-review-2026-07-19.md`, `v2/README.md`) | superseded by `CLAUDE.md`'s own "Read, in this order" list and `docs/releasing.md` | **delete** | A pointer index ("the durable records are…") whose job `CLAUDE.md`'s reading order now does live. Smallest, lowest-risk delete in scope. |
| `v2/development-process-v2.md` | 323 | rule/invariant | `docs/development-process.md:5` ("The v2-era process doc is `archive/v2/development-process-v2.md`") | superseded by `docs/development-process.md` | **→ADR** | Required to exist (cited by a live truth doc). But it carries two rules with no live home — see Table 2 rows 1–2 — that were dropped, not superseded, when `development-process.md` was rewritten for v3. |
| `v2/distribution.md` | 46 | howto | — (archive: `README.md`, `development-history.md`, `development-process-v2.md`) | **verbatim merged into `docs/releasing.md`** §"Distribution and notarization", which literally says `*(merged from `distribution.md`, 2026-09-02)*` | **delete** | Textbook case: uncited, superseded, and its exact prose is already live under a different heading. Confirmed by diff-reading both files. |
| `v2/load-pipeline-plan.md` | 1381 | architecture | — (archive: 8 files incl. `open-items-2026-09-02.md`, `post-v1-ideas.md`, `v1-scope.md`, `v2-release.md`, `v2-scope.md`) | superseded by `docs/v3-plan.md` (the load-pipeline work was folded into/overtaken by later planning; no live doc restates the L1–L6 invariants) | →archive (stays as is) | Second-largest file. Detailed py4DSTEM-deviation analysis (crop/bin origin-rereferencing traps) has no live restatement — it's exactly the kind of *why* `CLAUDE.md` says the archive is for. |
| `v2/open-items-2026-09-02.md` | 2116 | status/history | soft: `docs/open-items.md:15` ("the 2026-09-02 pre-cull file beside it" — prose, not a backticked link) | superseded by `docs/open-items.md` (current) and `docs/archive/open-items-2026-09-07.md` | →archive (stays as is) | The pre-cull open-items snapshot; explicitly the thing `open-items.md`'s own history note points a reader at, even without a hard link. |
| `v2/post-v1-ideas.md` | 387 | decision | `CHANGELOG.md:490,508`, `ROADMAP.md:72`, `docs/v3-plan.md:9` | Q-calibration idea superseded by `docs/q-calibration-design.md` (file says so: "ANSWERED by S12… design… is `q-calibration-design.md`"); WS₂ step 1 superseded by `decisions.md` 2026-09-12 (β″ built-in structure) | →archive (stays as is) | Required live (three citations). Still-open ideas (precipitates, EDX, uncertainty propagation) have no other home — this **is** their record. |
| `v2/release-2026-09-04.md` | 118 | status/history | `docs/status.md:29` | none | →archive (stays as is) | Required live. Release-night log with two self-corrections; unique. |
| `v2/s22-ux-design.md` | 758 | decision | — (archive: `README.md`, `open-items-2026-09-02.md`, `v2-release.md`) | outcome superseded by `docs/archive/v2/ui-rework-2026-09-03.md` (what actually shipped) and `docs/decisions.md`'s 2026-09-03/04 entries | →archive (stays as is) | Design-phase document for a redesign since redone twice more (v2.5 rework, then the full SwiftUI rebuild). History only. |
| `v2/ui-rework-2026-09-03.md` | 158 | status/history | `docs/architecture.md:203`, `docs/status.md:35` | none (though the window it describes was itself deleted the next day, 2026-09-04, per `decisions.md`) | →archive (stays as is) | Required live by two docs. Explicitly says at its own top: "History, not guidance." |
| `v2/v1-scope.md` | 117 | decision | `ROADMAP.md:113` | superseded by `docs/v3-plan.md`; VoiceOver deferral restated in `decisions.md` 2026-09-11 | →archive (stays as is) | Required live. Frozen v1 contract, correctly kept as the record of what v1.0.0 promised. |
| `v2/v2-release.md` | 1042 | decision | `ROADMAP.md:121`, `docs/q-calibration-design.md:3,404` | superseded by `docs/archive/v2/v2.5-plan.md` then `docs/v3-plan.md`; refusal-rule clause 2 restated verbatim-ish in `CLAUDE.md` | →archive (stays as is) | Required live (two citations, one of them a live reference doc citing its own session numbering). Largest "decision" file. |
| `v2/v2-scope.md` | 248 | decision | — (archive: `README.md`, `development-history.md`, `development-process-v2.md`, `load-pipeline-plan.md`, `open-items-2026-09-02.md`, `v1-scope.md`, `v2-release.md`, `visual-acceptance-checklist-2026-09-03.md`) | superseded by `docs/archive/v2/v2-release.md` (file says so at line 3) | →archive (stays as is) | Refusal rule + AppState rule + dataset policy — all three restated live (Table 3), but the "why this file is not shaped like v1-scope.md" reasoning and the deferred-items table are unique. |
| `v2/v2-ship-plan.md` | 115 | status/history | — (archive: `README.md`, `open-items-2026-09-02.md`, `s22-ux-design.md`, `v2-release.md`) | superseded by `docs/decisions.md` 2026-09-02 "Tag before ship" entry and `docs/status.md`'s Releases table | →archive (stays as is) | Sequenced path to the v2.0.0 tag; small, fully executed, harmless to keep. |
| `v2/v2-triage-2026-09-01.md` | 164 | decision | — (archive: `2026-09-01-trackb-playthrough.md`, `README.md`, `open-items-2026-09-02.md`, `s22-ux-design.md`, `v2-release.md`) | findings folded into `docs/archive/v2/v2-release.md`; disposition decisions restated in `docs/decisions.md` | →archive (stays as is) | The 39-finding Group A/B/C/D/E/F triage; unique classification reasoning not restated elsewhere. |
| `v2/v2.5-log-2026-09-03.md` | 18 | status/history | `docs/status.md:17` | none | →archive (stays as is) | Required live. Tiny, exactly what it claims to be (a moved-verbatim per-increment log). |
| `v2/v2.5-plan.md` | 404 | architecture | `docs/architecture.md:6,133`, `ROADMAP.md:27,115`, `docs/v3-plan.md:10`, `docs/open-items.md:16`, `docs/decisions.md:44,389,393` | none — this is itself the most-cited archive file in scope | →archive (stays as is) | Required live by **9 separate citations**, more than any other file in this scope. The consolidation architecture contract; `architecture.md` still points into its §4. |
| `v2/visual-acceptance-checklist-2026-09-03.md` | 396 | howto | `CONTRIBUTING.md:91`, `docs/open-items.md:1028`, `.claude/skills/diagnose/SKILL.md:17` | Track B itself retired per `docs/decisions.md` 2026-09-03 ("Track B is retired… the owner drives and reports") | →archive (stays as is) | Required live (three citations, including a skill file). Retired procedure kept as trap-note history for anyone re-deriving a checklist. |

## Table 2 — rules/decisions found only in this archive scope

| rule/decision | archive path#section | why it might still be load-bearing |
|---|---|---|
| Mutation-tested suites can be *collectively* blind at symmetric test constants (S8, 2026-08-25): pinning exactly 90° let a wrong angle sign AND a dropped transpose both survive a 15-mutation-verified suite. Rule: pin sign-discriminating constants (37.2°, not 90/45/0) with an in-test guard proving the variant differs. | `v2/development-process-v2.md` §2 | Verified absent from `docs/development-process.md`, `docs/decisions.md`, `CLAUDE.md` (grepped for "symmetric", "37.2", "blind spot"). The current Gate D discipline (independent refuter, mutation testing) is exactly the mechanism this rule would harden — it is a concrete instance of "review the diagnosis, not the code" that got dropped when the process doc was rewritten for v3, not superseded by anything more specific. |
| Model/subagent tier table: Haiku for locate/search, Opus for Plan/design and adversarial review, Sonnet (default) for implementation, Opus for `/code-review`, "never let the model that wrote a science change be the only one that approves it." | `v2/development-process-v2.md` §2 | Verified absent from `docs/development-process.md`, `docs/decisions.md`, `CLAUDE.md` (grepped "Haiku", "model tier", "scouts" — zero hits in any live doc). The *principle* survives in CLAUDE.md's Gate D paragraph and in the `.claude/agents/*` definitions, but the explicit tier-assignment table that operationalizes it (which job gets which model) has no current repo-doc home — it now lives only in the user's personal `~/.claude` memory, outside this repo. |
| The refusal rule's fabrication clause, stated as a named rule: **"Nothing ships that can fabricate a scientific result, and no gate is widened to make something pass."** Operational form: never let the model that wrote a science-affecting change approve it alone; review the diagnosis, not just the code. | `v2/v2-scope.md` §4 (also `v2/v2-release.md` §4, same text) | Partially covered by `CLAUDE.md`'s Gate D paragraph and `docs/development-process.md`'s "Never widen a gate that fails silently" (Working methods #3), but neither restates the "nothing ships that can fabricate a scientific result" framing as a standalone named rule with worked examples (the #14 CIF-precision trap). Worth an explicit ADR line rather than leaving it implicit across two paraphrases. |
| `AppState` extraction ranking methodology: rank candidate seams by **state ownership**, not by MARK-section line count (which was tried and refuted same-day — 172 of ~188 stored properties live before the first MARK). Order: (1) state a stage is *adding* goes into its own type from the start — free; (2) then a cohesive group of existing facade properties, identified by grepping stored properties, not MARK; (3) calibration last. | `v2/development-process-v2.md` §7 | `docs/architecture.md`'s "Ownership today and where it is going" section lists the seams already extracted (`DatasetResidency`, `SessionGates`, `FitOverlayPresentation`, …) and the target shape, but does not restate *how to pick the next one* — this methodology is exactly what a session doing the plan's §4 extraction order (which `CLAUDE.md`'s hard rules still reference) would need, and it is currently nowhere live. |

## Table 3 — live facts repeated in this archive scope

| fact | live path#section | archive path#section |
|---|---|---|
| Any stage touching `AppState` extracts one seam first, at a green test boundary, itself `@Observable`; a forwarding-only split does not count. | `docs/decisions.md` (2026-08-17 entry); `CLAUDE.md` "Hard rules" ("New stored state in `AppState` names its owner first") | `v2/development-process-v2.md` §7; `v2/v2-scope.md` §6 decision 4 |
| Never let the model that wrote a science-affecting change be the only one to approve it; review the diagnosis, not just the code. | `CLAUDE.md` "Hard rules" (Gate D paragraph) | `v2/v2-scope.md` §4 clause 1; `v2/development-process-v2.md` §2 |
| No claim in docs/README/CHANGELOG that a reader cannot reproduce on a current machine — the repo is public. | `CLAUDE.md` "Hard rules" ("No claim a reader cannot reproduce. The repo is public.") | `v2/v2-scope.md` §4 clause 2 |
| `tools/run-tests.sh` refuses below a free-space floor rather than producing spurious failures on a full disk. | `docs/development-process.md` "Isolate work…" section; `docs/decisions.md` 2026-09-12 entry (floor since split 4/8 GB) | `v2/v2-scope.md` §6 decision 6 |
| Distribution/notarization procedure: embedded `libhdf5`/`libsz`/`libaec`, `tools/package-test/run.sh` credential-free audit, Developer ID + `notarytool` for the credentialed release. | `docs/releasing.md` §"Distribution and notarization" (verbatim, states "merged from `distribution.md`") | `v2/distribution.md` (whole file) |
| Screen-reader (VoiceOver) usability is deliberately not a release gate. | `docs/decisions.md` 2026-09-11 entry ("owner: *i dont care about VoiceOver, it is not part of the*…") | `v2/v1-scope.md` "Post-v1" section; `v1.0/voiceover-verification-checklist.md` header |
| Q-calibration's origin-error fragility has two distinct real causes (broad measurement failure vs. outlier contamination) that a single RMS threshold cannot separate. | `docs/q-calibration-design.md` | `v2/post-v1-ideas.md` "Q calibration is fragile…" section (which itself records "ANSWERED by S12" and points at the live doc) |
| Gate ceremony: Gate D unchanged; Gate B only for changes that alter a number in `Core`/`DSTEMCore`; Track B (human checklist) retired in favour of the owner driving and reporting through `/diagnose`. | `docs/decisions.md` 2026-09-02 "Gate ceremony" entry and 2026-09-03 "Track B is retired" entry | `v2/v2.5-plan.md` §4 (D3) and §8 |

## Table 4 — broken citations inside this scope

**Total: 330 missing repo-rooted paths** out of 500 path-like backticked
tokens extracted (500 total citations checked; 170 resolve against
`git ls-files`). Not a defect list — every one of the 23 files in this scope
is explicitly *history*, and `docs/archive/v2/README.md` says outright that
"relative links inside these files were written for their original location
in `docs/` and are not rewritten." `CLAUDE.md`'s inventory-gate rule ("a
repo-rooted path a truth doc cites and does not have" fails the gate) applies
to *truth docs*, i.e. the live set — archive files are one of its three
named exemptions ("plans and designs name what does not exist yet"). None of
these need fixing; they are presented so the synthesizer can see the shape of
the staleness.

Four categories account for nearly all of it:

| category | count | example |
|---|---|---|
| Missing `mac4DSTEM/` prefix on a source path that still exists (or was deleted in a later refactor) | 123 | `App/AppState.swift` → now `mac4DSTEM/App/AppState.swift` |
| Old `docs/` path for a file later renamed into this very archive folder | 102 | `docs/v1-scope.md` → now `docs/archive/v2/v1-scope.md` |
| Retired tool/test harness (the whole `mac4DSTEMUITests` target and `tools/ui-qc-playthrough` were deleted 2026-09-02, per `v2/README.md`) | 78 | `tools/ui-qc-playthrough/run.sh`, `mac4DSTEMUITests/Support/AXDriver.swift` |
| Gitignored/local `References/` path (never tracked, so never resolvable from `git ls-files`) | 12 | `References/py4DSTEM-dev`, `References/parity_records/latest` |
| Relative archive-internal link, unrewritten by policy | 7 | `../ROADMAP.md` (from inside `docs/archive/v2/`) |
| Other / not a real path (numeric fractions, code identifiers matched by the path regex) | ~8 | `1/nm`, `x/b`, `a/4.1` — regex noise, not citations |

Representative sample (40 of 330, capped per instructions):

| cited path | citing file:line |
|---|---|
| `docs/qc-playthrough-prompts.md` | `docs/archive/v1.0/qc-playthrough-prompts.md:7` |
| `docs/ui-workflow-backlog.md` | `docs/archive/v1.0/qc-playthrough-prompts.md:17` |
| `docs/ui-implementation-prompts.md` | `docs/archive/v1.0/qc-playthrough-prompts.md:55` |
| `docs/v2-onramp.md` | `docs/archive/v1.0/ui-implementation-prompts.md:6` |
| `docs/v1-scope.md` | `docs/archive/v1.0/ui-implementation-prompts.md:113` |
| `docs/voiceover-verification-checklist.md` | `docs/archive/v1.0/ui-implementation-prompts.md:117` |
| `docs/ui-design-pass-2026-08-05.md` | `docs/archive/v1.0/ui-implementation-prompts.md:154` |
| `docs/post-v1-ideas.md` | `docs/archive/v1.0/ui-workflow-backlog.md:19` |
| `tools/ui-qc-playthrough/run.sh` | `docs/archive/v1.0/qc-playthrough-prompts.md:62` |
| `mac4DSTEMTests/SidebarLayoutProbe.swift` | `docs/archive/v1.0/ui-design-pass-2026-08-05.md:23` |
| `mac4DSTEMTests/SidebarLayoutTests.swift` | `docs/archive/v1.0/ui-design-pass-2026-08-05.md:376` |
| `mac4DSTEMUITests/Support/ParityRecords.swift` | `docs/archive/v1.0/ui-implementation-prompts.md:51` |
| `mac4DSTEMUITests/Support/AXDriver.swift` | `docs/archive/v1.0/ui-implementation-prompts.md:110` |
| `tools/scientific-bundle-test` | `docs/archive/v1.0/ui-workflow-backlog.md:1152` |
| `mac4DSTEMTests/SplitViewHeightTests.swift` | `docs/archive/v1.0/ui-workflow-backlog.md:1350` |
| `mac4DSTEMTests/SidebarDensityMeasurementTests` | `docs/archive/v1.0/ui-workflow-backlog.md:2392` |
| `build/ui-qc-DerivedData` | `docs/archive/v1.0/qc-playthrough-prompts.md:95` |
| `.claude/skills/track-b/DRIVING.md` | `docs/archive/v2/open-items-2026-09-02.md:464` |
| `real-data-acceptance/run.sh` | `docs/archive/v2/open-items-2026-09-02.md:1604` |
| `q-calibration-gate-test/run.sh` | `docs/archive/v2/open-items-2026-09-02.md:1606` |
| `Support/ResultExport.swift` | `docs/archive/v1.0/ui-design-pass-2026-08-05.md:338` |
| `App/ProductWorkflow.swift` | `docs/archive/v1.0/ui-design-pass-2026-08-05.md:383` |
| `App/AppState.swift` | `docs/archive/v1.0/ui-design-pass-2026-08-05.md:384` |
| `Core/Analysis/StrainMapping.swift` | `docs/archive/v1.0/ui-implementation-prompts.md:54` |
| `Core/Crystal/CIFImport.swift` | `docs/archive/v1.0/ui-implementation-prompts.md:197` |
| `UI/ACOMControlsView.swift` | `docs/archive/v1.0/ui-implementation-prompts.md:220` |
| `Core/Data` | `docs/archive/v1.0/ui-implementation-prompts.md:291` |
| `Core/Crystal/CrystalModel.swift` | `docs/archive/v1.0/ui-implementation-prompts.md:400` |
| `References/py4DSTEM-dev` | `docs/archive/v1.0/ui-implementation-prompts.md:49` |
| `References/MigrationSource/Core/Compute/MLXEngine.swift` | `docs/archive/v2/development-process-v2.md:161` |
| `References/py4DSTEM-dev/py4DSTEM/braggvectors/diskdetection_aiml.py` | `docs/archive/v2/development-process-v2.md:163` |
| `References/training_dataset/WS2.cif` | `docs/archive/v2/open-items-2026-09-02.md:62` |
| `References/parity_records/latest` | `docs/archive/v2/post-v1-ideas.md:294` |
| `References/tb1-drive-kit.md` | `docs/archive/v2/visual-acceptance-checklist-2026-09-03.md:112` |
| `../closed-items-2026-08.md` | `docs/archive/v2/README.md:23` |
| `../ROADMAP.md` | `docs/archive/v2/development-history.md:10` |
| `archive/training-dataset-evaluation-2026-07-15.md` | `docs/archive/v2/development-history.md:11` |
| `archive/2026-08-31-comparator-gate-b.md` | `docs/archive/v2/open-items-2026-09-02.md:1554` |
| `archive/2026-09-01-trackb-playthrough.md` | `docs/archive/v2/v2-release.md:828` |
| `a/4.1` (regex noise, not a real citation) | `docs/archive/v1.0/ui-workflow-backlog.md:1734` |

## Table 5 — totals

| | files | lines |
|---|---|---|
| **Scope total** | 23 | 12 169 |
| → verdict **archive (stays as is)** | 20 | 11 780 |
| → verdict **delete** | 2 | 66 |
| → verdict **→ADR** | 1 | 323 |
| → verdict **keep→CLAUDE.md** | 0 | 0 |
| → verdict **keep→ARCHITECTURE.md** | 0 | 0 |

Rows: 23 total (one per file, as specified — archive files get file-level
rows, not section-level).
