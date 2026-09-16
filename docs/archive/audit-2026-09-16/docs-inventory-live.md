# Docs inventory — live set (outside docs/archive/)

Scope: the 33 tracked `.md` files outside `docs/archive/`, 8641 lines (per
`git ls-files '*.md' | grep -v '^docs/archive/'`). Three sibling agents cover
`docs/archive/`. Read in full: every file below, including both 1300+-line
files (`docs/open-items.md`, `docs/decisions.md`) end to end.

**Verdict-mapping convention.** The stated target final doc set is
`CLAUDE.md` (hard rules), `ARCHITECTURE.md`, a `decisions/` folder (one ADR
per decision), `RELEASE.md`, and one `open-items` file — it does not name a
`status.md`. Where content is pure "what shipped, what version" it is routed
`→RELEASE.md`; pure dated "done 2026-09-XX, gate X" narrative is routed
`→archive` (it is history, not a next step); the live unresolved
handoff/next-steps content is routed `→open-items.md` as the nearest live
target. `README.md`, `CHANGELOG.md`, `ROADMAP.md`, `CONTRIBUTING.md`, and the
skill files are public-facing/tooling artifacts outside the "internal docs
consolidation" the target set describes — they are not being folded into the
five targets, so their rows record what content is DUPLICATED from (or
should defer to) the internal set, not a literal merge instruction; this is
called out per row in the note.

## Table 1 — one row per section

`path | section | lines | class | duplicate-of | verdict | note`

### CLAUDE.md (100 lines, 3 sections + front matter)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| CLAUDE.md | (front matter, lines 1-9) | 9 | status/history | AGENTS.md#front-matter (verbatim) | →RELEASE.md | **STALE**: says "v3.0.0 is prepared and not yet cut" — contradicted by status.md's Releases table, CHANGELOG.md `## v3.0.0 — 2026-09-11`, and README.md `## New in v3.0.0 (2026-09-11)`, all confirming v3.0.0 shipped. This is the first file every session reads. |
| CLAUDE.md | Read, in order | 19 | rule/invariant | AGENTS.md#Read-in-order (verbatim, generated) | keep→CLAUDE.md | doc map; load-bearing |
| CLAUDE.md | Hard rules | 63 | rule/invariant | AGENTS.md#Hard-rules (verbatim); individual bullets duplicated across many files, see Table 2 | keep→CLAUDE.md | the target file; see Table 2 for per-rule fan-out |
| CLAUDE.md | Build/test | 7 | howto | AGENTS.md (verbatim); architecture.md#Requirements-build-test; CONTRIBUTING.md#Building (narrower, missing 4 of 7 lanes) | keep→ARCHITECTURE.md | commands belong beside build/test entry points in the target ARCH doc; CLAUDE.md could keep a one-line pointer |

### AGENTS.md (108 lines) — generated

Verified via `tools/sync-agents-md.sh --check`: **in sync** with CLAUDE.md
(see Table 5). Every row below is a byte-identical or anchored-substitution
copy of the corresponding CLAUDE.md row.

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| AGENTS.md | (front matter, incl. generator banner) | 15 | status/history | CLAUDE.md#front-matter (same stale claim, propagated) | delete | generated; fixing CLAUDE.md's front matter and re-running the sync script fixes this automatically |
| AGENTS.md | Read, in order | 19 | rule/invariant | CLAUDE.md#Read-in-order (verbatim) | delete | generated copy |
| AGENTS.md | (skills passage, the one deliberate substitution) | 5 | rule/invariant | CLAUDE.md's skills line (substituted, not duplicate) | keep | correctly non-Claude-Code-agent-specific; the one place AGENTS.md must differ from CLAUDE.md |
| AGENTS.md | Hard rules | 63 | rule/invariant | CLAUDE.md#Hard-rules (verbatim) | delete | generated copy |
| AGENTS.md | Build/test | 7 | howto | CLAUDE.md#Build-test (verbatim) | delete | generated copy |

### README.md (141 lines)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| README.md | (front matter/badge/hero image) | 27 | status/history | - | keep | public front door; stays as its own file regardless of internal consolidation |
| README.md | New in v3.0.0 (2026-09-11) | 27 | status/history | CHANGELOG.md `## v3.0.0` (condensed restatement) | →RELEASE.md (content); keep (file) | duplicates the CHANGELOG header; recall/precision numbers (0.768/0.712, 0.667/0.840) repeated verbatim in CHANGELOG.md and v3-plan.md §3a |
| README.md | What it does | 20 | architecture | architecture.md "What it does, by subsystem" (loose overlap, different granularity) | keep→ARCHITECTURE.md (content origin) | public capability list; not a literal duplicate, source of truth should be architecture.md |
| README.md | Verification | 29 | status/history | CHANGELOG.md "Verified by" (v2.5.1); status.md gate table; ROADMAP.md "Current baseline" | →RELEASE.md | four numbers repeated near-verbatim elsewhere: `all` exit 0, 458/0/0 44 harnesses (2026-09-04), DMG SHA-256, badge description |
| README.md | Requirements | 10 | rule/invariant | architecture.md "Requirements, build, test" (macOS 14+ line, verbatim) | keep→ARCHITECTURE.md | |
| README.md | Building | 8 | howto | CLAUDE.md/AGENTS.md Build/test; CONTRIBUTING.md Building | keep→ARCHITECTURE.md | |
| README.md | Contributing | 6 | howto | CONTRIBUTING.md (pointer only) | keep | trivial pointer, no content to dedupe |
| README.md | Citing | 5 | rule/invariant | - | keep | unique, CITATION.cff pointer |
| README.md | Licence | 6 | rule/invariant | CONTRIBUTING.md#Licence (near-identical GPL-3.0 statement) | keep | |
| README.md | Contact | 3 | rule/invariant | - | keep | unique |

