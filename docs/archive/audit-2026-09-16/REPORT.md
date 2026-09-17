# Audit report — docs and code, 2026-09-16

Companion: [`phase-b-report.md`](phase-b-report.md) — the hygiene slice's own report (rows 1, 2, 3, 10).

Read-only audit of `a960665` (`ai-analysis`). Nothing outside `docs/audit/` was
touched. Six Sonnet agents produced the inputs; this file is the synthesis.
Numbers are from this audit's own runs, named by file below.

| Input | Scope | File | Size |
|---|---|---|---|
| Docs inventory, live | 33 `.md` outside `docs/archive/` (8 641 lines), per-section rows | `docs-inventory-live.md` | 552 rows |
| Docs inventory, archive A | `docs/archive/v1.0`, `v2` (23 files, 12 169 lines), per-file rows | `docs-inventory-archive-A.md` | 23 rows |
| Docs inventory, archive B | `v2-session-records`, `v3`, `2026-*` reviews (49 files, 7 972 lines) | `docs-inventory-archive-B.md` | 49 rows |
| Docs inventory, archive C | top-level `docs/archive/*.md` (16 files, 8 352 lines) | `docs-inventory-archive-C.md` | 16 rows |
| Code metrics | unused symbols, duplicates, largest files, untested funcs, build times | `code-metrics.md` | 1 025 lines, tables A–H |
| Fresh eyes | CLAUDE.md + ARCHITECTURE.md written from a markdown-free copy of the tree | `fresh-eyes/` | 97 + 462 lines |
| Synthesizer's own | Core file → gated-harness coverage (from `tools/lib/sources.manifest`) | §3.1 below | 62 files |

Totals: 121 tracked `.md`, 37 134 lines. Live 8 641; archive 28 493 (88 files).

## 1. Proposed final doc set

### 1.1 Five files

| File | Budget | Holds | Built from |
|---|---|---|---|
| `CLAUDE.md` | ≤ 1 page (~60 lines) | Only what code cannot enforce (§2.2 list): Gate D trigger + exemptions, refuter rule, break-every-test, no-pipe exit codes, log-name rule, residency nil, push/commit rule, docs-are-done + AGENTS sync, on-screen-claim rule, no `CODE_SIGNING_ALLOWED=NO` on a launched build, threshold-on-every-dataset rule; read order; build/test lines | current `CLAUDE.md` minus front-matter history, minus everything §2.1 shows the code already says |
| `ARCHITECTURE.md` | ~350 lines | Layering + enforcement, ownership today, data flow file→screen, where files go, UI contract (6 rules), tools/harness structure, HDF5 notes, limitations, developer notes | `docs/architecture.md` (drop the SUPERSEDED presentation-contract section, 60 lines; fix C5 wording) + fresh-eyes §3, §4, §7, §8 (verified content only) |
| `decisions/` | one file per ADR, ~30 files | §1.2 | `docs/decisions.md` 97 entries → 30 topic ADRs; 21 superseded entries dropped or listed as "superseded by" |
| `RELEASE.md` | ~220 lines | Release contract, arch pin, notarize/staple, the Releases table, versioning rule | `docs/releasing.md` (near-canonical already) + `status.md` §Releases + decisions 2026-09-02 "Naming" |
| `open-items.md` | ≤ 12 lines/item, live only | Defects and debts; the handoff paragraph moves to its top | `docs/open-items.md` trimmed (41 of 77 items exceed 12 lines); 11 near-closed items → archive |

Kept beside them, unchanged in role: `README.md`, `CHANGELOG.md` (full record),
`CONTRIBUTING.md` (deduped to pointers), `LICENSE`/`NOTICE`/`CITATION.cff`,
the four `.claude/skills`, and three reference specs that do not fit any of
the five without bloating it: `dm4-format.md` (331), `q-calibration-design.md`
(634), `py4dstem-pipelines.md` (352, §7–10 → archive). Recommendation: move
these three to `docs/reference/` and link from `ARCHITECTURE.md` rather than
inline 1 300 lines. `AGENTS.md` stays generated. `status.md` dissolves: its
Releases table → `RELEASE.md`, its step table → archive, its handoff →
`open-items.md`, its gate table → the closeout commit message.

