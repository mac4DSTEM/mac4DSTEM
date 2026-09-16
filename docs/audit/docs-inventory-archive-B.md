# Docs inventory — Archive B (v2-session-records, v3, 2026-08-31-review, 2026-09-09-review, 2026-09-11-drive)

Scope: `docs/archive/v2-session-records/*.md`, `docs/archive/v3/**/*.md`,
`docs/archive/2026-08-31-review/**/*.md`, `docs/archive/2026-09-09-review/*.md`,
`docs/archive/2026-09-11-drive/*.md`. 49 files, 7972 lines. Read in full.
Live context read first: `CLAUDE.md`, `docs/status.md`, `docs/architecture.md`,
`docs/development-process.md`, `docs/v3-plan.md`, `docs/open-items.md`,
`docs/decisions.md` (headings + targeted sections), plus
`docs/ai-ml/{README,precipitates}.md`, `docs/v3-phase-mapping-method-choice.md`,
`docs/v3-precipitate-classification.md`, `docs/v3-vector-matching-plan.md`,
`docs/q-calibration-design.md`, `docs/releasing.md`, `docs/dm4-format.md`,
`docs/py4dstem-pipelines.md`, and the four `.claude/skills/*/SKILL.md` files,
all grepped for citations of every in-scope path (full path, path relative to
`docs/`, and basename, each verified against the actual matched line to
exclude basename coincidences). Cross-archive citations (other `docs/archive/`
files, outside this scope, citing an in-scope file, and in-scope files citing
each other) were checked the same way.

## Table 1 — one row per file

Legend: verdict `→archive` = stays as is; `→ADR` = names a decision not in
`docs/decisions.md`; `delete` = uncited, superseded, content restated
elsewhere. "arch:" in cited-by means another **archive** file (in or out of
this scope) cites it, not a live doc.