### ROADMAP.md (126 lines)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| ROADMAP.md | (front matter) | 8 | status/history | v3-plan.md, status.md (pointers) | →archive | pointer only |
| ROADMAP.md | Phase status (2026-09-11) | 21 | **stale** | CLAUDE.md/AGENTS.md front matter (same wrong claim) | →archive | **STALE, self-flagged**: status.md's own 2026-09-16 handoff says verbatim "`ROADMAP.md` still says 'v2.5.1 is the current release' and 'v3.0.0 is prepared and not yet cut'. It predates the v3.0.0 release of 2026-09-11." Not fixed since. |
| ROADMAP.md | Version policy | 7 | rule/invariant | decisions.md 2026-09-02 "Naming" (near-identical semver policy) | →ADR | restates a decisions.md entry |
| ROADMAP.md | Current baseline | 19 | status/history | README.md Verification; CLAUDE.md Build/test | →archive | |
| ROADMAP.md | Priority 1 — scientific interpretation | 18 | rule/invariant | v3-plan.md §2 (parity themes) partial overlap | keep→ARCHITECTURE.md | "appendix/reference"; standing priorities, not superseded but overlaps v3-plan's newer, dated priority framing |
| ROADMAP.md | Priority 2 — product clarity | 8 | rule/invariant | architecture.md "The UI contract" (more current, dated 2026-09-04) | keep→ARCHITECTURE.md | UI contract in architecture.md supersedes the generality here |
| ROADMAP.md | Priority 3 — incremental architecture | 15 | rule/invariant | CLAUDE.md AppState rule; architecture.md "Ownership today..."; CONTRIBUTING.md | keep→ARCHITECTURE.md | says "binding per-stage rule ... in CLAUDE.md" — itself points at the newer source |
| ROADMAP.md | Release-owner actions | 11 | status/history | releasing.md (fuller); decisions.md 2026-09-04 macOS floor | →RELEASE.md | "No release is pending" is now false (v3.0.0 shipped 2026-09-11) — a second staleness in this file beyond the Phase-status one |
| ROADMAP.md | Scope rule | 15 | status/history | v3-plan.md (current); archive/v2/* (frozen) | →archive | describes v1/v2/v2.5/v3 scope, mostly historical framing already |

### CONTRIBUTING.md (108 lines)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| CONTRIBUTING.md | (front matter) | 6 | rule/invariant | - | keep | unique framing |
| CONTRIBUTING.md | Reporting a problem | 16 | howto | - | keep | unique, external-contributor-facing |
| CONTRIBUTING.md | Building | 20 | howto | CLAUDE.md/AGENTS.md Build/test (narrower: lists only unit/scientific/all, missing inventory/core/benchmark/campaign) | keep→ARCHITECTURE.md | **incomplete relative to the 7-lane list elsewhere** — not contradictory, just stale/thin |
| CONTRIBUTING.md | Where code goes | 20 | architecture | architecture.md "Project structure and where files go" (near-identical table, this one older/shorter) | keep→ARCHITECTURE.md | two file-placement tables; architecture.md's is the fuller/newer one (includes Core/ML row CONTRIBUTING.md lacks) |
| CONTRIBUTING.md | The rules that actually matter | 28 | rule/invariant | CLAUDE.md Hard rules (AppState, DEVIATION, Metal struct byte-identity, Gate B, widen-gate rules — all restated in different words) | keep→CLAUDE.md | see Table 2; five separate facts each duplicated here |
| CONTRIBUTING.md | Scope | 6 | rule/invariant | ROADMAP.md Scope rule; open-items.md header | →ADR or delete | thin pointer |
| CONTRIBUTING.md | Licence | 6 | rule/invariant | README.md#Licence | keep | |

### CHANGELOG.md (518 lines, 19 headings)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| CHANGELOG.md | v3.0.0 — 2026-09-11 (+ 4 subsections: ML feature, fixes, science, known limitations) | 215 | status/history | README.md New-in-v3.0.0 (condensed); status.md v3.0.0 release row; decisions.md multiple 2026-09-11/12 entries | →RELEASE.md | canonical source for the v3.0.0 release; README.md and status.md both restate subsets |
| CHANGELOG.md | v2.5.1 — 2026-09-04 (+ Verified by) | 39 | status/history | status.md Releases row (near-verbatim numbers: 458/0/0, 44 harnesses, SHA-256) | →RELEASE.md | |
| CHANGELOG.md | v2.5.0 — 2026-09-04 (+ What is new, Verified by) | 98 | status/history | status.md Releases row | →RELEASE.md | |
| CHANGELOG.md | v1.0.0 — 2026-08-06 (+ 6 subsections) | 87 | status/history | status.md Releases row (v1.0.0, one line) | →RELEASE.md | canonical, keep full detail here |
| CHANGELOG.md | Working notes | 7 | status/history | - | keep | pointer to docs/archive/v1.0/ |

### docs/status.md (185 lines, 5 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/status.md | (front matter: log-name convention) | 17 | rule/invariant | CLAUDE.md "no pipes on exit codes" / "log name is a name" rule (same rule, this is its origin/fuller statement) | keep→CLAUDE.md | this is the fullest statement of the rule; CLAUDE.md's is the condensed one — pick one home |
| docs/status.md | Releases | 11 | status/history | CHANGELOG.md (fuller); ROADMAP.md Phase status (**stale** copy) | →RELEASE.md | canonical current-releases table |
| docs/status.md | Where the UI stands (the giant dated step table, ~60 rows) | 60 | status/history | decisions.md (many of the same dated events, e.g. 2026-09-15/16 phase-mapping decisions) | →archive | each row is a closed, dated "done 2026-09-XX" narrative — once done, this is history, not live status |
| docs/status.md | Last gates (retained logs) | 12 | status/history | - | →archive | dated gate-run log, superseded by the next run each time |
| docs/status.md | Handoff — 2026-09-16 | 76 | status/history | open-items.md (T1 reference item, cross-phase winner item both restated); decisions.md 2026-09-16 entries | →open-items.md | this IS the live next-step content; the closest fit of the five targets |
| docs/status.md | Owed to the owner | 5 | status/history | - | →open-items.md | |

### docs/v3-plan.md (170 lines, 7 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/v3-plan.md | (front matter) | 10 | status/history | - | →archive | |
| docs/v3-plan.md | 1. Decided 2026-08-28 (owner) | 34 | decision | decisions.md (no direct dated entry found for this exact set — largely unique) | →ADR | should be split into ADR entries, not left as a plan section |
| docs/v3-plan.md | 2. Parity themes, ranked by value | 11 | architecture | ROADMAP.md Priority 1 (older, overlapping) | keep→ARCHITECTURE.md | appendix/reference |
| docs/v3-plan.md | 3. Beyond py4DSTEM — the differentiators | 24 | decision | v3-precipitate-classification.md (the precipitate item here is explicitly superseded by that doc, and says so in-line: "Superseded 2026-09-11") | keep→ARCHITECTURE.md | appendix/reference; internally marks its own staleness correctly |
| docs/v3-plan.md | 3a. Learned disk candidates — pre-registration | 63 | decision | CHANGELOG.md v3.0.0 ML section; decisions.md 2026-09-06/07/08 entries (C6/C7); status.md C7 rows | →ADR | pre-registration + verdict, now shipped; recall/precision numbers (0.667/0.840) repeated in 3+ places |
| docs/v3-plan.md | 4. Leave alone; where the app is ahead | 7 | architecture | - | keep→ARCHITECTURE.md | |
| docs/v3-plan.md | 5. Open questions for the next pass | 8 | status/history | - | →open-items.md | |
| docs/v3-plan.md | 6. How a v3 feature is done | 7 | rule/invariant | CLAUDE.md front matter ("§6 says how a v3 feature is pre-registered") | keep→CLAUDE.md or ARCHITECTURE.md | referenced by name from CLAUDE.md; process rule |

### docs/open-items.md (1378 lines, 84 headings: 7 lane groups + 77 item entries)

Full per-item breakdown feeds Table 4. Table 1 rows (auto-extracted, one per
`##`/`###` heading):

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/open-items.md | Phase mapping, landed unvalidated 2026-09-12 — added 2026-09-12 | 2 | status/history | - | →open-items.md | lane header |
| docs/open-items.md | Step 3's 2026-09-16 increments — the record is archived, these are the live residuals | 30 | status/history | status.md Handoff (same numbers: 4.21%, 83% refusals) | →open-items.md | exceeds 12-line rule |
| docs/open-items.md | Step 3 ran on a stride-3 subsample and is OUTSIDE their band — measured 2026-09-15 | 158 | status/history | v3-vector-matching-plan.md §3 (same numbers restated); status.md rows | →archive | **158 lines** — by far the longest item; almost entirely closed/superseded narrative (three decisions landed, OR landed) with only the last paragraph still open — should be trimmed to a residual + archived narrative |
| docs/open-items.md | The matrix is a verdict by exclusion, so it fails exactly when detection improves — MEASURED 2026-09-16, Gate D target | 53 | status/history | status.md Handoff item 2 | →open-items.md | live Gate D target, legitimately long but still 4x the rule |
| docs/open-items.md | The Al-Mg-Si cube's peak set is not clean enough — added 2026-09-12 | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | The β″ zone axis for ⟨110⟩Al data is not chosen — added 2026-09-12 | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | Phase mapping's two distance thresholds sit near a cliff — added 2026-09-12, the cliff moved 2026-09-15 | 20 | status/history | decisions.md 2026-09-15 "verdict cliff" entry | →archive | closed as a defect per its own first line ("Closed as a defect, kept as a caution") |
| docs/open-items.md | A stale DerivedData test bundle fakes both a pass and a surviving mutation — added 2026-09-12 | 25 | rule/invariant | development-process.md "Working methods" (same class of trap) | keep→ARCHITECTURE.md | this is a process/tooling lesson, not a live defect — belongs beside development-process.md's "Working methods that earned their keep", not open-items.md |
| docs/open-items.md | The ellipse "Fit anyway" mark: what it does not yet do — added 2026-09-15 | 24 | status/history | decisions.md 2026-09-14(later)/2026-09-15 ellipse entries | →open-items.md | |
| docs/open-items.md | A challenged matrix verdict is drawn like one by exclusion — added 2026-09-15 | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | The rotation null keeps the field's structure now — what it still cannot do — Gate D 2026-09-15 night | 46 | status/history | decisions.md 2026-09-15(night) entry (same content, shorter) | →archive | mostly closed ("Presentation fixed... and SEEN on screen") with 2 residual bullets — trim |
| docs/open-items.md | ACOM returns a zone axis up to 12.8° beyond what its bank forces — MEASURED 2026-09-15 | 27 | status/history | archive/v3/acom-zone-axis-2026-09-15.md (pointer) | →open-items.md | live, unresolved |
| docs/open-items.md | 26 of 200 ACOM templates do not recover themselves at an off-grid rotation — added 2026-09-14 | 33 | status/history | - | →open-items.md | live, unresolved |
| docs/open-items.md | py4DSTEM's `power_radial` is absent from the port, with no DEVIATION note — added 2026-09-14 | 17 | rule/invariant | CLAUDE.md DEVIATION-note rule (this is a violation report of that rule) | →open-items.md | |
| docs/open-items.md | The zone-axis sweep marks a wrong axis against its own median — Gate D 2026-09-15 night, residuals | 41 | status/history | decisions.md 2026-09-15(night) "zone-axis sweep is its own null" | →archive | fix already landed and Gate B'd; only "Residuals" (3 lines) still open — trim |
| docs/open-items.md | Contiguous invalid regions fabricate precipitates — blocks wiring | 17 | status/history | v3-precipitate-classification.md (unwired engine context) | →open-items.md | |
| docs/open-items.md | Non-finite pixels ON a feature erase it silently | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | The robust-sigma constant and the fill statistic are unpinned | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | Dark-contrast ridges register through their flanks — added 2026-09-14 | 12 | status/history | - | →open-items.md | |
| docs/open-items.md | A negative peak collapses an object to 1 × 1, and NaN next to a maximum passes — added 2026-09-14 | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | Repository review 2026-09-09 — added 2026-09-09 | 2 | status/history | - | →open-items.md | lane header |
| docs/open-items.md | 119 unverified defect claims, and the adversarial pass that never ran | 14 | status/history | archive/2026-09-09-review/register.md (pointer) | →open-items.md | |
| docs/open-items.md | The three redistributed dylibs have no rebuild path | 13 | status/history | releasing.md (HDF5/sz/aec embedding, same libs) | →open-items.md | |
| docs/open-items.md | Accessibility — added 2026-09-09 by the delegated drive | 8 | status/history | CHANGELOG.md v3.0.0 Known limitations (VoiceOver); decisions.md 2026-09-11 accessibility entry | →open-items.md | lane header, but content overlaps 3 other files |
| docs/open-items.md | Reading an accessibility label crashes the app — evidence aged off 2026-09-15, suspect named | 33 | status/history | CHANGELOG.md (same crash, one line) | →open-items.md | |
| docs/open-items.md | In-body controls report no accessibility label — the same bug | 14 | status/history | - | →open-items.md | |
| docs/open-items.md | Verification debt — added 2026-09-08 | 2 | status/history | - | →open-items.md | lane header |
| docs/open-items.md | GitHub CI's unit job has been red since the v3.0.0 cut — added 2026-09-14 | 10 | status/history | status.md CI row (same facts, longer) | →open-items.md | |
| docs/open-items.md | The learned-detector parity fixture is a same-runtime claim, and CI has no Neural Engine — added 2026-09-14 | 18 | status/history | - | →open-items.md | |
| docs/open-items.md | The published v2.5.1 artefact is universal, and Intel users get a broken app | 25 | status/history | CHANGELOG.md v3.0.0 "Intel Macs are not supported" (same fact, shorter) | →open-items.md | |
| docs/open-items.md | Owed on screen from C4(c) and C7, after the 2026-09-09 drive | 15 | status/history | archive/v3/drive-2026-09-09.md (pointer) | →archive | dated to a specific closed session; mostly resolved per its own text |
| docs/open-items.md | Release-readiness review 2026-09-11 — added 2026-09-11 | 15 | status/history | - | →open-items.md | lane header + long preamble |
| docs/open-items.md | The hexagonal IPF colour key is labelled the wrong way round (2026-09-11) | 17 | status/history | CHANGELOG.md v3.0.0 Known limitations (same defect, one line) | →open-items.md | |
| docs/open-items.md | Single-slice ptychography publishes under a mode its export guard misses | 14 | status/history | CHANGELOG.md v3.0.0 Known limitations (ptychography scale-bar caveat, related) | →open-items.md | |
| docs/open-items.md | HDF5 runs under one lock now — what that costs and what is still open — fixed 2026-09-15 late night | 30 | status/history | decisions.md 2026-09-15(late night) "HDF5 is serialised by a lock" (near-duplicate) | →archive | title says "fixed"; residual (2 sentences on cost) could move to a 5-line entry |
| docs/open-items.md | The Quantitative badge consults no origin gate at all (2026-09-11) | 17 | status/history | archive/2026-09-11-drive/quantitative-badge-gate-b.md (pointer); CHANGELOG.md v3.0.0 Known limitations (same defect) | →open-items.md | |
| docs/open-items.md | A radius-only aperture drag destroys the fitted origin (2026-09-11) | 15 | status/history | - | →open-items.md | |
| docs/open-items.md | "Computed this session" reports what EXISTS, not what was computed (2026-09-11) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | Moving the detector destroys the origin fit with no durable warning (2026-09-11) | 15 | status/history | - | →open-items.md | |
| docs/open-items.md | A red real-data gate names the symptom, not the cause (2026-09-09) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | Real-data numbers are pinned by one harness only `all` reaches (2026-09-09) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | The acceptance harness pins peak COUNTS, never positions (2026-09-09) | 10 | status/history | - | →open-items.md | |
| docs/open-items.md | The one-peak warning is below the fold, and Strain unlocks without it (2026-09-09) | 23 | status/history | CHANGELOG.md v3.0.0 fixes (placement fix, same fact) | →open-items.md | placement half fixed per own text; Strain-unlock half open |
| docs/open-items.md | Bullseye disk detection accepts noise — two of three fixes landed 2026-09-05, drive owed | 13 | status/history | CHANGELOG.md v3.0.0 (flat-kernel fix, same facts) | →open-items.md | |
| docs/open-items.md | Origin-fit gate has two unresolved holes (2026-09-05) | 12 | status/history | q-calibration-design.md §1-2 (same design question, much fuller) | →open-items.md | q-calibration-design.md is the primary source; this is the summary |
| docs/open-items.md | The origin's coarse block seed lands on the wrong blob on noisy cubes (2026-09-05) | 12 | status/history | q-calibration-design.md §4 (same topic) | →open-items.md | |
| docs/open-items.md | CIF import can silently accept a wrong crystal (2026-09-01) | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | ACOM orientation/export coverage gaps (2026-08-31) | 12 | status/history | - | →open-items.md | |
| docs/open-items.md | Q-calibration scale defects on real crystals (2026-09-02) | 13 | status/history | q-calibration-design.md §8 (part (a), same fact, "closed" here too) | →open-items.md | |
| docs/open-items.md | Twisted bilayer graphene finds only the beam at defaults, at either reference (2026-09-05) | 8 | status/history | tools/disk-detector/README.md (graphene not mentioned there; no dup) | →open-items.md | |
| docs/open-items.md | #18 — training-dataset campaign can't reproduce the app's Si_SiGe strain (2026-09-02) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | No automated visual baseline (2026-08-17) | 9 | rule/invariant | CLAUDE.md on-screen-verification rule; CONTRIBUTING.md "Acceptance is evaluation only" | →open-items.md | |
| docs/open-items.md | macOS 14–25 is supported and has never been run there (2026-09-04) | 10 | status/history | CHANGELOG.md v3.0.0 Known limitations; architecture.md Requirements (macOS 14+, Xcode 26) | →open-items.md | see Table 2 "dev machine OS version" cluster |
| docs/open-items.md | Residency `.automatic` cannot be re-measured without a second machine (2026-08-19) | 6 | rule/invariant | CLAUDE.md "do NOT set measuredWorkingSetFraction"; v3-plan.md §4 "Leave alone"; pickup SKILL.md | →open-items.md | see Table 2 |
| docs/open-items.md | An emptied manual Q field, confirmed, discards the file's calibration (2026-09-07) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | C3 drive leftovers: presentation observations (2026-09-07) | 13 | status/history | decisions.md 2026-09-07 area (owner's four checks) | →archive | most items closed ("closed 2026-09-07 23:38"); 2 residual bullets remain |
| docs/open-items.md | Two diagnostic harnesses gate nothing (2026-09-02) | 4 | rule/invariant | - | →open-items.md | |
| docs/open-items.md | Learned detector above 256 px: the probe channel's anchor (Gate B, 2026-09-08) | 9 | status/history | tools/disk-detector/README.md (same anchor concept) | →open-items.md | |
| docs/open-items.md | #30 — origin calibration over a NAS runs at ~3 MB/s (2026-08-06) | 2 | status/history | - | →open-items.md | |
| docs/open-items.md | Known, scoped, not blocking | 2 | status/history | - | →open-items.md | lane header |
| docs/open-items.md | Parallax and ptychography are unrunnable on the owner's Mac (2026-09-11) | 22 | status/history | CHANGELOG.md v3.0.0 Known limitations (same numbers: 8.2/11.6 GB vs 1.07 GB) | →open-items.md | |
| docs/open-items.md | Fabricated provenance on pre-2026-08-18 sidecars (2026-09-02) | 8 | status/history | - | →open-items.md | |
| docs/open-items.md | DM4Reader silently reads the whole file into RAM off non-local volumes (2026-09-02) | 13 | status/history | dm4-format.md (no direct mention; complementary) | →open-items.md | |
| docs/open-items.md | The sidecar reader has D003's missing guard too — not fixed (2026-09-09) | 10 | status/history | - | →open-items.md | |
| docs/open-items.md | Ptychography pads both object axes unlike py4DSTEM — deliberate (2026-09-09) | 9 | rule/invariant | CLAUDE.md DEVIATION-note rule (this IS a documented DEVIATION) | →open-items.md | |
| docs/open-items.md | Scan-fastest DM4 detector pair may be transposed — Gate D owed (2026-09-05) | 12 | status/history | dm4-format.md §3.3 (same open question, fuller); CHANGELOG.md v3.0.0 (same fact) | →open-items.md | dm4-format.md is the fuller technical source |
| docs/open-items.md | The open/promote unwind is sixfold, and Cancel can vanish mid-load (2026-09-04) | 13 | status/history | - | →open-items.md | |
| docs/open-items.md | Promote/replay residuals (2026-09-02) | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | Recents/window-state edge cases, both low priority (2026-09-02) | 6 | status/history | - | →open-items.md | |
| docs/open-items.md | Legacy `.icns` tops out at 256 px — reopened 2026-09-07 (the floor is 14) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | Resident/streaming residuals (2026-09-02) | 9 | status/history | architecture.md Known limitations (streaming vs resident) | →open-items.md | |
| docs/open-items.md | Toolbar Cancel button renders wrong during a run — cosmetic, not blocking (2026-09-04) | 22 | status/history | decisions.md 2026-09-12 status-bar entry (the fix applied to the OTHER Cancel button, referenced here) | →open-items.md | |
| docs/open-items.md | Sidecar/session UX residuals (2026-09-02) | 9 | status/history | - | →open-items.md | |
| docs/open-items.md | DPC's banner contradicts its badge — entry corrected 2026-09-04 | 13 | status/history | - | →open-items.md | |
| docs/open-items.md | Misc unclaimed, low priority (2026-09-02) | 13 | status/history | - | →open-items.md | |
| docs/open-items.md | The constraint-loop crash: nothing in a split may change its own minimum (2026-09-04) | 14 | rule/invariant | architecture.md doesn't restate this; decisions.md UI2 entries reference it | keep→ARCHITECTURE.md | this is a standing SwiftUI/AppKit-split rule, not a live defect — belongs in architecture.md's Developer notes |
| docs/open-items.md | `PaneSplit` residuals from the refuter (2026-09-04) | 12 | status/history | - | →open-items.md | |
| docs/open-items.md | Manual Q and R pixel scale cannot be corrected once entered — fixed in code, drive owed (2026-09-04) | 12 | status/history | - | →open-items.md | code fix landed; only the drive-verification is open |
| docs/open-items.md | `calibration.*` identifiers exist twice while the export sheet is open (2026-09-04) | 8 | status/history | - | →open-items.md | |
| docs/open-items.md | Code hygiene | 2 | status/history | - | →open-items.md | lane header |
| docs/open-items.md | `tools/free-space.sh` still spells shared path knowledge three times (2026-09-04) | 13 | status/history | CLAUDE.md `tools/free-space.sh` build/test mention | →open-items.md | |
| docs/open-items.md | Acceptance-gate test-infrastructure residuals (2026-09-02) | 11 | status/history | - | →open-items.md | |
| docs/open-items.md | `.fixedSize()` in `UI/`, audited 2026-09-04 — one armed site, contained | 13 | rule/invariant | the constraint-loop entry above (same underlying rule) | →open-items.md | cross-references the constraint-loop entry directly |
| docs/open-items.md | Harness type replicas of `Aperture` (2026-09-02) | 10 | status/history | - | →open-items.md | |

### docs/development-process.md (238 lines, 13 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/development-process.md | (front matter) | 8 | status/history | - | →archive | |
| docs/development-process.md | What should remain | 8 | rule/invariant | CLAUDE.md Hard rules (Gate D/B, independent review) | keep→CLAUDE.md | restates Gate concepts |
| docs/development-process.md | One compact task, one evidence record | 20 | howto | - | keep→ARCHITECTURE.md | process design, largely unadopted literally (no "task record" format visible elsewhere) |
| docs/development-process.md | Complete small review batches | 27 | rule/invariant | adversarial-review SKILL.md (both copies) — overlapping Gate B discipline | keep→ARCHITECTURE.md | |
| docs/development-process.md | A threshold is not a result until it is measured on every dataset it will touch | 25 | rule/invariant | decisions.md 2026-09-16 "step 3 gets a stopping rule" (same lesson, same session) | keep→CLAUDE.md | strong standing rule, duplicated by the decisions.md entry that motivated it |
| docs/development-process.md | Separate evidence levels | 18 | rule/invariant | - | keep→ARCHITECTURE.md | |
| docs/development-process.md | Make scientific state own its interpretation | 15 | architecture | architecture.md "Ownership today and where it is going" (same target design) | keep→ARCHITECTURE.md | |
| docs/development-process.md | Shorten the visual feedback loop | 17 | rule/invariant | CLAUDE.md on-screen-verification rule | keep→CLAUDE.md | |
| docs/development-process.md | Isolate work and choose gates by evidence | 13 | rule/invariant | CLAUDE.md "Do not drive the app during the unit gate" (verbatim-ish) | keep→CLAUDE.md | |
| docs/development-process.md | Measure whether this helps | 16 | status/history | - | →archive | v3-kickoff-specific, largely dated |
| docs/development-process.md | Working methods that earned their keep | 5 | rule/invariant | - | keep→CLAUDE.md | intro to the 3 sub-lessons + numbered list below |
| docs/development-process.md | Read the gate's own exit line, never the wrapper's | 10 | rule/invariant | CLAUDE.md "Never read a gate's exit code through a pipe" (same rule, same S4/S8 example); closeout SKILL.md (both copies) | keep→CLAUDE.md | 4-way duplicate, see Table 2 |
| docs/development-process.md | Resume a lost session from its scratchpad, not from memory | 6 | howto | - | keep→ARCHITECTURE.md | |
| docs/development-process.md | Count a gate's tests by name, and reconcile against the expected delta | 47 | howto | status.md gate-table rows (same reconciliation trap, repeated dozens of times) | keep→ARCHITECTURE.md | contains the 8-item numbered checklist too (lines 205-238) |

### docs/architecture.md (308 lines, 10 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/architecture.md | (front matter) | 6 | architecture | - | keep→ARCHITECTURE.md | |
| docs/architecture.md | Layers and the dependency rule | 25 | architecture | CONTRIBUTING.md "Where code goes" (looser) | keep→ARCHITECTURE.md | canonical |
| docs/architecture.md | What it does, by subsystem | 61 | architecture | README.md "What it does" (public-facing subset) | keep→ARCHITECTURE.md | canonical, fuller |
| docs/architecture.md | Project structure and where files go | 28 | architecture | CONTRIBUTING.md "Where code goes" (near-identical table) | keep→ARCHITECTURE.md | canonical; CONTRIBUTING.md's copy is missing the Core/ML row |
| docs/architecture.md | Ownership today and where it is going | 24 | **stale** | CLAUDE.md AppState rule; decisions.md 2026-09-07 C5 entry, 2026-09-16 overrule entry | keep→ARCHITECTURE.md | **STALE**: "adapters carry an expiry condition; `AppState.swift` + `Support/ResultExport.swift` never net positive lines in a commit" — this is exactly the "hard form" of C5 that CLAUDE.md records as **overruled (owner, 2026-09-16)**. architecture.md was not updated to match. |
| docs/architecture.md | Presentation contract (2026-09-03) — SUPERSEDED | 57 | stale | decisions.md multiple 2026-09-04 UI2 entries | keep→ARCHITECTURE.md | correctly self-labelled SUPERSEDED; candidate for deletion now that "The UI contract" below has stood since 2026-09-04 |
| docs/architecture.md | The UI contract (2026-09-04) | 45 | architecture | decisions.md 2026-09-04 UI2 entries (source decisions); open-items.md constraint-loop entry (rule 3/"no AppKit shell" overlap) | keep→ARCHITECTURE.md | canonical, current |
| docs/architecture.md | Requirements, build, test | 16 | howto | CLAUDE.md Build/test; CONTRIBUTING.md Building; README.md Requirements | keep→ARCHITECTURE.md | canonical; also says "Xcode 26" — see Table 2 dev-machine-version cluster |
| docs/architecture.md | HDF5 notes | 10 | architecture | releasing.md (dlopen/embedding overlap) | keep→ARCHITECTURE.md | |
| docs/architecture.md | Known limitations | 19 | status/history | CHANGELOG.md v3.0.0 Known limitations (different list, some overlap: streaming/resident, R–Q 180° ambiguity) | →open-items.md (content) / keep→ARCHITECTURE.md (structural ones) | mixed: structural limits (no Metal fallback) stay; dated ones (bundle-id) could move |
| docs/architecture.md | Developer notes | 13 | rule/invariant | CLAUDE.md Metal-struct-byte-identity rule (verbatim) | keep→ARCHITECTURE.md | |

### docs/decisions.md (1579 lines, 97 decision entries: 71 in bold-paragraph pre-2026-09-11 format with no `##` heading, 26 in `##`-headed format from 2026-09-11 on)

See Table 3 for the full one-row-per-decision breakdown (date, title, still
load-bearing). Table 1 rows below group by markdown structure:

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/decisions.md | (front matter + 71 bold-paragraph decisions, 2026-08-17..2026-09-09, pre-heading format) | 773 | decision | many entries individually duplicated by status.md/CHANGELOG.md/architecture.md, see Table 2/3 | →ADR | one-ADR-per-decision split; 21 of these 71 are superseded/history-only per Table 3 |
| docs/decisions.md | 2026-09-11 — the accessibility crash does not block v3.0.0 (owner) | 24 | decision | CHANGELOG.md v3.0.0 Known limitations (VoiceOver); open-items.md Accessibility lane | →ADR | |
| docs/decisions.md | 2026-09-11 — the consolidation plan is archived and v3.0.0 is the next cut | 21 | decision | CLAUDE.md/AGENTS.md front matter (source of "exited 2026-09-11" claim); ROADMAP.md (stale copy) | →ADR | |
| docs/decisions.md | 2026-09-11 — clicking a pane selects it again, reversing two earlier calls | 40 | decision | status.md row (near-verbatim) | →ADR | |
| docs/decisions.md | 2026-09-11 — mac4DSTEM ships arm64 only, and the artefact proves it | 290 | decision | releasing.md Release contract (same arm64 facts); CHANGELOG.md v3.0.0; status.md v3.0.0 row | →ADR | **longest entry in the file by far** (290 lines) — should split into several ADRs (arch pin, package-test alignment, Intel breakage postmortem) |
| docs/decisions.md | 2026-09-12 — vector matching lands unvalidated, deliberately | 17 | decision | v3-vector-matching-plan.md (source plan) | →ADR | |
| docs/decisions.md | 2026-09-12 — β″ becomes a built-in structure, not an import-only CIF | 16 | decision | v3-vector-matching-plan.md "The β″ structure is no longer a blocker" | →ADR | |
| docs/decisions.md | 2026-09-12 — the matrix is stated by the user, never inferred | 10 | decision | - | →ADR | |
| docs/decisions.md | 2026-09-12 — an in-plane angle is reported modulo the projected symmetry | 11 | decision | - | →ADR | |
| docs/decisions.md | 2026-09-12 — the chance guard stays although it is inert at shipped settings | 15 | decision | open-items.md "detection at the noise floor" | →ADR | |
| docs/decisions.md | 2026-09-12 — completeness is a chance-level test, not a fraction | 12 | decision | - | →ADR | |
| docs/decisions.md | 2026-09-12 — throughput leaves the status strip, which narrows a 2026-09-04 decision | 21 | decision | open-items.md Toolbar-Cancel entry (references this) | →ADR | |
| docs/decisions.md | 2026-09-12 — a readout is not an event | 15 | decision | status.md 2026-09-12 status-bar row | →ADR | |
| docs/decisions.md | 2026-09-14 — `Crystal.reflections` deviates from py4DSTEM's tile bound, and a gate owns its own frame | 18 | decision | CLAUDE.md DEVIATION rule (this creates one) | →ADR | |
| docs/decisions.md | 2026-09-14 — Two verdicts a user reads: the matrix gets the last word, and a spotty annulus is refused rather than flagged | 32 | decision | open-items.md "matrix is a verdict by exclusion" (directly related, later refines this) | →ADR | |
| docs/decisions.md | 2026-09-14 (later) — the ellipse refusal is a degeneracy bound, on the owner's decision | 21 | decision | open-items.md "ellipse Fit anyway" entry | →ADR | |
| docs/decisions.md | 2026-09-15 — the ellipse flag sits behind a click, and "fit anyway" still refuses more than one ring | 32 | decision | open-items.md ellipse entry (near-duplicate) | →ADR | |
| docs/decisions.md | 2026-09-15 (night) — the rotation null keeps the field's structure | 21 | decision | open-items.md rotation-null entry (near-duplicate, fuller) | →ADR | open-items.md's version is more detailed; pick one home |
| docs/decisions.md | 2026-09-15 (night) — the zone-axis sweep is its own null | 16 | decision | open-items.md zone-axis entry (near-duplicate) | →ADR | |
| docs/decisions.md | 2026-09-15 (late night) — HDF5 is serialised by a lock around operations, not by an actor | 16 | decision | open-items.md HDF5-lock entry (near-duplicate, fuller) | →ADR | |
| docs/decisions.md | 2026-09-15 — the three decisions step 3 turned on, taken and measured | 43 | decision | status.md row; v3-vector-matching-plan.md §"Decisions owed" | →ADR | |
| docs/decisions.md | 2026-09-15 — the detection default stays py4DSTEM's 0.5 % | 11 | decision | open-items.md (references this decision directly, "the default stays py4DSTEM's 0.5%") | →ADR | |
| docs/decisions.md | 2026-09-15 — the orientation relationship lands inert, without a panel control | 15 | decision | superseded same day by the next entry | →archive | superseded, see Table 3 |
| docs/decisions.md | 2026-09-15 — the verdict cliff is three quarters of the pair radius, and the OR earns its control | 19 | decision | open-items.md cliff entry (near-duplicate) | →ADR | |
| docs/decisions.md | 2026-09-15 — the orientation relationship is stated as parallel vectors, and gets its control | 14 | decision | v3-vector-matching-plan.md §"Decisions owed" (same OR-form facts) | →ADR | |
| docs/decisions.md | 2026-09-16 — step 3 gets a stopping rule, set before the measurements | 25 | decision | development-process.md "A threshold is not a result..." (same lesson, same session) | →ADR | duplicate with development-process.md |
| docs/decisions.md | 2026-09-16 — three rules overruled by the owner, and the merge is split | 32 | decision | CLAUDE.md Hard rules (the three overrules are stated there directly); closeout/pickup SKILL.md drift (see Table 5) | →ADR | source of 3 of the most-duplicated facts in the whole corpus, see Table 2 |

### docs/releasing.md (197 lines, 8 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/releasing.md | (front matter) | 7 | howto | - | keep→RELEASE.md | |
| docs/releasing.md | Release contract | 30 | status/history | decisions.md 2026-09-11 arm64 entry (near-duplicate of the arm64/HDF5 facts); status.md v3.0.0 row | keep→RELEASE.md | canonical release-mechanics home; version/build numbers duplicate status.md |
| docs/releasing.md | Before using credentials | 30 | howto | CLAUDE.md/AGENTS.md Build/test (`run-tests.sh all`) | keep→RELEASE.md | |
| docs/releasing.md | Developer ID archive | 13 | howto | - | keep→RELEASE.md | |
| docs/releasing.md | Notarize and staple | 16 | howto | - | keep→RELEASE.md | |
| docs/releasing.md | The disk image users actually download | 24 | howto | - | keep→RELEASE.md | |
| docs/releasing.md | Distribution and notarization | 20 | howto | - | keep→RELEASE.md | marked "merged from distribution.md, 2026-09-02" — already once-consolidated |
| docs/releasing.md | Credentialed release | 26 | howto | - | keep→RELEASE.md | |
| docs/releasing.md | Sandboxed file access | 7 | architecture | architecture.md (sandbox/bookmarks not detailed there) | keep→RELEASE.md | |

### docs/dm4-format.md (331 lines, 19 sections — reference spec)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/dm4-format.md | (all sections: file structure, type tables, locating the datacube, parsing algorithm, Swift notes) | 331 | architecture | open-items.md "Scan-fastest DM4 detector pair may be transposed" (the one open question overlaps §3.3); CHANGELOG.md v3.0.0 (DM4 axis-role fix, same facts) | keep→ARCHITECTURE.md | "appendix/reference" per guidance — a byte-format spec, one coherent unit; do not split by heading |

### docs/q-calibration-design.md (634 lines, 14 sections — design note)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/q-calibration-design.md | (front matter) | 33 | status/history | cites `docs/v2-release.md` §8 twice — **BROKEN CITATION**, see Broken citations table | keep→ARCHITECTURE.md | |
| docs/q-calibration-design.md | 1. #29 answered | 61 | status/history | open-items.md "Origin-fit gate has two unresolved holes" (summarizes this) | keep→ARCHITECTURE.md | appendix/reference; the fuller, primary source |
| docs/q-calibration-design.md | 1.1 The three fit functions on the same measured maps | 49 | status/history | - | keep→ARCHITECTURE.md | |
| docs/q-calibration-design.md | 1.2 The distribution — where #29's binary breaks down | 56 | status/history | - | keep→ARCHITECTURE.md | |
| docs/q-calibration-design.md | 1.3 The answer | 17 | decision | - | →ADR | reads like a decision record embedded in a design doc |
| docs/q-calibration-design.md | 2. The split | 44 | architecture | Session/SessionGates.swift ownership (architecture.md doesn't mention SessionGates by name) | keep→ARCHITECTURE.md | |
| docs/q-calibration-design.md | 3. The estimator-internal plausibility gate | 54 | status/history | - | keep→ARCHITECTURE.md | |
| docs/q-calibration-design.md | 3.1 Shell consistency | 47 | status/history | - | keep→ARCHITECTURE.md | contains a REFUTED-IN-PART correction inline — good practice, not stale |
| docs/q-calibration-design.md | 3.2 Shell-ratio self-check | 50 | status/history | CHANGELOG.md v3.0.0 "Q calibration from a known crystal averages..." (same fix, shorter) | keep→ARCHITECTURE.md | |
| docs/q-calibration-design.md | 4. The `measureOrigin` coarse step — OUT of S13 | 79 | decision | open-items.md "origin's coarse block seed" (related but distinct topic) | →ADR | a full recommendation-and-rejection record; belongs as an ADR |
| docs/q-calibration-design.md | 5. What S13 should build, in order | 33 | status/history | - | →archive | S13 is long complete; pure history |
| docs/q-calibration-design.md | 6. Owner decisions | 51 | decision | - | →ADR | two dated owner decisions embedded in prose |
| docs/q-calibration-design.md | 7. What S12 did not verify | 34 | status/history | - | →archive | |
| docs/q-calibration-design.md | 8. Gate D, 2026-09-05 — the per-pattern minimum radius | 47 | status/history | CHANGELOG.md v3.0.0 "Q calibration...averages the innermost shell's equivalents" (same fix) | →archive | dated Gate D record, fully closed |
| docs/q-calibration-design.md | 9. Gate D, 2026-09-05 — the origin measurement sat 0.26 px off the beam | 66 | status/history | CHANGELOG.md v3.0.0 "The diffraction origin is measured where the beam is" (same fix); status.md origin-measurement row | →archive | dated Gate D record, fully closed |

### docs/py4dstem-pipelines.md (352 lines, 20 sections — reference)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/py4dstem-pipelines.md | 0. The shared front-end through 6. Dataset↔pipeline map | ~190 | architecture | - | keep→ARCHITECTURE.md | "appendix/reference" per guidance; pure py4DSTEM-workflow documentation, unique content |
| docs/py4dstem-pipelines.md | 7. UI observations & gaps | 61 | status/history | - | →archive | dated 2026-07/08 hypotheses; explicitly says "not yet verified claims" |
| docs/py4dstem-pipelines.md | 8. How this feeds the app | 74 | status/history | - | →archive | superseded by the retirement note in §8.4 point 4 (QC playthrough retired 2026-08-17) |
| docs/py4dstem-pipelines.md | 9–10. QC-run findings (archived) | 7 | status/history | - | →archive | pointer only, already says "archived" |
| docs/py4dstem-pipelines.md | Appendix: source notebooks consulted | 8 | architecture | - | keep→ARCHITECTURE.md | |

### docs/ai-ml/README.md (284 lines, 11 sections — brief)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/ai-ml/README.md | 1. Where this brief fits | 17 | architecture | CLAUDE.md "Read, in order" (parallel doc map for the ai-ml subtree) | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 2. What last night established | 25 | status/history | decisions.md 2026-09-06/07 entries (same review) | →archive | dated review, fully historical |
| docs/ai-ml/README.md | 3. Product direction and placement | 33 | decision | decisions.md 2026-09-11 "AI work gets a sixth workspace" (this brief's proposal, later approved) | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 4. Priority feature: precipitate segmentation | 55 | architecture | docs/ai-ml/precipitates.md (fuller spec); v3-precipitate-classification.md (supersedes the route described here) | keep→ARCHITECTURE.md | broken image citation, see Broken citations table |
| docs/ai-ml/README.md | 5. Thickness and the path to number density | 25 | architecture | v3-precipitate-classification.md §5 (references this section directly) | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 6. Diffraction clustering, similarity and discovery | 14 | architecture | v3-phase-mapping-method-choice.md (NMF/DiffractionEmbedding overlap) | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 7. Further opportunities discussed | 18 | architecture | - | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 8. Repository and documentation structure | 26 | architecture | architecture.md "Project structure and where files go" (parallel table for AI files) | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 9. Recommended development sequence and gates | 24 | rule/invariant | CLAUDE.md Gate D/B rules (restated for AI features) | keep→ARCHITECTURE.md | |
| docs/ai-ml/README.md | 10. Open design decisions and Git workflow | 13 | decision | CLAUDE.md commit-freely rule (this predates the 2026-09-16 change, says "commit/push only when asked" — **STALE** relative to current CLAUDE.md) | →ADR | **STALE**: "Follow the existing branch/integration rules, linear main, and commit/push only when asked" — superseded by the 2026-09-16 "Commit freely" rule |
| docs/ai-ml/README.md | 11. Literature and platform references discussed | 14 | architecture | - | keep→ARCHITECTURE.md | |

### docs/ai-ml/precipitates.md (167 lines, 9 sections — feature spec)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/ai-ml/precipitates.md | (front matter/status line) | 7 | status/history | v3-precipitate-classification.md line 1-7 (this whole spec is superseded) | →archive | **STALE, self-admitted only in the SUPERSEDING doc, not here**: v3-precipitate-classification.md says this route ("per-object, real-space segmentation") was "Superseded 2026-09-11", but precipitates.md itself carries no superseded banner |
| docs/ai-ml/precipitates.md | 1. User outcome / non-goals | 12 | architecture | v3-precipitate-classification.md §1 (contradicts: that doc says the whole route is wrong) | →archive | |
| docs/ai-ml/precipitates.md | 2. The workflow that survives new samples | 37 | architecture | v3-precipitate-classification.md §1 ("three failures this session, all downstream of that one choice" — directly rebuts this workflow) | →archive | describes the now-rejected real-space segmentation route |
| docs/ai-ml/precipitates.md | 3. Proposed screens | 19 | architecture | docs/ai-ml/README.md §3 (workspace placement, consistent) | →archive | |
| docs/ai-ml/precipitates.md | 4. Owner of state / data model | 29 | architecture | v3-precipitate-classification.md §3 ("It does not exist on `main`" — same file cited as branch-only) | →archive | cites `Session/PrecipitateProduct.swift` as if designed/current; branch-only, see Broken citations |
| docs/ai-ml/precipitates.md | 5. Input/output and unit contracts | 10 | architecture | - | →archive | |
| docs/ai-ml/precipitates.md | 6. Validation and acceptance, pre-registered | 15 | decision | v3-precipitate-classification.md §4 (different, superseding acceptance criteria) | →archive | pre-registration for the superseded route |
| docs/ai-ml/precipitates.md | 7. Runtime budget | 6 | architecture | - | →archive | |
| docs/ai-ml/precipitates.md | 8. Unresolved decisions for the owner | 7 | decision | - | →archive | moot if route is superseded |
| docs/ai-ml/precipitates.md | 9. Links to evidence | 17 | architecture | broken image citation (shared with ai-ml/README.md), see Broken citations table | →archive | |

### docs/v3-phase-mapping-method-choice.md (101 lines, 6 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/v3-phase-mapping-method-choice.md | (front matter) | 5 | decision | - | →ADR | |
| docs/v3-phase-mapping-method-choice.md | First, a correction to how this repo reported their result | 13 | status/history | archive/v3/sped-phase-mapping-reference-2026-09-11.md (pointer) | →archive | self-corrects an earlier error, now historical |
| docs/v3-phase-mapping-method-choice.md | Recommendation: vector matching | 20 | decision | v3-vector-matching-plan.md (the plan this recommendation produced) | →ADR | |
| docs/v3-phase-mapping-method-choice.md | The deviation worth making | 21 | decision | - | →ADR | |
| docs/v3-phase-mapping-method-choice.md | Why not the others, for us specifically | 24 | decision | v3-precipitate-classification.md §5 item 2 (template-matching-fails-per-position finding, related but distinct) | →ADR | |
| docs/v3-phase-mapping-method-choice.md | The shape this suggests | 8 | decision | v3-vector-matching-plan.md (implements this shape) | →ADR | |
| docs/v3-phase-mapping-method-choice.md | What is still blocking step 2, unchanged by this evaluation | 10 | status/history | v3-vector-matching-plan.md "Decisions owed by the owner" 1-2 (both resolved 2026-09-11, this doc not updated) | →open-items.md | **partially STALE**: `.identity`/β″-CIF blockers are marked resolved in v3-vector-matching-plan.md but this doc still lists them as "still blocking" |

### docs/v3-precipitate-classification.md (270 lines, 6 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/v3-precipitate-classification.md | (front matter) | 8 | decision | v3-plan.md §3 (marks that doc's route "Superseded 2026-09-11") | →ADR | |
| docs/v3-precipitate-classification.md | 1. Why the existing route is wrong, measured not argued | 25 | status/history | docs/ai-ml/precipitates.md (the route being refuted, in full) | →archive | |
| docs/v3-precipitate-classification.md | 2. What is built | 49 | architecture | docs/ai-ml/README.md §4/§5 (thickness/density chain overlap) | keep→ARCHITECTURE.md | |
| docs/v3-precipitate-classification.md | 3. What it touches, and who owns the state | 14 | architecture | - | keep→ARCHITECTURE.md | |
| docs/v3-precipitate-classification.md | 4. The tests, written before the code | 50 | status/history | - | →open-items.md | contains a self-correction (parity harness narrower than first claimed) — live/current |
| docs/v3-precipitate-classification.md | 5. Decisions owed to the owner | 117 | decision | decisions.md 2026-09-11 entries (PCA-stays, template-matched, ridge-filter-parked — all restated here at greater length) | →ADR | **longest section in this file**; heavily duplicates 4 separate decisions.md entries, should be trimmed to a pointer once split into ADRs |
| docs/v3-precipitate-classification.md | 6. What this does not claim | 7 | decision | - | →ADR | |

### docs/v3-vector-matching-plan.md (221 lines, 11 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| docs/v3-vector-matching-plan.md | (front matter, incl. 2026-09-15 status callout) | 16 | status/history | status.md Handoff (same 4.21%/98.26%/etc. sequence) | →open-items.md | live status embedded in a plan doc |
| docs/v3-vector-matching-plan.md | What we take, and what we may not | 14 | rule/invariant | - | keep→ARCHITECTURE.md | licensing/attribution rule, unique |
| docs/v3-vector-matching-plan.md | The single biggest thing we gain | 13 | architecture | - | keep→ARCHITECTURE.md | |
| docs/v3-vector-matching-plan.md | The build order (0-5, with per-step status) | 129 | status/history | decisions.md 2026-09-12 entries (steps 0-2, 5); open-items.md step-3 entry (step 3, near-duplicate); decisions.md 2026-09-15 entries (step 4 decisions) | →open-items.md / →ADR (mixed) | the single most cross-referenced section in the corpus — step 3's numbers (26.4%→13.24%→8.75%→7.96%→6.64%) repeated in open-items.md, status.md, and here |
| docs/v3-vector-matching-plan.md | What we inherit that is not good | 9 | architecture | - | keep→ARCHITECTURE.md | |
| docs/v3-vector-matching-plan.md | Decisions owed by the owner | 22 | decision | decisions.md 2026-09-11/15 entries (items 1-2 resolved and say so; items 3-4 near-duplicate open-items.md step-3 content) | →ADR | items 1-3 are resolved-and-say-so (good hygiene); item 4 duplicates open-items.md's step-3 entry closely |

### tools/acom-convention-test/README.md (69 lines, 3 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| tools/acom-convention-test/README.md | (front matter) | 12 | howto | CLAUDE.md Build/test (`scientific` lane mention) | keep→ARCHITECTURE.md | |
| tools/acom-convention-test/README.md | Independent truth and limitations | 25 | architecture | - | keep→ARCHITECTURE.md | |
| tools/acom-convention-test/README.md | Frozen-reference provenance | 13 | howto | - | keep→ARCHITECTURE.md | |
| tools/acom-convention-test/README.md | Break before trusting | 19 | rule/invariant | adversarial-review SKILL.md (Gate B mutation-testing discipline, same pattern) | keep→ARCHITECTURE.md | |

### tools/disk-correlation-parity/README.md (180 lines, 10 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| tools/disk-correlation-parity/README.md | (front matter + What it guards) | 26 | architecture | CLAUDE.md Build/test (`scientific` lane) | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | Measured cost (Apple M3...) | 11 | status/history | tools/performance-baseline/README.md (related, non-gating benchmark) | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | The 250-px case (FFT speedup session, 2026-09-01) | 55 | status/history | ROADMAP.md "Speed" bullet (14 min → 15 s, same fact); CHANGELOG.md v2.5.0 "Speed" (same fact) | keep→ARCHITECTURE.md | the 14min→15s FFT speedup number appears in 3 files |
| tools/disk-correlation-parity/README.md | What is pinned | 17 | architecture | - | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | Input | 10 | howto | - | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | Finding: a Metal disk-correlation backend was built, measured, and removed | 17 | decision | - | →ADR | a full decision record: built, measured, rejected |
| tools/disk-correlation-parity/README.md | The trap | 13 | rule/invariant | tools/disk-detector/README.md "scan-bench" section (same "benchmark against the real parallel opponent" lesson) | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | Why the GPU loses here | 15 | architecture | - | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | The bigger reason it was not worth it | 11 | architecture | - | keep→ARCHITECTURE.md | |
| tools/disk-correlation-parity/README.md | Also note | 5 | architecture | - | keep→ARCHITECTURE.md | |

### tools/disk-detector/README.md (337 lines, 10 sections)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| tools/disk-detector/README.md | (front matter) | 13 | architecture | v3-plan.md §3a (pre-registration this tool implements) | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Environments (two, on purpose) | 10 | howto | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Conventions | 12 | architecture | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Modes | 12 | howto | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Model size (C7, 2026-09-07) | 32 | status/history | decisions.md 2026-09-07/08 entries (same 256-px decision) | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | (unlabelled overnight-chain code block) | 5 | howto | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | The fixture (`fixture/`) | 22 | architecture | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Step 2 — the net, the exports, the checks | 137 | status/history | v3-plan.md §3a "Step 3 — evidence" (cross-referenced, overlapping numbers); CHANGELOG.md v3.0.0 ML section (recall/precision numbers repeated) | →archive | long dated experiment log; historical once C7 shipped |
| tools/disk-detector/README.md | 2026-09-07 revisions | 45 | status/history | v3-plan.md §3a (the C7 ceiling numbers, 1.44-1.64×, repeated in both) | →archive | dated, historical |
| tools/disk-detector/README.md | Retraining — when and how | 12 | howto | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Recipe | 16 | howto | - | keep→ARCHITECTURE.md | |
| tools/disk-detector/README.md | Before a new asset ships | 8 | rule/invariant | - | keep→ARCHITECTURE.md | |

### tools/performance-baseline/README.md (15 lines, 1 section — no headings below title)

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| tools/performance-baseline/README.md | (whole file, no `##`/`###` headings) | 15 | howto | CLAUDE.md Build/test (`benchmark` lane); tools/disk-correlation-parity/README.md (related non-gating measurement philosophy) | keep→ARCHITECTURE.md | |

### Skill files — `.claude/skills/*/SKILL.md` and `.agents/skills/*/SKILL.md` (4 skills × 2 copies = 8 files)

Diff results are in Table 5. Table 1 rows below are for the `.claude/` copies (canonical, more current per Table 5); the `.agents/` copies are flagged as stale duplicates and not separately rowed except where content differs.

| path | section | lines | class | duplicate-of | verdict | note |
|---|---|---|---|---|---|---|
| .claude/skills/adversarial-review/SKILL.md | (whole file, one `#` heading + numbered list, no `##`) | 79 | rule/invariant | CLAUDE.md Gate B mention; CONTRIBUTING.md "A change to Core/..."; development-process.md "Complete small review batches" | keep→CLAUDE.md (procedure) | identical to `.agents/` copy (Table 5); Gate B procedure, references many dated incidents (2026-08-19, 2026-08-28, 2026-08-31, 2026-09-01) that are also decisions.md/open-items.md material |
| .claude/skills/closeout/SKILL.md | (whole file, one `#` heading + numbered list) | 75 | rule/invariant | CLAUDE.md Hard rules (commit-freely, docs-part-of-done, AGENTS.md-sync — all restated here); MEMORY.md "v2 status board artifact" (external, the board-URL rule matches this file's step 7) | keep→CLAUDE.md (procedure) | **current**, matches the 2026-09-16 rule set; `.agents/` copy is stale, see Table 5 |
| .claude/skills/diagnose/SKILL.md | (whole file) | 68 | rule/invariant | CLAUDE.md Gate D rule (fuller procedure here); pickup SKILL.md (references `/diagnose`) | keep→CLAUDE.md (procedure) | identical to `.agents/` copy (Table 5) |
| .claude/skills/pickup/SKILL.md | (whole file) | 46 | rule/invariant | CLAUDE.md front matter ("`/pickup` takes the next step..."); status.md Handoff (this skill reads it) | keep→CLAUDE.md (procedure) | **current**; line 46 still says "Commit only if asked; never push" — **contradicts CLAUDE.md's 2026-09-16 "Commit freely" rule directly, in the CURRENT (non-stale) copy** — see Table 2 |

## Table 2 — Facts stated in more than one place

Exhaustive within what was read. Ordered roughly by fan-out (most-duplicated
first).

| fact | places | count |
|---|---|---|
| Current version is v2.5.1, v3.0.0 "prepared and not yet cut" | CLAUDE.md#front-matter, AGENTS.md#front-matter, ROADMAP.md#Phase-status | 3 (**all 3 are STALE** — v3.0.0 shipped 2026-09-11 per status.md/CHANGELOG.md/README.md) |
| v3.0.0 released 2026-09-11 (correct current fact) | status.md#Releases, CHANGELOG.md#v3.0.0, README.md#New-in-v3.0.0, releasing.md#Release-contract, decisions.md 2026-09-11 arm64 entry, decisions.md 2026-09-11 "consolidation plan is archived" entry | 6 |
| "Commit freely" / pushing is the owner's (2026-09-16 rule) | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, decisions.md 2026-09-16 "three rules overruled", .claude/skills/closeout/SKILL.md step 9 | 4 (**contradicted by** .agents/skills/closeout/SKILL.md step 9 "do not commit unless asked" [stale copy], AND by BOTH .claude/skills/pickup/SKILL.md and .agents/skills/pickup/SKILL.md step 5 "Commit only if asked; never push" [current copy too — not just the stale one]) |
| Gate D trigger: "moves a scientific number, or cause not yet established" | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, decisions.md 2026-09-04 "Gate D's trigger is sharpened", decisions.md 2026-08-18 "v2 contract and three gates" (earlier form), development-process.md#What-should-remain, .claude+.agents/skills/diagnose/SKILL.md (both), .claude+.agents/skills/pickup/SKILL.md (both, "Non-negotiables"), CONTRIBUTING.md#The-rules-that-actually-matter | 9 |
| "What does NOT need Gate D" (placement/presentation/renames/docs/tooling/reproducing-mechanism) | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, decisions.md 2026-09-04 entry (source) | 3 |
| Never read a gate's exit code through a pipe (the S4/S8 `\| tail` trap) | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, development-process.md#Read-the-gates-own-exit-line, .claude+.agents/skills/closeout/SKILL.md step 1 (both) | 5 |
| "A log name is a name, not a path" / evidence must be committed under docs/archive/ | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, status.md#front-matter (fullest/original statement) | 3 |
| `AppState` is the single source of truth; views describe UI only; Core/ holds compute | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, CONTRIBUTING.md#The-rules-that-actually-matter, architecture.md#Layers-and-the-dependency-rule, architecture.md#Ownership-today, ROADMAP.md#Priority-3, decisions.md 2026-08-17 "AppState seam rule" | 7 |
| New stored state in `AppState` names its owner first; no forwarding properties | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, docs/ai-ml/precipitates.md §4, docs/v3-precipitate-classification.md §3, docs/ai-ml/README.md §8 | 5 |
| C5's hard "never net positive lines" rule for AppState.swift+ResultExport.swift | decisions.md 2026-09-07 "C5: the rule is a number", architecture.md#Ownership-today-and-where-it-is-going (**STILL states the hard form, not updated**) | 2 (**contradiction**: CLAUDE.md/AGENTS.md/decisions.md 2026-09-16 say this is overruled — reports delta, no longer fails; architecture.md was never updated) |
| C5 hard form overruled 2026-09-16 (inventory reports delta, does not fail) | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, decisions.md 2026-09-16 "three rules overruled" | 3 |
| Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, .claude+.agents/skills/pickup/SKILL.md "Non-negotiables" (both), open-items.md "Residency `.automatic`...", v3-plan.md §4 "Leave alone" | 6 |
| Metal parameter structs stay byte-identical to `.metal` structs (4-byte fields) | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, architecture.md#Developer-notes, CONTRIBUTING.md#The-rules-that-actually-matter | 4 |
| DEVIATION note required for py4DSTEM port deviations | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, CONTRIBUTING.md#The-rules-that-actually-matter, .claude+.agents/skills/adversarial-review/SKILL.md (both, point 4) | 5 |
| Never `CODE_SIGNING_ALLOWED=NO` on a build you intend to launch | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, architecture.md#Requirements-build-test | 3 |
| On-screen verification: assistant may claim it when it drove and is sure; otherwise state "unverified on screen" | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, decisions.md 2026-09-16 (source), CONTRIBUTING.md#The-rules-that-actually-matter ("owner driving the app", older framing), development-process.md#Shorten-the-visual-feedback-loop | 5 |
| Docs are part of done; update status.md + open-items.md same commit; AGENTS.md generated by sync script | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, .claude+.agents/skills/closeout/SKILL.md step 5 (both) | 4 |
| Never widen a gate that fails silently | CLAUDE.md (implicit via "no claim a reader cannot reproduce"), CONTRIBUTING.md#The-rules-that-actually-matter, development-process.md#Working-methods item 3, ROADMAP.md#Scope-rule (refusal rule) | 4 |
| "A test written for your own fix proves nothing until it has failed without the fix" / break every new test first | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, CONTRIBUTING.md#The-rules-that-actually-matter, development-process.md#Working-methods item 8, .claude+.agents/skills/pickup/SKILL.md "Non-negotiables" (both) | 6 |
| An independent refuter reviews Gate B changes; the model that wrote the change never approves it alone | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, CONTRIBUTING.md#The-rules-that-actually-matter, .claude+.agents/skills/adversarial-review/SKILL.md (both), .claude+.agents/skills/pickup/SKILL.md "Non-negotiables" (both), development-process.md#What-should-remain | 8 |
| Build/test commands (`xcodebuild ... build`; `run-tests.sh unit\|scientific\|all\|inventory\|core\|benchmark\|campaign`; `tools/free-space.sh`) | CLAUDE.md#Build-test, AGENTS.md#Build-test, architecture.md#Requirements-build-test (all 7 lanes), CONTRIBUTING.md#Building (**only 3 of 7 lanes**, stale/thin), README.md#Building (build only) | 5 |
| Development/build machine runs macOS 26 / Xcode 26 | CONTRIBUTING.md#Building, architecture.md#Requirements-build-test, CHANGELOG.md v3.0.0 Known-limitations ("Every machine here runs 26") | 3 (**contradicted**: open-items.md "GitHub CI's unit job..." 2026-09-14 states the owner's local machine runs Xcode 27.0, and the live session environment for this very audit is `Darwin 27.0.0` — none of the 3 citing docs have been updated) |
| py4DSTEM pinned commit fetched via `tools/lib/fetch-py4dstem.sh` into gitignored `References/` | CLAUDE.md#front-matter, AGENTS.md#front-matter, CONTRIBUTING.md#Building, architecture.md#Project-structure | 4 |
| The consolidation plan exited/closed 2026-09-11, gates C0–C8 | CLAUDE.md#front-matter, AGENTS.md#front-matter, ROADMAP.md#Phase-status (stale copy), .claude+.agents/skills/pickup/SKILL.md (both), decisions.md 2026-09-11 "consolidation plan is archived" entry | 6 |
| A v3 feature is no longer refused; pre-registered per v3-plan.md §6 | CLAUDE.md#front-matter, AGENTS.md#front-matter, .claude+.agents/skills/pickup/SKILL.md (both) | 4 |
| Learned disk detector: recall/precision 0.768/0.712 at 0.7, 0.667/0.840 at 0.9, vs classical 0.487/0.485; speed 1.44–1.64× | README.md#New-in-v3.0.0, CHANGELOG.md#v3.0.0, v3-plan.md §3a "Verdict (step 3)", status.md (C6/C7 rows), tools/disk-detector/README.md | 5 |
| FFT speedup: Detect All Disks on 250-px cube, 14 min → under 15 s | README.md (implicit "an exact Bluestein FFT for any detector size"), CHANGELOG.md v2.5.0 "Speed", ROADMAP.md (not directly, via `docs/s22-ux-design.md` pointer — external), tools/disk-correlation-parity/README.md | 3 |
| The demo cube / demo dataset as the standard fixture | status.md (many rows), open-items.md (many rows), decisions.md (many entries), v3-vector-matching-plan.md §3, docs/ai-ml/precipitates.md | 5+ (consistent usage, not contradictory — noted per the task's own example) |
| `run-tests.sh all` exit 0, 458/0/0, 44 harnesses (v2.5.1 gate) | README.md#Verification, CHANGELOG.md#v2.5.1 "Verified by", status.md#Releases | 3 |
| DMG SHA-256 for v2.5.1 (`302822...31af`) | README.md#Verification, CHANGELOG.md#v2.5.1, status.md#Releases | 3 |
| "Push is the owner's; the owner pushes" | CLAUDE.md#Hard-rules, AGENTS.md#Hard-rules, .claude/skills/closeout/SKILL.md step 9, .claude+.agents/skills/pickup/SKILL.md (both, "never push"), decisions.md 2026-09-07 "Consolidate before any new feature; the owner pushes" | 6 |
| The v2 status board artifact — find by title, never hardcode the URL (it changed 2026-09-15) | .claude/skills/closeout/SKILL.md step 7 (correct) | 1 in-scope-correct, **contradicted by** .agents/skills/closeout/SKILL.md step 7 which hardcodes the exact URL this rule warns against |
| AppState line-count metric (7509/7515/7400/etc.) tracked per session | status.md (dozens of rows), decisions.md (C5-related entries), architecture.md#Ownership | many (expected churn, not a contradiction — a genuinely time-varying number, correctly re-dated each time) |
| Precipitate density route: real-space image segmentation vs full-pattern classification | docs/ai-ml/precipitates.md (describes the now-superseded route without a superseded banner), docs/ai-ml/README.md §4 (describes the superseded route with a "Superseded 2026-09-11" note), v3-plan.md §3 (also self-flags "Superseded 2026-09-11"), v3-precipitate-classification.md (the superseding route), decisions.md 2026-09-11 "precipitate density is measured by CLASSIFYING" | 5 (**inconsistent self-flagging**: v3-plan.md and ai-ml/README.md mark the supersession inline; docs/ai-ml/precipitates.md, the fullest spec of the old route, does not) |
| Template matching per-position phase ID fails (mixing flip at f=0.60, gold scores above aluminium on an Al-only pattern) | v3-precipitate-classification.md §5 item 2, decisions.md 2026-09-11 "class identification should be TEMPLATE-MATCHED" (the refuted/superseded framing) and "...TEMPLATE-MATCHED and MATERIAL-GENERAL" (the corrected framing) | 3 |
| β″ structure: C2/m, a=15.16 b=4.05 c=6.74 Å, β=105.3° (Andersen et al. 1998) | v3-vector-matching-plan.md §4, decisions.md 2026-09-12 "β″ becomes a built-in structure" | 2 |
| Step 3 (Thronsen validation) mislabelled-fraction sequence: 98.26 → 26.4 → 13.24 → 8.75 → 7.96 → 6.64 → 4.21 % | status.md#Handoff, open-items.md (step-3 entries, twice), v3-vector-matching-plan.md §"Build order" step 3, decisions.md (several 2026-09-15/16 entries) | 5 |
| `notIndexedAboveInvAngstrom`/pair-radius "cliff" moved to 0.75× pair radius | status.md, open-items.md (two entries), decisions.md 2026-09-15 "verdict cliff" entry | 4 |
| Xcode/build trap: `-only-testing` with a filename (not a class) runs nothing and exits 0 | status.md (C7 session-2 row), open-items.md "A stale DerivedData test bundle..." | 2 |
| Reconcile test counts by method-name suffix, never by anchored `Test case '` prefix (glued-timestamp trap) | status.md#Last-gates (many rows), development-process.md#Count-a-gates-tests-by-name | many (status.md restates this reconciliation methodology in nearly every gate-table row) |
| Xcode DerivedData staleness silently hides a new test / fakes a surviving mutation | development-process.md#Working-methods ("Break every new test..."), open-items.md "A stale DerivedData test bundle fakes both a pass..." | 2 |

## Table 3 — ADR candidates from docs/decisions.md

97 decision entries total: 71 in the pre-2026-09-11 bold-paragraph format (no
`##` heading), 26 in the `##`-headed format from 2026-09-11 onward. **21 of
97 (≈22%) are superseded by a later entry in the same file** or are
history-only (narrow one-off implementation choices now just shipped code),
per the assessment below.

| date | title (≤10 words) | section anchor | still load-bearing? |
|---|---|---|---|
| 2026-08-17 | The `AppState` seam rule | L10 | y — governs Core/ layering |
| 2026-08-18 | The v2 contract and the three gates | L15 | y — Gate A/B/D still current |
| 2026-08-31 | W4a merged | L21 | y — history but uncontested |
| 2026-09-01 | v2 endgame scope | L23 | y — token conservation directive still cited |
| 2026-09-02 | Naming (v2.0/v2.5/v3 semver policy) | L29 | y — governs version numbering |
| 2026-09-02 | Tag before ship (v2.0.0 tag) | L34 | n — v2.0.0 superseded, never built |
| 2026-09-02 | Consolidation order and scale | L40 | y — governs package-split order |
| 2026-09-02 | Gate ceremony (Gate D/B/A, Track B) | L46 | y — partly, Track B redefined 2026-09-16 |
| 2026-09-02 | The inventory is the review | L52 | y — governs `run-tests.sh inventory` |
| 2026-09-02 | Step 2 build guard first (`DSTEMCore`) | L57 | y — shipped, still the shape |
| 2026-09-03 | `package` access at the Core boundary | L64 | y — governs Package.swift access level |
| 2026-09-03 | py4DSTEM lock fetched, not vendored | L73 | y — governs References/ policy |
| 2026-09-03 | Step 7c decisions (plan §11g) | L82 | y — governs Phase workspace shape |
| 2026-09-03 | A system-only presentation | L97 | y — governs no-custom-chrome rule |
| 2026-09-03 | The columns are AppKit's | L106 | n — AppKit shell deleted 2026-09-04 |
| 2026-09-03 | One split-view contract, like Xcode | L117 | n — AppKit split view retired 2026-09-04 |
| 2026-09-03 | Four lanes and a number rule | L128 | y — governs open-items.md's 4 lanes |
| 2026-09-03 | Steps 2c–4 decisions (unattended) | L136 | n — dated session decisions, implemented |
| 2026-09-03 | Step 2a decisions (unattended) | L148 | n — dated session decisions, implemented |
| 2026-09-03 | Presentation pass = complete UI rework | L164 | n — history, rework long finished |
| 2026-09-03 | Presentation contract rule 3 held by grep | L170 | y — governs the `inventory` grep gate |
| 2026-09-03 | v2.5.0 next release; Track B retired | L178 | n — Track B redefined 2026-09-16 |
| 2026-09-04 | `UI2` type prefix dropped | L189 | n — renaming only, historical |
| 2026-09-04 | `UI/` retired; SwiftUI rebuild IS the UI | L204 | y — governs current UI/ shape |
| 2026-09-04 | Toolbar/sidebar own the run action & trust | L224 | y — governs toolbar/sidebar UI rule |
| 2026-09-04 | UI2's shape: nav left, science centre, controls right | L242 | y — governs current 3-column layout |
| 2026-09-04 | UI2 may not use `HSplitView` | L258 | y — governs SwiftUI-only rule |
| 2026-09-04 | Status-bar ticking number gets a reserved slot | L274 | n — superseded by 2026-09-12 status-bar redesign |
| 2026-09-04 | macOS floor down to 14, claim stays 26 | L283 | y — governs deployment target |
| 2026-09-04 | Gate D's trigger is sharpened | L306 | y — the current trigger wording's source |
| 2026-09-04 | A file's labels decide datacube-ness | L317 | y — governs discovery/refusal rule |
| 2026-09-05 | Nothing measurable is a refusal, not a default | L341 | y — governs probeSize refusal |
| 2026-09-05 | DM4 calibration domains decide scan axis | L353 | y — governs DM4Reader axis logic |
| 2026-09-03 | The run functions stay on `AppState` (7c 4b) | L371 | y — governs `AnalysisRunner` deferral |
| 2026-09-02 | Results is three columns (7c slice 1) | L381 | y — governs Results workspace shape |
| 2026-09-02 | Live doc set (CLAUDE.md/status/open-items/...) | L388 | y — this is CLAUDE.md's "Read in order" source |
| 2026-09-06 | Learned disk detector is Neural-Engine-native | L397 | y — governs the shipped detector's design |
| 2026-09-07 | Learned detector ships on Core ML; Core AI insurance | L430 | y — governs current ML runtime choice |
| 2026-09-07 | Consolidate before any new feature; owner pushes | L443 | n — consolidation plan closed 2026-09-11 |
| 2026-09-07 | C0 of the consolidation plan closed | L450 | n — history, plan archived |
| 2026-09-07 | C1: docs made true, 3 facts recorded | L465 | n — history, plan archived |
| 2026-09-07 | C2 (hygiene): sources.manifest choices | L481 | n — history, plan archived |
| 2026-09-07 | C5: the AppState rule is a number | L495 | n — hard form overruled 2026-09-16 |
| 2026-09-07 | C6, Python side: "one truth rule" | L506 | n — history, C7 shipped over it |
| 2026-09-07 night | C3 delegated | L528 | y — session-delegation precedent, still cited |
| 2026-09-07 night | C4(a): one enable logic, named | L535 | y — governs `ProductWorkflow.mayRun` |
| 2026-09-07 23:45 | C6's size session, design as briefed | L548 | y — governs crash-safe design pattern |
| 2026-09-08 | C6 verdict: detector earns its place, 256px, 0.7 | L559 | y — governs shipped default 0.7 |
| 2026-09-08 | C7 session 1: Core ML runtime on main | L586 | n — history, implementation detail |
| 2026-09-08 | C7 session 2: picker in Disk detection | L609 | n — history, implementation detail |
| 2026-09-08 | C7 session 3: disagreement map, Core ML ceiling | L631 | n — history, implementation detail |
| 2026-09-08 | Labels in sidecar: centres, one attribute | L661 | y — governs `DiskCentreLabelStore` schema |
| 2026-09-08 | C7 session 4: centre labels, six choices | L675 | n — history, implementation detail |
| 2026-09-08 | C7 Gate B campaign (sessions 1-4) | L698 | n — history, review record |
| 2026-09-08 | C8: four pure engines stay on branch | L723 | n — reversed 2026-09-11, AI pipeline ported |
| 2026-09-08 | C4(c)'s final drive delegated | L731 | n — history, session logistics |
| 2026-09-09 | 3.0.0 ships a UI that has been looked at | L741 | n — history, v3.0.0 already shipped |
| 2026-09-09 | Even-count median pinned below `all` gate | L757 | y — governs probeSize median rule |
| 2026-09-11 | Accessibility crash does not block v3.0.0 | L774 | y — still governs VoiceOver deferral |
| 2026-09-11 | Consolidation plan archived; v3.0.0 next cut | L798 | y — governs feature-freeze lapse |
| 2026-09-11 | Clicking a pane selects it again | L819 | y — governs `SelectsPaneOnClick` |
| 2026-09-11 | mac4DSTEM ships arm64 only | L859 | y — governs release arch pin |
| 2026-09-11 | AI pipeline ported onto `main`, reversing "leave" | L890 | y — governs `ai-analysis` branch status |
| 2026-09-11 | AI work gets 6th workspace "AI Analysis" | L902 | y — governs workspace placement |
| 2026-09-11 | Precipitates ship only if baseline beaten | L919 | y — governs precipitate ship gate |
| 2026-09-11 | `-DACCELERATE_NEW_LAPACK` accepted in Package.swift | L932 | y — governs the LAPACK build flag |
| 2026-09-11 (2nd round) | How the unattended port behaves | L950 | n — history, one-off port session |
| 2026-09-11 | Precipitate density by CLASSIFYING patterns | L992 | y — governs current precipitate route |
| 2026-09-11 | AI work NOT consolidated into one folder | L1031 | y — governs Core/ML, Session placement |
| 2026-09-11 | `docs/ai-ml/` brief ported to `main` | L1045 | n — history, one-off port note |
| 2026-09-11 | PCA stays for now | L1065 | y — governs PCA-over-NMF choice |
| 2026-09-11 | Class ID should be TEMPLATE-MATCHED, not unsupervised | L1074 | n — superseded by the next entry, same day |
| 2026-09-11 | Ridge filter is PARKED, not retired | L1087 | y — governs parked-not-retired status |
| 2026-09-11 | Class ID is TEMPLATE-MATCHED and MATERIAL-GENERAL | L1100 | y — governs precipitate classification design |
| 2026-09-12 | `unit` free-space floor drops 8→4 GB | L1122 | y — governs run-tests.sh preflight |
| 2026-09-12 | Vector matching lands unvalidated, deliberately | L1149 | y — governs phase-mapping unvalidated-ship stance |
| 2026-09-12 | β″ built-in structure, not import-only CIF | L1166 | y — governs β″ handling |
| 2026-09-12 | Matrix stated by user, never inferred | L1182 | y — governs phase-mapping matrix input |
| 2026-09-12 | In-plane angle reported mod projected symmetry | L1192 | y — governs orientation angle convention |
| 2026-09-12 | Chance guard stays although inert at shipped settings | L1203 | y — governs chance-guard retention |
| 2026-09-12 | Completeness is chance-level test, not fraction | L1218 | y — governs matcher completeness score |
| 2026-09-12 | Throughput leaves status strip | L1230 | y — narrows the 2026-09-04 status-bar decision |
| 2026-09-12 | A readout is not an event | L1251 | y — governs ActivityLog logging rule |
| 2026-09-14 | `Crystal.reflections` deviates from py4DSTEM tile bound | L1266 | y — governs the DEVIATION note |
| 2026-09-14 | Matrix gets last word; spotty annulus refused not flagged | L1284 | y — governs two verdict-presentation rules |
| 2026-09-14 (later) | Ellipse refusal is a degeneracy bound | L1316 | y — governs ellipse refusal design |
| 2026-09-15 | Ellipse flag behind a click; Fit Anyway refuses >1 ring | L1337 | y — governs shipped Fit-Anyway UI |
| 2026-09-15 (night) | Rotation null keeps the field's structure | L1369 | y — governs `RotationCalibration.solve`'s null |
| 2026-09-15 (night) | Zone-axis sweep is its own null | L1390 | y — governs `ZoneAxisFit`'s second null |
| 2026-09-15 (late night) | HDF5 serialised by a lock, not an actor | L1406 | y — governs `HDF5Serial` design |
| 2026-09-15 | Three decisions step 3 turned on, taken, measured | L1422 | y — governs Friedel-floor/reach/reference defaults |
| 2026-09-15 | Detection default stays py4DSTEM's 0.5% | L1465 | y — governs shipped detection default |
| 2026-09-15 | Orientation relationship lands inert, no panel control | L1476 | n — superseded same day by the OR-form entry |
| 2026-09-15 | Verdict cliff at 3/4 pair radius; OR gets control | L1491 | y — governs cliff constants |
| 2026-09-15 | OR stated as parallel vectors, gets control | L1510 | y — governs the current OR field design |
| 2026-09-16 | Step 3 gets a stopping rule, set before measuring | L1524 | y — governs step-3 lever-closure rule |
| 2026-09-16 | Three rules overruled; merge is split | L1549 | y — governs C5/on-screen/commit rules today |

## Table 4 — docs/open-items.md triage

- **Item count:** 77 `###`-level items (plus 7 `##` lane-group headers = 84
  headings total).
- **Marked closed/resolved/superseded but still fully present (not moved to
  archive):** none is a bare "closed, forgotten" duplicate — the file is
  disciplined about only keeping genuinely open items. But **5 items carry an
  internal "closed"/"fixed" sub-clause alongside a still-open residual**, and
  in 2 of those 5 the residual is now small enough that the item should be
  trimmed rather than kept at full length: "HDF5 runs under one lock now —
  what that costs and what is still open — fixed 2026-09-15 late night" (30
  lines; title says "fixed", ~6 lines of actual residual); "The zone-axis
  sweep marks a wrong axis against its own median... residuals" (41 lines;
  fix landed and Gate B'd, ~3 lines of residual under "Residuals:"). The
  other 3 ("Origin-fit gate has two unresolved holes", "The sidecar reader
  has D003's missing guard too — not fixed", "Manual Q and R pixel scale
  cannot be corrected once entered — fixed in code, drive owed") correctly
  keep full length because most of the content is still open.
- **Items exceeding the CLAUDE.md rule "≤ 12 lines each": 41 of 77 (≈53%).**
  The rule is stated in CLAUDE.md/AGENTS.md and in open-items.md's own
  header ("Each entry is ≤ 12 lines and dated") — the file violates its own
  stated format more often than it follows it.
- **The 15 longest items, with line counts:**

| rank | lines | item |
|---|---|---|
| 1 | 158 | Step 3 ran on a stride-3 subsample and is OUTSIDE their band — measured 2026-09-15 |
| 2 | 53 | The matrix is a verdict by exclusion, so it fails exactly when detection improves — MEASURED 2026-09-16, Gate D target |
| 3 | 46 | The rotation null keeps the field's structure now — what it still cannot do — Gate D 2026-09-15 night |
| 4 | 41 | The zone-axis sweep marks a wrong axis against its own median — Gate D 2026-09-15 night, residuals |
| 5 | 33 | Reading an accessibility label crashes the app — evidence aged off 2026-09-15, suspect named |
| 6 | 33 | 26 of 200 ACOM templates do not recover themselves at an off-grid rotation — added 2026-09-14 |
| 7 | 30 | HDF5 runs under one lock now — what that costs and what is still open — fixed 2026-09-15 late night |
| 8 | 30 | Step 3's 2026-09-16 increments — the record is archived, these are the live residuals |
| 9 | 27 | ACOM returns a zone axis up to 12.8° beyond what its bank forces — MEASURED 2026-09-15 |
| 10 | 25 | The published v2.5.1 artefact is universal, and Intel users get a broken app |
| 11 | 25 | A stale DerivedData test bundle fakes both a pass and a surviving mutation — added 2026-09-12 |
| 12 | 24 | The ellipse "Fit anyway" mark: what it does not yet do — added 2026-09-15 |
| 13 | 23 | The one-peak warning is below the fold, and Strain unlocks without it (2026-09-09) |
| 14 | 22 | Toolbar Cancel button renders wrong during a run — cosmetic, not blocking (2026-09-04) |
| 15 | 22 | Parallax and ptychography are unrunnable on the owner's Mac (2026-09-11) |

## Table 5 — Generated / mirrored files

| pair | result | detail |
|---|---|---|
| `AGENTS.md` vs `tools/sync-agents-md.sh`'s output from `CLAUDE.md` | **identical** | verified with `tools/sync-agents-md.sh --check` (read-only: compares against a temp file, does not write `AGENTS.md`) → "AGENTS.md is in sync with CLAUDE.md." AGENTS.md's own staleness (the v3.0.0 front-matter claim) is therefore CLAUDE.md's staleness, propagated correctly by the generator — fixing CLAUDE.md and re-running the script fixes both. |
| `.agents/skills/adversarial-review/SKILL.md` vs `.claude/skills/adversarial-review/SKILL.md` | **identical** | both 79 lines, `diff` exit 0 |
| `.agents/skills/diagnose/SKILL.md` vs `.claude/skills/diagnose/SKILL.md` | **identical** | both 68 lines, `diff` exit 0 |
| `.agents/skills/closeout/SKILL.md` vs `.claude/skills/closeout/SKILL.md` | **different** | `.agents/` 69 lines, `.claude/` 75 lines. `.agents/` copy is **stale**: (1) still says "do not commit unless the user asked" where `.claude/` reflects the 2026-09-16 "Commit freely" rule; (2) hardcodes the v2 Board artifact URL (`https://claude.ai/code/artifact/02ef433e-...`) that MEMORY.md explicitly warns against ("its URL form CHANGED 2026-09-15... never the address hardcoded in the skill") — the `.claude/` copy correctly says to find it by title instead. |
| `.agents/skills/pickup/SKILL.md` vs `.claude/skills/pickup/SKILL.md` | **different** | `.agents/` 41 lines, `.claude/` 46 lines. `.claude/` copy adds the "A red gate outranks a verification gate (2026-09-09)" paragraph that `.agents/` lacks. **Both copies share one stale line** ("Commit only if asked; never push — the owner pushes", unchanged by the diff) that contradicts the current CLAUDE.md rule — this is not a sync-drift issue between the two copies, it is a shared staleness neither copy has fixed. |

Net: of the 4 skills, 2 pairs are byte-identical and 2 have drifted; of the 2
drifted pairs, the `.agents/` copy is behind in both cases, and one fact (the
commit-freely rule) is stale in *all four* pickup/closeout files taken
together in at least one place each.

## Table 6 — Per-file summary

| path | lines | sections | rows by verdict | proposed destination |
|---|---|---|---|---|
| CLAUDE.md | 100 | 4 | CLAUDE 2, ARCH 1, RELEASE 1 (stale) | CLAUDE.md (fix front matter) |
| AGENTS.md | 108 | 5 | delete 4, keep 1 | delete (generated; edit CLAUDE.md) |
| README.md | 141 | 10 | keep(file) 6, RELEASE 2, ARCH 2 | README.md (trim duplicated numbers to pointers) |
| ROADMAP.md | 126 | 9 | archive 5 (2 stale), ARCH 3, ADR 1 | mostly archive; 2 confirmed-stale sections need fixing first |
| CONTRIBUTING.md | 108 | 7 | ARCH 4, CLAUDE 1, keep 2 | CONTRIBUTING.md (dedupe "Where code goes" and Build against ARCH/CLAUDE) |
| CHANGELOG.md | 518 | 5 | RELEASE 4, keep 1 | RELEASE.md is the summary; CHANGELOG.md stays as full record |
| docs/status.md | 185 | 6 | RELEASE 1, archive 3, open-items 2 | split: Releases→RELEASE.md, dated rows→archive, Handoff→open-items.md |
| docs/v3-plan.md | 170 | 8 | ADR 2, ARCH 3, open-items 1, archive 1, CLAUDE 1 | mostly ARCH (reference) + ADR (decided items) |
| docs/open-items.md | 1378 | 84 | open-items 68, archive 11, ARCH 3, CLAUDE 0 | stays open-items.md; 41 of 77 items need trimming to ≤12 lines; 11 near-closed items ready to archive |
| docs/development-process.md | 238 | 14 | CLAUDE 6, ARCH 6, archive 2 | split between CLAUDE.md (standing rules) and ARCH (process reference) |
| docs/architecture.md | 308 | 11 | ARCH 10 (1 stale), keep 1 | ARCHITECTURE.md; fix the C5-hard-form staleness and delete the SUPERSEDED presentation-contract section |
| docs/decisions.md | 1579 | 98 (1 grouped + 97 individual) | ADR 96, archive 2 | decisions/ folder, one ADR per entry; 21 of 97 are superseded/history-only and can be dropped or marked closed |
| docs/releasing.md | 197 | 9 | RELEASE 9 | RELEASE.md as-is, near-canonical already |
| docs/dm4-format.md | 331 | 1 (treated as one unit) | ARCH 1 | ARCHITECTURE.md appendix, unchanged |
| docs/q-calibration-design.md | 634 | 15 | ARCH 9, ADR 3, archive 3 | mostly ARCH reference; extract 3 owner-decision sections to ADR; fix broken `docs/v2-release.md` citation |
| docs/py4dstem-pipelines.md | 352 | 5 | ARCH 2, archive 3 | keep §0-6 as ARCH reference appendix; archive §7-10 (dated/retired) |
| docs/ai-ml/README.md | 284 | 11 | ARCH 9, ADR 1 (stale) | ARCHITECTURE.md appendix; fix stale commit/push line |
| docs/ai-ml/precipitates.md | 167 | 10 | archive 10 | archive whole file — route it describes is superseded, not self-flagged |
| docs/v3-phase-mapping-method-choice.md | 101 | 7 | ADR 5, archive 1, open-items 1 (stale) | ADR folder; fix the "still blocking" list (2 items already resolved elsewhere) |
| docs/v3-precipitate-classification.md | 270 | 7 | ARCH 3, archive 1, open-items 1, ADR 2 | mixed; §5 (117 lines) should shrink to a pointer once its 4 decisions are ADRs |
| docs/v3-vector-matching-plan.md | 221 | 6 | open-items 2, ARCH 3, ADR 1 | mixed; the "build order" section is the most cross-referenced content in the corpus |
| tools/acom-convention-test/README.md | 69 | 4 | ARCH 4 | ARCHITECTURE.md appendix (or stays as tools/ README) |
| tools/disk-correlation-parity/README.md | 180 | 10 | ARCH 9, ADR 1 | ARCHITECTURE.md appendix (or stays as tools/ README) |
| tools/disk-detector/README.md | 337 | 12 | ARCH 8, archive 2 | ARCHITECTURE.md appendix; archive the two dated experiment-log sections |
| tools/performance-baseline/README.md | 15 | 1 | ARCH 1 | ARCHITECTURE.md appendix (or stays as tools/ README) |
| .claude/skills/adversarial-review/SKILL.md | 79 | 1 | CLAUDE(procedure) 1 | stays as skill; identical to `.agents/` copy |
| .claude/skills/closeout/SKILL.md | 75 | 1 | CLAUDE(procedure) 1 | stays as skill; current; `.agents/` copy needs sync |
| .claude/skills/diagnose/SKILL.md | 68 | 1 | CLAUDE(procedure) 1 | stays as skill; identical to `.agents/` copy |
| .claude/skills/pickup/SKILL.md | 46 | 1 | CLAUDE(procedure) 1 (stale line) | stays as skill; fix the "commit only if asked" line to match CLAUDE.md |
| .agents/skills/adversarial-review/SKILL.md | 79 | 1 | (mirror) | identical, no action |
| .agents/skills/diagnose/SKILL.md | 68 | 1 | (mirror) | identical, no action |
| .agents/skills/closeout/SKILL.md | 69 | 1 | (mirror, stale) | needs sync from `.claude/` copy |
| .agents/skills/pickup/SKILL.md | 41 | 1 | (mirror, stale) | needs sync from `.claude/` copy, then both need the commit-line fix |

## Broken citations

Checked every backticked, path-shaped token (has an extension or trailing
slash) across the 33 in-scope files against `git ls-files`, resolving
relative to the repo root, `mac4DSTEM/`, and `docs/` (matching the
inventory gate's own stated rule in `docs/status.md`: "a backticked path
rooted at the repo or at `mac4DSTEM/` must exist"). Excluded per the repo's
own stated exemptions: `References/*` (gitignored by design), `scratchpad/*`
(gitignored), dated run-log names (`*.log`/`*.json` inside session-scratch
directory names like `c4b/`, `thronsen-*`, `s4/` — these are explicitly
"names, not paths" per CLAUDE.md's own rule), and paths inside an external
project's own source tree cited as an authority reference
(`py4DSTEM/io/filereaders/read_dm.py`, `rsciio/...`).

| path cited | cited in | note |
|---|---|---|
| `docs/images/precipitates-al-simg-near-beam-2026-09-07.png` | docs/ai-ml/README.md §4, docs/ai-ml/precipitates.md §9 | **does not exist**; `docs/images/` contains only `strain-map-workspace.png` |
| `docs/v2-release.md` | docs/q-calibration-design.md (front matter, and §5 "S13 is **Gate B**") | **does not exist at this path**; moved to `docs/archive/v2/v2-release.md`. Cited twice, in the same file, uncorrected |
| `Session/PrecipitateProduct.swift` | docs/ai-ml/precipitates.md §4 | not on `main` — confirmed branch-only (`ml/disk-detector`) by v3-precipitate-classification.md §3's own text ("It does not exist on `main`"); precipitates.md's own front matter does say "code on the branch", so this is a correctly-scoped branch reference, not an error |
| `UI/PrecipitateSettings.swift` | docs/ai-ml/precipitates.md (front matter) | same as above — branch-only, correctly scoped in the same sentence |
| `tools/ui-qc-playthrough/run.sh` | CHANGELOG.md v1.0.0 §Verification | correctly parenthesised "(since removed)" in the same sentence — not an error, listed for completeness |

Two genuine broken citations (the PNG and `docs/v2-release.md`); the other
three are self-scoped correctly by the citing text and are not defects.

## Summary of biggest duplication clusters and verdict counts

See the closing chat message for the 15-line summary requested by the task.