### 1.2 ADR list (from `docs/decisions.md`, grouped by topic)

| ADR | Title | Source entries (date) | State |
|---|---|---|---|
| 001 | Layering: DSTEMCore / DSTEMSession packages, `package` access, Core never reaches up | 08-17, 09-02 (×2), 09-03 | live |
| 002 | `AppState` is the composition root; new state names its owner; C5 size is reported, not gated | 08-17, 09-07, 09-16 | live (09-07 hard form superseded) |
| 003 | Gate D: trigger, exemptions, refuter, fixture | 08-18, 09-04 | live |
| 004 | Gate B: independent review of science; review the diagnosis | 08-18, 09-02 | live |
| 005 | The inventory gate is the repo's review | 09-02, 09-03 (grep rule 3) | live |
| 006 | py4DSTEM pin fetched not vendored; DEVIATION notes cite it | 09-03, 09-14 (`Crystal.reflections`) | live |
| 007 | Versioning: v2.0.0 named never built, v2.5, v3; patch vs minor | 09-02 (×2), 09-11 | live |
| 008 | macOS 14 floor; arm64 only and the artefact proves it | 09-04, 09-11 | live |
| 009 | The UI contract: SwiftUI only, no AppKit shell, `LayoutPolicy`, three columns, no focus model, no new state on `AppState` | 09-03, 09-04 (×4) | live (09-03 AppKit entries superseded) |
| 010 | System-only presentation; toolbar and sidebar own the run action and trust | 09-03, 09-04 | live |
| 011 | Status strip: reserved slot → throughput leaves the strip; a readout is not an event | 09-04, 09-12 (×2) | live |
| 012 | Refusals not defaults: `probeSize` nil, a file's labels decide datacube-ness, DM4 calibration domains | 09-04, 09-05 (×2) | live |
| 013 | Residency `.automatic` dropped; `measuredWorkingSetFraction` stays nil | 08-19 (in archive open-items) | live, only in CLAUDE.md today |
| 014 | Learned disk detector: NE-native design, Core ML runtime, 256 px, default 0.7, labels in sidecar | 09-06, 09-07, 09-08 (×3) | live |
| 015 | Even-count median pinned to `np.median` below the `all` gate | 09-09 | live |
| 016 | Accessibility crash does not block a release; VoiceOver deferred | 09-11 | live |
| 017 | Clicking a pane selects it again | 09-11 | live |
| 018 | AI pipeline on `main`, sixth workspace, not one folder; PCA stays; ridge parked | 09-11 (×5) | live |
| 019 | Precipitates: density by classifying patterns; template-matched and material-general; ship only if the baseline is beaten | 09-11 (×3) | live |
| 020 | `-DACCELERATE_NEW_LAPACK` via `unsafeFlags` accepted | 09-11 | live |
| 021 | Phase mapping lands unvalidated; matrix stated by the user; β″ built in; angle modulo symmetry; chance guard; completeness | 09-12 (×6) | live |
| 022 | Two verdicts a user reads: matrix last word; spotty annulus refused | 09-14 | live |
| 023 | Ellipse refusal is a degeneracy bound; the flag sits behind a click | 09-14, 09-15 | live |
| 024 | Rotation null keeps the field's structure; zone-axis sweep is its own null | 09-15 (×2) | live |
| 025 | HDF5 serialised by a lock, not an actor | 09-15 | live |
| 026 | Step 3: Friedel floor, reach, detection default 0.5 %, cliff ¾ pair radius, OR as parallel vectors, stopping rule | 09-15 (×5), 09-16 | live |
| 027 | `unit` free-space floor 4 GB | 09-12 | live |
| 028 | Three rules overruled (C5 form, on-screen claims, commit freely); the merge split | 09-16 | live |
| 029 | A threshold is measured on every dataset first; no mechanism from a null | 09-16 (development-process) | live |
| 030 | Promoted from the archive (no live home today): symmetric test constants blind mutation suites (S8); a gate that stops at the first red hides the second; too-loose tolerances fail silently; archival is verbatim; `max(0,.nan)==0`; cross-file `nonisolated` extension trap; never edit `run-tests.sh` mid-gate; matrix fall-back off by default | archive A T2, B T2, C T3 | to write |