| path | lines | class | cited-by | duplicate-of / superseded-by | verdict | note |
|---|---:|---|---|---|---|---|
| `docs/archive/2026-08-31-review/README.md` | 131 | gate-evidence | `docs/development-process.md` | - | →archive | Index of the 75-finding v2 recovery review (39 confirmed/34 narrowed/1 refuted/1 resolved). The 2026-09-09 register calls 16 of its own findings repeats and 8 possible repeats of this round. |
| `docs/archive/2026-08-31-review/acom-gate-b.md` | 37 | gate-evidence | arch: README.md (in-scope) | - | →archive | Independent Gate B, ACOM convention fixture. Approval is explicitly scoped to CPU projection/returned-matrix regression, not blanket ACOM accuracy. |
| `docs/archive/2026-08-31-review/process-review.md` | 162 | gate-evidence | arch: README.md (in-scope) | - | →archive | Reviews `tools/review-record-check/run.py` and the v3 process proposal. Contains the broken `docs/v3-development-process.md` citation (Table 4) — that doc's content lives in `docs/development-process.md` + `docs/v3-plan.md` today. |
| `docs/archive/2026-08-31-review/verification/review-data-crystal.md` | 41 | gate-evidence | none anywhere (not even from this review's own README) | README.md's findings table + `findings.json` (disposition level) | delete | Zero inbound citations from any live doc, any archive file, or even its own review's index — README's "Read this first" links `acom-gate-b.md` and `process-review.md` by name but never these three `verification/*.md` files, pointing readers at `findings.json` instead. The review round it narrates is itself superseded by the more rigorous 2026-09-09 register (which cross-references the same core-data/core-crystal findings as "repeat of core-data-01" etc.). |
| `docs/archive/2026-08-31-review/verification/review-physics-export.md` | 20 | gate-evidence | none anywhere | README.md's findings table + `findings.json` | delete | Same orphaning as above. |
| `docs/archive/2026-08-31-review/verification/review-tests-workflow.md` | 32 | gate-evidence | none anywhere | README.md's findings table + `findings.json` | delete | Same orphaning as above. |
| `docs/archive/2026-09-09-review/d002-d003-gate-d.md` | 297 | gate-evidence | `docs/status.md`; arch: `closed-items-2026-09.md`, `v3.0.0-closeout-2026-09-11.md` (in-scope) | - | →archive | The Gate D record CLAUDE.md's own status table cites by name for D002 (ptychography rotation) and D003 (H5Aread overrun). Independent refuter overturned the crash claim and corrected the mutation count (5→4 distinct transformations). |
| `docs/archive/2026-09-09-review/register.md` | 197 | gate-evidence | `docs/open-items.md`, `docs/status.md` | - | →archive | 259 records deduplicated to 156 clusters; 113 new-and-unverified per status.md's own count. |
| `docs/archive/2026-09-11-drive/origin-cleared-gate-d.md` | 159 | gate-evidence | none found | `docs/open-items.md`'s "A radius-only aperture drag destroys the fitted origin" entry restates the conclusion, not the H1/H2 reasoning or the refuted-hypotheses sweep | →archive | Full Gate D diagnosis of the origin-un-ticks-after-Imaging defect (the `ApertureOverlay.emit` pixel-rounding evidence, the exhaustive writer sweep). Uncited despite being the direct ancestor of a live open item — worth a link, but the reasoning is not duplicated so it should stay regardless. |
| `docs/archive/2026-09-11-drive/quantitative-badge-gate-b.md` | 96 | gate-evidence | `docs/open-items.md`; arch: `v3.0.0-closeout-2026-09-11.md` (in-scope) | - | →archive | Rejected/reverted fix, kept per CLAUDE.md's "a fix that looks like one and is not is worse than the open defect." |
| `docs/archive/v2-session-records/cif-pair.md` | 129 | gate-evidence | arch only: `v2/open-items-2026-09-02.md` ×2, `v2/v2-release.md`, `v2/v2-ship-plan.md` | - | →archive | CIF symmetry-expansion + truncated-loop Gate D/B; Gate B found a two-column symmetry loop that floor-divided a centering op away and passed `verifyFamily`. |
| `docs/archive/v2-session-records/dpc-angle-units.md` | 155 | gate-evidence | arch only: `v2/v2-release.md`, `v2/v2-triage-2026-09-01.md` | - | →archive | Textbook Gate D structure (diagnosis → refuting observation → predicted outcome → outcome → Gate B); confirmed the 2π DPC-angle error. |
| `docs/archive/v2-session-records/probe-radius.md` | 133 | gate-evidence | arch only: `v2/open-items-2026-09-02.md` ×3, `v2/v2-release.md`, `v2/v2-ship-plan.md` | - | →archive | `probeSize(maxDP)` vs `meanDP` Gate D/B; the within-file nested-sub-scan evidence (16.07→16.50→19.07 px) is the causal clincher. |
| `docs/archive/v2-session-records/review-recovery.md` | 77 | status/history | `docs/development-process.md` | - | →archive | The 2026-08-31 review-recovery session record (in progress at time of writing); registers the ACOM Gate B pre-registration. |
| `docs/archive/v2-session-records/s1.md` | 36 | status/history | arch only: `v2/v2-release.md` | - | →archive | Sidecar-locator seam session. |
| `docs/archive/v2-session-records/s2.md` | 14 | status/history | arch only: `v2/v2-release.md` | - | →archive | Shortest file in scope. |
| `docs/archive/v2-session-records/s3.md` | 32 | status/history | arch only: `v2/v2-release.md` | - | →archive | `.automatic` residency dropped (Table 3 match). |
| `docs/archive/v2-session-records/s4.md` | 50 | status/history | arch only: `v2/v2-release.md` | - | →archive | Configurator session; the tail-pipe exit-code trap (Table 3 match, the "S4" CLAUDE.md cites). |
| `docs/archive/v2-session-records/s5.md` | 55 | status/history | arch only: `v2/v2-release.md` | - | →archive | Replay-record seam; AppState-seam-rule example (Table 3). |
| `docs/archive/v2-session-records/s6.md` | 78 | status/history | arch only: `v2/v2-release.md` | - | →archive | Unattended-execution/promote-and-replay session. |
| `docs/archive/v2-session-records/s7.md` | 73 | status/history | arch only: `v2/v2-release.md` | - | →archive | Error-honesty / SessionGates seam. |
| `docs/archive/v2-session-records/s8.md` | 74 | status/history | arch only: `v2/v2-release.md` | - | →archive | Strain-frame session; py4DSTEM's `get_reference_g1g2` non-equivariance DEVIATION. |
| `docs/archive/v2-session-records/s10.md` | 131 | status/history | arch only: `v2/v2-release.md` | - | →archive | Reduced-file export / frame mapping. |
| `docs/archive/v2-session-records/s13.md` | 691 | gate-evidence | `docs/q-calibration-design.md` ×3 | - | →archive | Largest file in scope. Q-calibration pre-registration/Gate B/Gate D; §0 was lost to a later append and restored verbatim with the loss stated rather than hidden. |
| `docs/archive/v2-session-records/s17.md` | 161 | gate-evidence | arch only: `v2/open-items-2026-09-02.md`, `v2/v2-release.md` | - | →archive | Sidebar-intermittent Gate D; the real cause was an uncontrolled `@AppStorage` disclosure state, not layout timing. |
| `docs/archive/v2-session-records/s18.md` | 405 | status/history | arch only: `v2/v2-release.md` | - | →archive | Polish sweep; proposes a `.claude/skills/track-b/SKILL.md` edit (that skill now lives under a different plugin path — see Table 4). |
| `docs/archive/v2-session-records/s21.md` | 153 | status/history | arch only: `v2/v2-release.md` | - | →archive | CI-on-public-repo session; postscript records the first two CI runs. |
| `docs/archive/v2-session-records/w4a.md` | 114 | gate-evidence | arch only: `v2/v2-release.md` | - | →archive | WS₂ crystal model, two refuters; corrected the "wrong 2H polytype" hole the fixture originally missed. |
| `docs/archive/v2-session-records/w4b.md` | 376 | gate-evidence | arch only: `v2/open-items-2026-09-02.md` ×2, `v2/v2-release.md` | - | →archive | ACOM on WS₂; three Gate-B corrections to its own conclusions (0.60 flip factor, reliability anti-correlation refuted, 2.2129× not 2.2564×). Closing section proposes the "break a refuter's own remedy" rule, now in `adversarial-review/SKILL.md` (Table 3). |
| `docs/archive/v3/acom-zone-axis-2026-09-15.md` | 148 | gate-evidence | `docs/open-items.md` | - | →archive | Nine (then eleven) refuted hypotheses for ACOM's up-to-12.8° zone-axis excess; ends with "more templates make ACOM worse" and an unresolved next step (look at the polar images). |
| `docs/archive/v3/ai-analysis-audit-2026-09-14.md` | 95 | gate-evidence | none found | - | →archive | Records fixes shipped in commit `94c4d29` (Crystal.reflections tiling, phase-vector-matching frame, PCA clamp). Not linked from `docs/status.md`'s current table despite real shipped changes. |
| `docs/archive/v3/ai-gateD-2026-09-06/gateD-A2.md` | 129 | gate-evidence | arch: `ai-port-2026-09-11.md` (in-scope) | - | →archive | Learned/diffraction-groups full-scan-on-main-thread Gate D; the cross-file `nonisolated` extension gap (Table 2). |
| `docs/archive/v3/ai-gateD-2026-09-06/gateD-C1.md` | 212 | gate-evidence | arch: `ai-port-2026-09-11.md` (in-scope) | - | →archive | `symmetricEigenTop` one-subspace-iteration defect via the `max(0,.nan)==0` IEEE trap (Table 2); fixed with LAPACK `dsyevd_`. |
| `docs/archive/v3/ai-gateD-2026-09-06/gateD-C3.md` | 168 | gate-evidence | arch: `ai-port-2026-09-11.md` (in-scope) | - | →archive | Precipitate `widthPx`/`area` readings — recorded as owner choices, not fixed. |
| `docs/archive/v3/ai-gateD-2026-09-06/gateD-P6.md` | 86 | gate-evidence | arch: `ai-port-2026-09-11.md` (in-scope) | - | →archive | SwiftUI `ForEach` id-collision between reflection and object rows. |
| `docs/archive/v3/ai-port-2026-09-11.md` | 300 | status/history | none anywhere (live or archive) | - | →archive | The hub record for the 7-commit AI-pipeline port (the `AnalysisMode` move, the LAPACK flag, the sixth "AI Analysis" workspace). Cites all four `ai-gateD-2026-09-06/` files and both precipitate files, but nothing points a reader to it — `docs/status.md`'s table has no row for it even though the workspace it created is live. Worth a citation from `docs/status.md`; content is not restated elsewhere so it stays regardless. |
| `docs/archive/v3/c7-gate-b-2026-09-08.md` | 203 | gate-evidence | `docs/status.md`; arch: `consolidation-plan.md` | - | →archive | 17 mutations, 5 survived; the M7 "axis-swap invisible at symmetric test constants" finding names a recurring repo trap. |
| `docs/archive/v3/c8-triage-2026-09-08.md` | 86 | decision | `docs/status.md`, `docs/decisions.md`; arch: `consolidation-plan.md`, `2026-09-09-review/register.md` (in-scope, D010), `ai-port-2026-09-11.md` (in-scope), `2026-09-11-ai-port-analysis.md` (outside scope) | - | →archive | Acceptance-checklist triage of the `ml/disk-detector` branch; the "leave" verdict it fed into `decisions.md` was reversed 2026-09-11 (the port happened). |
| `docs/archive/v3/drive-2026-09-09.md` | 189 | gate-evidence | `docs/open-items.md` ×2, `docs/status.md` | - | →archive | 87-screenshot delegated drive; finding #16 (WS2's 1-peak/pattern "success") is the headline the parent session corrected against its own screenshot. |
| `docs/archive/v3/drive-2026-09-15.md` | 52 | gate-evidence | `docs/open-items.md` ×2, `docs/status.md` | - | →archive | Confirms R–Q rotation refusal wording, the ellipse Fit Anyway flow; one wording defect found and fixed same morning. |
| `docs/archive/v3/learned-detector-2026-09-06.md` | 600 | status/history | `docs/v3-plan.md` ×2; arch: `decisions.md`-cited, `consolidation-plan.md` | `docs/v3-plan.md` §3a (current registration) + `docs/decisions.md`'s terser 2026-09-06/07/08 entries | →archive | Largest file in scope. Explicitly "History, not guidance" per its own header — the Core AI → Core ML runtime reversal is stated in the header as a correction of the body's own 2026-09-06 "Core AI exclusively" decision. |
| `docs/archive/v3/phase-discrimination-2026-09-11.md` | 167 | gate-evidence | `docs/v3-phase-mapping-method-choice.md`, `docs/v3-precipitate-classification.md` | - | →archive | Killed per-position template matching twice over (mixing flip at f=0.60; gold outscores aluminium on an Al-only pattern); corrects its own first (wrong) explanation of the Al/Au confusion. |
| `docs/archive/v3/phase-mapping-2026-09-12.md` | 315 | gate-evidence | `docs/open-items.md`, `docs/v3-vector-matching-plan.md` | - | →archive | Vector-matching steps 1/2/4/5; two pre-registered criteria failed for real reasons (P3 chance coverage, P5 fcc 4-fold symmetry); Gate B found 11/13 mutations survived. |
| `docs/archive/v3/precipitate-baseline-2026-09-11.md` | 119 | gate-evidence | `docs/v3-precipitate-classification.md`; arch: `ai-port-2026-09-11.md` (in-scope) ×2 | - | →archive | Pre-registered baseline scored a TIE (pass by the owner's criterion) but shows the ridge filter doesn't reject round particles — its whole purpose. |
| `docs/archive/v3/precipitate-handcount-2026-09-11.md` | 118 | gate-evidence | `docs/v3-precipitate-classification.md` ×2 | - | →archive | Hand-count candidates; same-day correction that shape filters were discarding 56% of real signal, halving the density estimate. |
| `docs/archive/v3/sped-phase-mapping-reference-2026-09-11.md` | 121 | howto | `docs/v3-phase-mapping-method-choice.md`; arch: `phase-discrimination-2026-09-11.md` (in-scope) | - | →archive | Reading notes on `elisathr/SPED-phase-mapping` (Thronsen et al.); corrects its own first draft's "template matching is worst of four" claim (paper says the differences are not significant). |
| `docs/archive/v3/status-bar-2026-09-12.md` | 181 | gate-evidence | `docs/status.md` | - | →archive | Three independent designs + adversarial critique for the status-bar Cancel button; measured, not guessed (9pt label vs 10pt text). |
| `docs/archive/v3/step3-2026-09-16.md` | 372 | gate-evidence | `docs/open-items.md`, `docs/status.md` | - | →ADR | Names a decision not in `docs/decisions.md`: **keep the matrix explained-fraction fall-back off by default and ship the reported quantity instead of a verdict-changing threshold**, because a 0.90 bar that separates Al/T1 on Thronsen flags 46% of a fully-correct demo-cube map. See Table 2 item 4. |
| `docs/archive/v3/v3.0.0-closeout-2026-09-11.md` | 202 | status/history | `docs/status.md` | - | →archive | v3.0.0 cut record; the `ARCHS=arm64` archive-vs-build gap, the Intel v2.5.1 discovery, and the credentialed-run traps. |

## Table 2 — rules/decisions found ONLY in this archive scope

| rule/decision | archive path#section | why it might still be load-bearing |
|---|---|---|
| `Swift.max(0, .nan) == 0.0` (IEEE `maxNum` semantics) silently breaks any convergence/threshold check that assumes NaN propagates through `max` | `docs/archive/v3/ai-gateD-2026-09-06/gateD-C1.md` §1 (explicitly "the trap this repo already recorded on 2026-09-02" re: FFT2D) | Verified absent from `CLAUDE.md`'s Hard Rules and `docs/architecture.md`. Has bitten this codebase at least twice (FFT2D 2026-09-01, PCA eigensolver 2026-09-06) with no standing warning for the next `Core/` numerical routine. |
| `nonisolated` on a class declaration does not extend to a member declared in a *different file's* `extension` of that class — the member stays `@MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | `docs/archive/v3/ai-gateD-2026-09-06/gateD-A2.md` §1, §5 | `docs/architecture.md`'s "Developer notes" states the general `nonisolated`/`Task.detached` pattern but not this cross-file-extension exception, which caused a real full-scan main-thread freeze. |
| Never edit `tools/run-tests.sh` (or any source it compiles) while a gate is running in another process — the running process can read the half-written file and die with a parse error that looks like a tree failure | `docs/archive/v3/phase-mapping-2026-09-12.md` §"A trap paid here" | `CLAUDE.md`'s pipe-exit-code section lists three prior traps (S4, S8, twice on 2026-09-04) but not this one; a concurrent-gate session would rediscover it. |
| The matrix explained-fraction fall-back stays off (0) by default; ship the reported quantity instead of a verdict-changing threshold | `docs/archive/v3/step3-2026-09-16.md` §"The matrix explained fraction is reported…" | Decided 2026-09-16 by the owner in the same session `docs/decisions.md`'s two 2026-09-16 entries cover (the stopping rule; the three overruled rules) — but neither entry names this specific fall-back decision. Verified absent by reading both 2026-09-16 entries in full. |

## Table 3 — live facts repeated in this archive scope

| fact (≤15 words) | live path#section | archive path#section |
|---|---|---|
| Never read a gate's exit code through a pipe; redirect to a log, check its own exit line | `CLAUDE.md` (pipe-exit-code bullet) | `docs/archive/v2-session-records/s4.md` (the tail-pipe run); `docs/archive/v3/v3.0.0-closeout-2026-09-11.md` ("read the gate's own line, never a wrapper's") |
| `.automatic` residency was dropped, not tuned; `measuredWorkingSetFraction` stays nil | `CLAUDE.md` (Hard rules) | `docs/archive/v2-session-records/s3.md` (`.automatic` dropped from `Residency`, `measuredWorkingSetFraction` nil, kept as the return path) |
| A threshold is not a result until it is measured on every dataset it will touch | `docs/development-process.md` §"A threshold is not a result until it is measured on every dataset it will touch" | `docs/archive/v3/step3-2026-09-16.md` (the f=0.8 fall-back entry and the 0.90 matrix-evidence bar entry, the same lesson learned twice in one session) |
| Break every new test before trusting it, by a named mutation | `CLAUDE.md` (Hard rules) | `docs/archive/v2-session-records/w4a.md` ("Break-every-new-test: 7 author mutations, 7/7 caught"); `docs/archive/v2-session-records/cif-pair.md` |
| On-screen verification names the build, what was clicked, what was seen — else stated unverified | `CLAUDE.md` (Hard rules) | `docs/archive/v3/status-bar-2026-09-12.md`, `docs/archive/v3/ai-port-2026-09-11.md` ("UNVERIFIED ON SCREEN") |
| Any stage touching `AppState` extracts one seam first, `@Observable`, at a green boundary | `docs/decisions.md` 2026-08-17 "The `AppState` seam rule" | `docs/archive/v2-session-records/s5.md` (Seam: `FitOverlayPresentation.swift`); s1, s3, s6, s7, s8 each name a seam |
| Gate D: diagnosis, refuting observation, predicted outcome, then the experiment, before the fix; independent refuter after | `CLAUDE.md` (Hard rules) | `docs/archive/v2-session-records/dpc-angle-units.md` (literally structured as "Gate D preregistration — written before the experiment"); every `ai-gateD-2026-09-06/*.md` file |
| Port deviations from py4DSTEM get an inline `DEVIATION` note | `CLAUDE.md` (Hard rules) | `docs/archive/v2-session-records/probe-radius.md` ("each with a DEVIATION note carrying the measurement"); `docs/archive/2026-09-09-review/d002-d003-gate-d.md` §"DEVIATION kept" |
| Docs are part of done; a session nets negative markdown lines or says why | `CLAUDE.md` (Hard rules) | `docs/archive/v2-session-records/s13.md` §8 "Doc tax"; `docs/archive/v2-session-records/w4b.md` §3 "Kickoff tax" |
| A refuter's proposed remedy must itself be broken before it is trusted | `.claude/skills/adversarial-review/SKILL.md` rule 5b | `docs/archive/2026-09-09-review/d002-d003-gate-d.md` (the origin-invariant remedy rejected as vacuous); `docs/archive/v3/phase-mapping-2026-09-12.md` ("One remedy was broken before it was trusted, and rejected"); `docs/archive/v2-session-records/w4b.md` (proposes exactly this rule in its closing Skills section) |

## Table 4 — broken citations inside this scope

Repo-rooted, backticked/linked paths cited by in-scope files that do not
exist as tracked files (checked against the literal path, a `mac4DSTEM/`- or
`docs/`-prefixed resolution, and a path relative to the citing file — the
same resolutions a reader would try). **Total: 39.** Absolute `/tmp/…` paths
and un-rooted session-log fragments (e.g. `gateB/foo.py`, `fix-c/foo.log`) are
excluded — per `CLAUDE.md`'s own rule these are log names, not claimed paths.

| cited path | citing file:line |
|---|---|
| `docs/v3-development-process.md` | `docs/archive/2026-08-31-review/process-review.md:4` |
| `docs/consolidation-plan.md` (moved to `docs/archive/consolidation-plan.md`) | `docs/archive/2026-09-09-review/register.md:96` |
| `docs/consolidation-plan.md` | `docs/archive/v3/c7-gate-b-2026-09-08.md:3` |
| `docs/consolidation-plan.md` | `docs/archive/v3/c8-triage-2026-09-08.md:3` |
| `docs/consolidation-plan.md` | `docs/archive/v3/c8-triage-2026-09-08.md:84` |
| `docs/consolidation-plan.md` | `docs/archive/v3/learned-detector-2026-09-06.md:5` |
| `References/training_dataset/downsample_Si_SiGe_exp.mac4dstem.h5.h5` (gitignored data, never tracked by design) | `docs/archive/2026-09-11-drive/origin-cleared-gate-d.md:96` |
| `docs/v2-release.md` (moved to `docs/archive/v2/v2-release.md`) | `docs/archive/v2-session-records/s1.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s13.md:3` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s18.md:7` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s2.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s21.md:4` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s3.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s4.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s5.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s6.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s7.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/s8.md:1` |
| `docs/v2-release.md` | `docs/archive/v2-session-records/w4b.md:357` |
| `docs/visual-acceptance-checklist.md` (retired with Track B, 2026-08-17) | `docs/archive/v2-session-records/s17.md:108` |
| `docs/visual-acceptance-checklist.md` | `docs/archive/v2-session-records/w4b.md:342` |
| `mac4DSTEM/App/SessionSidecarLocator.swift` (now `mac4DSTEM/Session/SessionSidecarLocator.swift`) | `docs/archive/v2-session-records/s1.md:6` |
| `mac4DSTEM/UI/InspectorPanels.swift` | `docs/archive/v2-session-records/s1.md:16` |
| `mac4DSTEM/UI/InspectorPanels.swift` | `docs/archive/v2-session-records/s1.md:36` |
| `mac4DSTEM/App/QCalibrationRun.swift` (now `mac4DSTEM/Session/QCalibrationRun.swift`) | `docs/archive/v2-session-records/s13.md:410` |
| `mac4DSTEM/UI/ScaleBarView.swift` | `docs/archive/v2-session-records/s18.md:16` |
| `.claude/skills/track-b/SKILL.md` (skill now lives under a different plugin path) | `docs/archive/v2-session-records/s18.md:370` |
| `mac4DSTEM/App/RecentDatasets.swift` (now `mac4DSTEM/Session/RecentDatasets.swift`) | `docs/archive/v2-session-records/s3.md:10` |
| `mac4DSTEM/App/ReplayRun.swift` (now `mac4DSTEM/Session/ReplayRun.swift`) | `docs/archive/v2-session-records/s6.md:8` |
| `mac4DSTEM/App/ReplayPlan.swift` (now `mac4DSTEM/Session/ReplayPlan.swift`) | `docs/archive/v2-session-records/s6.md:12` |
| `mac4DSTEM/App/SessionGates.swift` (now `mac4DSTEM/Session/SessionGates.swift`) | `docs/archive/v2-session-records/s7.md:6` |
| `mac4DSTEM/App/StrainProduct.swift` (now `mac4DSTEM/Session/StrainProduct.swift`) | `docs/archive/v2-session-records/s8.md:16` |
| `mac4DSTEMTests/GateBScratchTests.swift` (created and deliberately deleted at session end) | `docs/archive/v3/c7-gate-b-2026-09-08.md:186` |
| `mac4DSTEM/Session/PrecipitateProduct.swift` (branch-only path, `ml/disk-detector`, never merged) | `docs/archive/v3/c8-triage-2026-09-08.md:35` |
| `mac4DSTEM/UI/PrecipitateSettings.swift` (branch-only) | `docs/archive/v3/c8-triage-2026-09-08.md:37` |
| `mac4DSTEM/Session/DiskLabelStore.swift` (branch-only, dropped by owner decision) | `docs/archive/v3/c8-triage-2026-09-08.md:40` |
| `mac4DSTEM/UI/DiskLabelRows.swift` (branch-only, dropped) | `docs/archive/v3/c8-triage-2026-09-08.md:40` |
| `mac4DSTEM/UI/PrecipitateSettings.swift` (branch-only) | `docs/archive/v3/c8-triage-2026-09-08.md:81` |
| `Contents/Resources/` (bare, not repo-rooted — build-product path, correct in context) | `docs/archive/v3/v3.0.0-closeout-2026-09-11.md:136` |

Two patterns dominate: (1) `docs/v2-release.md`, `docs/visual-acceptance-checklist.md`
and `docs/consolidation-plan.md` were later moved into `docs/archive/`, and
every v2-session-record's header line ("moved verbatim from `docs/v2-release.md`
§9…") is a historical provenance statement rather than a live pointer — the
same shape as `CHANGELOG.md`'s exempted "names what existed at a past version."
(2) Six Swift-file citations in `s1`/`s3`/`s6`/`s7`/`s8`/`s13` name 2026-08-era
`App/*.swift` paths for types the later Session-package split moved to
`Session/*.swift` — a real path drift, not a fabricated citation, but one an
inventory-style check would still flag if it walks archive files.

## Table 5 — totals

| | files | lines |
|---|---:|---:|
| **Total** | 49 | 7972 |

Rows per verdict / lines per verdict:

| verdict | rows | lines |
|---|---:|---:|
| →archive (stays as is) | 45 | 7507 |
| delete | 3 | 93 |
| →ADR | 1 | 372 |

Class totals (the two the deliverable asks for; two smaller classes —
`decision` (`c8-triage-2026-09-08.md`, 86 lines) and `howto`
(`sped-phase-mapping-reference-2026-09-11.md`, 121 lines) — make up the
remaining 207 lines):

| class | lines |
|---|---:|
| gate-evidence (must stay) | 5485 |
| status/history | 2280 |