Dropped as history (21 of 97): the C0–C8 session records, the three AppKit
column entries, `UI2` prefix, tag-before-ship, "consolidate before any
feature", the two unattended-session decision lists, C7 session notes.

### 1.3 Mapping: every existing doc → destination

Live set (33 files). Verdict counts over 552 section rows: →open-items 81,
→ARCHITECTURE 78, →ADR 43, →archive 39, →CLAUDE 10, →RELEASE 8, delete 4.

| Existing | Lines | Goes to | Note |
|---|---|---|---|
| `CLAUDE.md` | 100 | `CLAUDE.md` | front matter is stale (says v3.0.0 not cut); history lines out |
| `AGENTS.md` | 108 | generated | stays; regenerate after the edit |
| `README.md` | 141 | `README.md` | duplicated numbers (gate counts, DMG hash) → pointers to `RELEASE.md` |
| `ROADMAP.md` | 126 | archive | doubly stale (v2.5.1 "current"); its 3 architecture lines → `ARCHITECTURE.md` |
| `CONTRIBUTING.md` | 108 | `CONTRIBUTING.md` | "Where code goes" and Build sections → pointers |
| `CHANGELOG.md` | 518 | stays | full record; `RELEASE.md` summarises |
| `docs/status.md` | 184 | dissolved | Releases → `RELEASE.md`; step table → `archive/v3/`; handoff → `open-items.md` |
| `docs/v3-plan.md` | 170 | `ARCHITECTURE.md` §Plan + ADR 014/019 | §1 decided items are ADRs |
| `docs/open-items.md` | 1 378 | `open-items.md` | trim 41 items; 11 near-closed → `archive/closed-items-2026-09.md` |
| `docs/development-process.md` | 238 | `CLAUDE.md` (6 rules) + ADR 003/004/029 + archive (review post-mortem) | the "eleven working methods" are the CLAUDE.md core |
| `docs/architecture.md` | 308 | `ARCHITECTURE.md` | delete SUPERSEDED section; fix C5 wording |
| `docs/decisions.md` | 1 579 | `decisions/` | 97 → 30 ADRs; file itself → archive as the verbatim record |
| `docs/releasing.md` | 197 | `RELEASE.md` | as is |
| `docs/dm4-format.md` | 331 | `docs/reference/` | linked from `ARCHITECTURE.md` |
| `docs/q-calibration-design.md` | 634 | `docs/reference/` | 3 owner-decision sections → ADR; fix its two `docs/v2-release.md` citations (moved) |
| `docs/py4dstem-pipelines.md` | 352 | `docs/reference/` §0–6; §7–10 → archive | |
| `docs/ai-ml/README.md` | 284 | `ARCHITECTURE.md` appendix or `docs/reference/` | stale commit/push line |
| `docs/ai-ml/precipitates.md` | 167 | archive | describes the superseded route without saying so; cites a PNG that does not exist |
| `docs/v3-phase-mapping-method-choice.md` | 101 | ADR 021 | its "still blocking" list has 2 resolved items |
| `docs/v3-precipitate-classification.md` | 270 | `docs/reference/` + ADR 019 | §5 (117 lines) → pointer once its decisions are ADRs |
| `docs/v3-vector-matching-plan.md` | 221 | `docs/reference/` + `open-items.md` (build order) | most cross-referenced live content |
| `tools/*/README.md` (4) | 601 | stay with their tools | `disk-detector/README.md` two dated sections → archive |
| `.claude/skills/*` (4) | 268 | stay | `pickup` still says "commit only if asked" (both copies); `.agents/` copies of `closeout` and `pickup` are behind — generate them or delete `.agents/` |

Archive (88 files, 28 493 lines): **82 stay as is** (cited by live docs, or
Gate B/D evidence — 5 485 lines of B's scope alone are gate evidence); **6
delete** (236 lines): `v2/distribution.md` (merged verbatim into
`releasing.md`), `v2/development-history.md` (pointer index), `tidy-session-plan.md`
(executed checklist; its one lesson already in the adversarial-review skill),
`2026-08-31-review/verification/review-{data-crystal,physics-export,tests-workflow}.md`
(uncited; content in that review's README). **2 hold an unrecorded decision**
to extract into ADR 030 and then stay: `v2/development-process-v2.md`,
`v3/step3-2026-09-16.md`. Uncited but real evidence worth a live link:
`2026-09-11-drive/origin-cleared-gate-d.md`, `v3/ai-port-2026-09-11.md`.
`consolidation-plan.md` §7: all five criteria are marked Met with evidence, as
`CLAUDE.md` claims.

### 1.4 Facts stated in more than one place (top of ~40 clusters; full list `docs-inventory-live.md` Table 2)

| Fact | Places | Status |
|---|---|---|
| Gate D trigger | 9 | consistent |
| Independent refuter approves science changes | 8 | consistent |
| `AppState` single source of truth / Core holds compute | 7 | consistent |
| Push is the owner's | 6 | **contradicted**: both `pickup` skills say "commit only if asked" |
| Residency nil rule | 6 | consistent |
| Break every new test first | 6 | consistent |
| Consolidation plan exited 2026-09-11 | 6 | consistent |
| Build/test command block | 5 | `CONTRIBUTING.md` lists 3 of 7 lanes |
| No-pipe exit-code rule | 5 | consistent |
| DEVIATION notes | 5 | consistent |
| Learned-detector recall/precision numbers | 5 | consistent |
| Metal struct byte-identity | 4 | consistent |
| "v3.0.0 prepared and not yet cut" | 3 (`CLAUDE.md`, `AGENTS.md`, `ROADMAP.md`) | **stale**: released 2026-09-11 |
| Dev machine on macOS/Xcode 26 | 3 | **stale**: this machine runs Xcode 27.0 |
| C5 hard "never net positive" form | `architecture.md` | **stale**: overruled 2026-09-16 |

Broken citations in live docs: `docs/images/precipitates-al-simg-near-beam-2026-09-07.png`
(two files) and `docs/v2-release.md` (twice in `q-calibration-design.md`).

## 2. Fresh-eyes vs existing docs

Method: a Sonnet agent got a copy of the tree with every `.md` removed and the
instruction to write both files from code and tests. Caveat: the agent's own
system prompt carries the project's `CLAUDE.md`; it was told to treat that as
unavailable and to trace every claim to a file. Spot checks below found its
claims traced to code comments and gate scripts, not to `CLAUDE.md` wording.

### 2.1 Got right from code alone — docs do not need to say it

| Fact | Where the code says it | Verified |
|---|---|---|
| Core/Session never reach up; two SwiftPM targets enforce it | `Package.swift` comment; `run-tests.sh core` | yes |
| UI is SwiftUI only; the four split-view names and `import AppKit` are grepped | `run-tests.sh inventory` | yes |
| `LayoutPolicy` is the number budget; two grep exemption lists | `run-tests.sh inventory`, `LayoutPolicy.swift` | yes |
| Metal param structs byte-identical, 4-byte fields | `MetalEngine.swift` "PARAM STRUCT CONTRACT", `// MUST match` in 6 of 8 shaders | yes |
| DEVIATION comments cite the pinned py4DSTEM | 36 under `mac4DSTEM/` (metrics count; fresh-eyes said 33) | yes |
| Every `tools/*/run.sh` sources `sources.manifest` or says why; groups are dependency-closed | manifest header, inventory | yes |
| Every `tools/` dir classified in one array | `run-tests.sh` | yes |
| `AppState.swift` + `ResultExport.swift` size tracked; hard form relaxed 2026-09-16 | `run-tests.sh:169-176` | yes |
| NOTICE hashes, no absolute load paths, folder-reference files tracked | inventory | yes |
| One `AppState` per window; libhdf5 process-wide | `mac4DSTEMApp.swift` | yes |
| GPU dispatch is synchronous; call from a background Task | `MetalEngine.swift`, `VirtualDetector.swift` | yes |
| MainActor default isolation; harness blind spot; app build is the only isolation gate | `Package.swift`, manifest | yes |
| `DisplayedProduct` carries pixels + domain + status + provenance together | its header | yes |
| Sidecar rewrite refusal; provenance snapshotted at compute time | `SessionGates.swift`, `ResultExport.swift` | yes |
| Free-space preflight 4/8 GB, exit 69 | `run-tests.sh` | yes |
| CI runs unit/scientific/inventory/core on `macos-26` | `ci.yml` | yes |
| arm64-only guard is `#error`, not a silent `#if` | `LearnedDiskDetector.swift` | yes |
| Views add no state; `WorkspaceRoute` derived | `WorkspaceRoute.swift` | yes |
| "UNVERIFIED ON SCREEN" is a code tag | `mac4DSTEMApp.swift:35` | yes |

Consequence: about half of today's `CLAUDE.md` hard-rules block and most of
`architecture.md` §Layers restate what a gate or a compiler already holds. The
proposed `CLAUDE.md` keeps one line each pointing at the enforcing mechanism.

### 2.2 Missed or wrong — load-bearing, must survive in CLAUDE.md or an ADR

| Rule / fact | Why code cannot carry it |
|---|---|
| Gate D: trigger, what does not need it, diagnosis before fix, refuter after, fixture; the three wrong diagnoses | process; no gate can hold it |
| Gate B: the model that wrote a science change never approves it alone; review the diagnosis, not the diff | process |
| Break every new test before trusting it | process |
| Never read a gate's exit code through a pipe; count tests by method name and reconcile | tooling habit; the script cannot stop `\| tail` |
| A log name is a name; evidence a reader must open lives under `docs/archive/` | convention |
| Do not set `ResidencyAdmission.measuredWorkingSetFraction` | code allows it |
| Commit freely; pushing is the owner's | policy |
| Docs are part of done; `status.md`/`open-items.md` in the same commit; run `sync-agents-md.sh` | policy (inventory checks sync, not the habit) |
| On-screen claims only when actually driven; otherwise "unverified on screen" | policy |
| Never `CODE_SIGNING_ALLOWED=NO` on a build you intend to launch | tooling |
| A threshold is measured on every dataset first; no mechanism from a null result (2026-09-16) | process |
| "Nothing ships that can fabricate a scientific result; no gate is widened to make something pass" | policy (only in archive today) |
| What is released: v3.0.0 on 2026-09-11; v2.0.0 named, never built | history; `CITATION.cff` gave it 3.0.0 only |
| The science defaults and their reasons: 0.5 % detection, cliff ¾ pair radius, matrix stated by the user, OR as parallel vectors, R–Q 180° ambiguity | decisions |
| The demo cube is the fixture; the ellipse is not fitted on it | decision |
| Where ownership is going: `AnalysisRunner` unscheduled; `ScientificProduct` target | plan |
| Known limitations list (float32 tiles, no Metal fallback, Preview readers) | judgement |

Wrong or imprecise in fresh-eyes: "~50 scientific harnesses" (roster is 46);
"~70 tools directories" (67); its CLAUDE.md is 97 lines, above the one-page
ask; DEVIATION count disagreed between its own passes (33 vs 28).

### 2.3 Found in code that no doc records (fresh-eyes bonus, verified here)

| Finding | Location |
|---|---|
| Stale comment names `FormPolicy`/`WindowPolicy`/`FormControls.swift`; none exist | `tools/run-tests.sh:210-211` |
| `ACOMMetalParams` ↔ `ACOMParams` is the one shader pair without a `MUST match` comment | `OrientationMatcher.swift:389`, `ACOMMatching.metal:4` |
| `OrientationMatcher` builds its own pipeline state instead of `MetalEngine`'s cached path | `OrientationMatcher.swift` |
| A test header cites `App/StrainProduct.swift`; the type lives in `Session/` | `mac4DSTEMTests` (agent report) |
| The presentation contract has no XCTest counterpart; only shell greps | `run-tests.sh` vs `mac4DSTEMTests/` |

## 3. Ranked refactor list

Numbers from `code-metrics.md` (static greps, builds only, no suites run) and
from the synthesizer's coverage matrix (§3.1). Machine: M3, 8 GB, Xcode 27.0,
Swift 6.4. "Parity" names the gated harnesses that COMPILE the file (from
`tools/lib/sources.manifest`); assertion coverage is narrower.

### 3.0 The numbers the ranking rests on

| Metric | Value |
|---|---|
| Source lines by layer | Core 28 897 (62 files) · tools 20 439 (66) · Tests 17 596 (65) · UI 10 740 (25) · App 7 524 (9) · Session 4 544 (22) · Support 2 099 (2) · Shaders 557 (8) |
| Largest files | `App/AppState.swift` 5 461 · `Core/Data/BraggVectorEMDWriter.swift` 2 890 · `Tests/PhaseVectorMatchingTests.swift` 2 023 · `Support/ResultExport.swift` 1 939 · `tools/cif-symmetry-test/main.swift` 1 268 · `UI/ImagePanes.swift` 1 248 · `Core/Crystal/PhaseVectorMatching.swift` 1 246 · `Core/Analysis/DiskDetection.swift` 1 187 |
| `AppState` | 209 stored members, 6 extension files, referenced from 101 files |
| Zero-reference symbols (static) | 12 candidates; 5 are `NSViewRepresentable`/`UIViewRepresentable` requirements → 7 real: `AppState.acomBackendSummary`, `AppState.availableComputedProducts`, `Colormaps.shortDisplayName`, `ProductWorkflow.recommendedNextArea`, `ResultExport.exportBraggPeaksCSV`, `ResultExport.exportBraggVectorsEMD`, `ZoomPan.isZoomedIn` |
| Duplicated helpers | 132 same-name groups (most are protocol conformances: `readScanTile` ×6, `reset` ×7, `clear` ×7); **30 identical-body groups**, 13 of them in production code (list in 3.2) |
| Non-private funcs with no test/tool name reference | App 64/122 (52 %) · Support 12/27 (44 %) · Session 19/117 (16 %) · Core 47/384 (12 %) |
| Core files compiled by no gated harness | 11 of 62 (§3.1) |
| Tests | 672 `func test` in 65 files; 5 `XCTSkip` sites |
| tools/ | 67 dirs: 46 scientific (CI) + 2 `all`-only + 16 diagnostic + 3 support; none unclassified |
| Markers | `DEVIATION` 36 · TODO/FIXME/HACK 0 · `deprecated` 2 |
| Metal struct parity | 5 pairs, all field counts match; `ACOMParams` pair lacks the `MUST match` comment |
| Build, cold → warm | DSTEMCore 25 s → 2 s · DSTEMSession 9 s → 1 s · app 59 s → 4 s (5 compiler warnings) · tests +19 s |

### 3.1 Core file → gated harnesses (blast radius for anything in `Core/`)

| Harnesses | Files |
|---|---|
| 0 | `Analysis/DatasetPreview` (2 test files) · `Analysis/RotationCalibration` (1 test file, `rotation-null-probe` diagnostic; **a py4DSTEM port with no parity harness**) · `Analysis/Precipitates/*` (3 files, 1 test file) · `Compute/MTLTexture+Float` (0 tests) · `Data/DisplayedProduct` (3) · `Data/LoadConfiguration` (1) · `ML/LearnedDiskDetection` (1) · `ML/LearnedDiskDetector` (4; parity test needs a Neural Engine, skipped in CI) · `Workflow/AnalysisOperationController` (2) |
| 1 | `DiffractionEmbedding` · `EllipseCalibration` · `FitOverlays` · `PtychographyPreparation` · `SingleslicePtychography` · `PhaseMapPresentation` · `PhaseReferenceLibrary` · `PhaseVectorMatching` · `ResultPresentation` |
| 2–5 | `CIFImport` 2 · `OriginCalibration` 3 · `StrainFrame` 3 · `StrainMapping` 3 · `DPC` 4 · `OrientationMatcher` 4 · `OrientationPlan` 4 · `QCalibration` 4 · Parallax chain 5 each · `Crystal`/`CrystalModel`/`ScatteringFactors` 5 · `OrientationResult` 5 |
| 6–13 | `ParallaxPreprocessing` 6 · `BraggVectorEMDWriter` 6 · `DM4Reader`/`VendorRawReaders`/`SessionReplayRecord` 7 · `TiledDiskDetection`/`VirtualDetector`/`DemoFourDDataSource` 8 · `FourDArray`/`ResidentCube` 10 · `MetalEngine` 11 · `H5Reader`/`HDF5Types` 13 |
| 20–35 | `DiskDetection`/`ProbeKernel` 20 · `FFT2D`/`MatrixDFTCorrelation` 26 · `AnalysisCancellationToken` 28 · `Calibration`/`CalibrationReReference` 32 · `DatasetDescriptor`/`DiffractionPattern`/`FourDDataSource`/`LoadSpecification` 35 |

### 3.2 Ranked list

Ordered by payoff against risk; the owner decides scope. **AR** = adversarial
review (Gate B) required; every `Core/` row carries it regardless of risk.

| # | Change | Blast radius | Parity tests covering | Risk to science | AR |
|---|---|---|---|---|---|
| 1 | Dedupe two byte-identical UI bodies: `readinessAction` (66 lines) and `manualScaleRows` (18) in `ExportSheet.swift` and `PrepareSettings.swift` | 2 UI files | none compile UI (`peak-overlay-test` compiles one other UI file); unit tests only | none | no |
| 2 | Delete the 7 real zero-reference symbols after checking menu/command wiring by string (`exportBraggPeaksCSV`, `exportBraggVectorsEMD` are the surprising two: the README advertises CSV export, so find the live path first) | 5 files | none | none if truly dead; **verify before delete** | no |
| 3 | Fix three stale comments: `run-tests.sh:210-211` (`FormPolicy`/`WindowPolicy`/`FormControls.swift`), the test header citing `App/StrainProduct.swift`, add `// MUST match ACOMMetalParams` to `ACOMMatching.metal:4` | 3 files | — | none | no |
| 4 | `tools/lib/harness.swift`: one `fail`/`check`/`maximumError`/`readPattern`/`readScanRow`/`readScanTile` shared by the harness mains (identical bodies in 4–12 harnesses each) | every harness that adopts it (up to 46) | the harnesses ARE the gate | none to results; **high to the gate itself** (a shared `fail` that stops exiting non-zero greens 46 harnesses at once) | yes, on the helper; break it before trusting it |
| 5 | Continue the `AppState` extractions in the archived plan's §4 order, one seam per session (209 members; 64 of 122 App funcs have no test reference) | 101 files reference `AppState` | none compile `App/` (manifest stops at Core); unit tests only | low for dispatch seams; **high where a calibration snapshot or provenance moves** | when calibration/provenance moves |
| 6 | Split `Support/ResultExport.swift` (1 939 lines, 12 of 27 funcs untested, `field` duplicated at :521/:567) by export kind; keep `originFitProvenance`/`strainFrameProvenance` single-sourced | 2 Support files + the UI export sheet | `bragg-export-test`, `preprocessing-export-test`, `reduced-export-test`, `scientific-bundle-test` (they verify the written file with py4DSTEM) | medium: provenance strings are what py4DSTEM reads back | yes |
| 7 | Split `Core/Data/BraggVectorEMDWriter.swift` (2 890 lines, 24 funcs) by dataset kind; no behaviour change | 6 gated harnesses + `hdf5-race-probe` | `bragg-export-test`, `sidecar-result-test`, `reduced-export-test`, `preprocessing-export-test`, `scientific-bundle-test`, `sidecar-error-detail-test` (3 run `verify_py4dstem.py`) | **high**: this is the wire format; a byte moved is a file py4DSTEM misreads | yes |
| 8 | Consolidate the small identical Core helpers: `nextPow2` (FFT1D/FFT2D), `positiveModulo` (3 sites, 2 bodies), `wrapped` (3), `checkCancellation` (2 identical + 6 same-name), `axisDelta` (CIFImport/CrystalModel), `finiteDouble` (Core/Session), `admits` (TiledDiskDetection/LearnedDiskDetection, 8 lines) | 26 harnesses for FFT2D; 5 for the parallax chain; 2 for `CIFImport` | as listed in §3.1 | low per helper; `admits` is detection admission and sits on both detector paths | yes |
| 9 | **Do not** consolidate `median` (5 Core sites, 5 different bodies: `EllipseCalibration`, `OriginCalibration`, `ParallaxAlignment`, `QCalibration`, `StrainMapping`) without a Gate D showing they should agree: the even-count rule was pinned to `np.median` on 2026-09-09 for one of them and the pinned goldens moved | 4–8 harnesses per site | `q-calibration-gate-test`, `ws2-crystal-test`, `real-data-acceptance`, `strain-test`, `strain-frame-test`, `ellipse-calibration-test`, parallax ×5 | **high** | yes, Gate D first |
| 10 | Close coverage before refactoring there: a parity harness for `RotationCalibration` (no gated harness, 2 `DEVIATION`s); tests for `MTLTexture+Float` (3 funcs, 0 refs) and `MetalEngine.virtualDiffraction`/`dpStatistics` (0 test refs); a CI-runnable stand-in for the Neural Engine parity test | 0 today | — | none (adds gates) | no |
| 11 | Sync or delete the `.agents/skills` mirror (2 of 4 behind); fix `pickup` "commit only if asked" in both copies; regenerate `AGENTS.md` after the `CLAUDE.md` edit | docs/tooling | — | none | no |
| 12 | Trim the four >1 000-line harness mains (`cif-symmetry-test` 1 268, `phase-map-probe` 1 287, `training-dataset-campaign` 1 063, `two-spec-analysis-test` 1 004) once #4 exists | 1 harness each | they are the gates | none to results; same caution as #4 | yes, same as #4 |
| 13 | The docs consolidation of §1: live markdown 8 641 → ~4 100 (five files + `docs/reference/` + `README`/`CHANGELOG`/`CONTRIBUTING`), archive −236 lines | every live doc | `inventory` (cited-path check, AGENTS sync, size report) | none | no |

Not proposed: anything in `Shaders/`, the calibration model, the detection
defaults, the fixtures under `tools/*/` and `References/`, or the six UI
contract rules.

## 4. Caveats

- Archive rows are per file, not per section (28 493 lines); the live set is
  per section. Archive "delete" is conservative: a file cited by any live doc
  stays because `inventory` fails on a missing cited path.
- Unused-symbol and untested-function counts are name-reference greps, not
  periphery and not execution coverage (periphery is not installed; nothing
  was installed).
- Harness coverage in §3.1 means "compiled into the harness", not "asserted
  by it"; a rename breaks that many harness builds, which is the blast radius
  that matters for a refactor.
- Fresh-eyes contamination risk stated in §2; its ARCHITECTURE.md is worth
  reading in full, its CLAUDE.md is not a drop-in.
- Nothing here changes science, fixtures, thresholds or the UI contract; every
  §3 row touching `Core/` is marked for adversarial review regardless of risk.
