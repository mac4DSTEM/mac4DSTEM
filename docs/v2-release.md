# mac4DSTEM v2 — the release contract and session plan

**Decided 2026-08-18** in the release-planning session, with the release owner
answering every scope question individually. This file supersedes
[`docs/v2-scope.md`](v2-scope.md) (the 2026-08-17 phase priorities) and
[`docs/load-pipeline-plan.md`](load-pipeline-plan.md) (the L1–L6 build plan,
now code-complete) **as the single entry point**. Both are kept as records;
neither should be extended.

**The two live logs are unchanged:** [`docs/open-items.md`](open-items.md)
(defects, findings, backlog) and
[`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md)
(Track B). This file carries the contract, the session plan, and the status
checklist — nothing else.

---

## 1. The release claim

> **Rehearse on a view. Promote overnight. Hand a colleague the recipe. Trust
> what's on screen.** An analysis validated on a cropped, binned view re-runs
> unchanged on the full dataset — unattended, calibration re-referenced,
> results traceable to *file + specification* — and nothing displayed or
> exported can be misread as a quantitative claim the app isn't making.

Four sentences, four commitments:

1. **Rehearse on a view** — the load pipeline (L1–L6, code-complete), closed
   as a *product*: driven on screen, with the claim's fixture behind it.
2. **Promote overnight** — one action reopens at full extent and replays the
   validated analyses with the user's parameters, unattended, machine held
   awake. New scope, decided 2026-08-18: without it, promotion at 60 GB means
   returning to click each analysis over several nights.
3. **Hand a colleague the recipe** — the session sidecar is the sharing unit:
   same cube (the group NAS), plus a small sidecar carrying the specification,
   the calibration, the results, and (new) the replay record. A colleague opens
   the cube and is where you were. A standalone reduced *file* export also
   ships, for py4DSTEM handoff and offline work.
4. **Trust what's on screen** — the verified science-presentation defects are
   fixed, Q calibration refuses what it cannot measure, and WS₂ enters through
   the full model contract so `polycrystal_2D_WS2` reaches ACOM honestly.

## 2. What is in — five workstreams

**W1 — Close the load pipeline as a product** (S1–S6, TB1). The two-spec
analysis fixture (the claim's evidence). The sidecar/sandbox defects fixed,
HDF5 errors un-silenced. `.automatic` residency **dropped** (owner decision
2026-08-18 — the threshold is unmeasurable on one machine; manual
load-into-memory stays; the mechanism stays in the code and `.automatic` can
return when a second-machine sweep makes a threshold defensible). A visible
promote control. The promote run (replay record + unattended execution). The
configurator finished (single-DP picker, dims, the small defects). The F1
Track B queue driven to empty.

**W2 — Trust fixes** (S7–S10). The four verified defects (strain frame, iDPC
gate, iDPC zero-fill, disk-detection error attribution), the caption
truncation (the burned-in caption *is* the provenance record), the process-wide
`H5Eset_auto2` silencing, the DM4 `.mappedIfSafe` / 8 GB investigation-then-fix,
and the **reduced-file export** — the refusal on exporting a cropped view is
lifted by teaching the exporter the crop, verified by a py4DSTEM round-trip.

**W3 — Q-calibration robustness** (S11–S13). Triage of the unverified review
leads first, then the estimator-internal plausibility gate, the
sane-origin/measure-Q split, and the `.fileMean` fix so the file's own stated
beam centre is no longer ignored. The `measureOrigin` frame-dependence is
**weighed in S12 with evidence**, not decided in advance.

**W4 — WS₂ campaign** (S14–S16, TB2). The full `ROADMAP.md` P1.3 contract, no
shortcuts: literature lattice, two-species basis, symmetry reduction, structure
factors, expected-orientation fixture, fit-overlay Track B acceptance. Ends
with `polycrystal_2D_WS2` reaching ACOM for the first time.

**W5 — Verification debt and release mechanics** (S17–S21). The sidebar
intermittent diagnosed or honestly quarantined, claims restated to what a
reader can reproduce, the polish sweep, floor raised to macOS 26, **CI on the
public repo** (S21 — the badge becomes the aggregate claim), then the full
release pipeline.

### The cut line

**The release is shippable after W1 + W2 + W5.** W3 and W4 (S11–S16, TB2) are
the severable block: cutting them to a fast v2.x weakens no other workstream
and nothing downstream needs rework. Cutting is the release owner's explicit
decision at the time, never a default — this line exists so that a schedule
problem can never argue for thinning a review gate instead. The promote run
and the reduced-file export are **binding**: they are part of the claim.

## 3. What is out — named, with entry conditions

Carried over from `v2-scope.md` §3, updated 2026-08-18. Silence is never the
reason something is missing.

| Deferred | Entry condition / note |
|---|---|
| **ML / MLX disk detection** | The `docs/development-process.md` §3 feasibility spike first. |
| **Batch processing / apply-a-recipe-to-many** | S5's replay record is the seed; generalising it to many datasets is its own feature after v2. |
| **Physical virtual-detector designer** (mrad / Å⁻¹) | Blocked on trustworthy Q calibration — **entry condition met by W3**. First v2.x candidate. |
| **Automated data-quality checks** | Serves the refusal rule; first v2.x candidate alongside the above. |
| **Linked 4D-STEM explorer** | Wants `AppState` decomposition further along; closer after this phase's seams. |
| **Materials Project lookup** (WS₂ step 2) | Needs network/sandbox/API-key design. Step 1 (local literature CIF) ships in W4. |
| **Screen-reader (VoiceOver) usability** | Opens when a real user needs it (2026-08-05 decision; procedure archived). |
| **Cropping a dataset that is already open** | A reopen with a different specification under the view model; its own stage if the gesture is wanted. |
| **Real-space binning or thinning** | Never asked for. |
| **MIB/EMPAD readers out of Preview** | Blocked on real acquisitions from two instruments — owner hardware, not sessions. |
| **`.automatic` residency + second-machine sweep** | Post-v2, by the 2026-08-18 decision. The sweep re-opens `.automatic`; if two machines disagree, the rule needs a second term, not a compromise value. |
| **Precipitate analysis, EDX correlation, live acquisition, copilot** | Each is its own product. |

The external v2 feature vision (2026-08-18) is fully accounted for: its two
must-haves were already this phase's work under other names (recipes →
`LoadSpecification` + L6 provenance + S5's replay record; large-data workflow →
the load pipeline), its trustworthy-v1 premise **is** W2 + W3, and its
remaining items are the table above.

## 4. The refusal rule

Folded verbatim from `v2-scope.md` §4 — it survives every reorganisation.

**1. Nothing ships that can fabricate a scientific result, and no gate is
widened to make something pass.** Use precision to *explain* a rejection,
never to grant an admission. A calibration value that cannot be re-referenced
is invalidated with a named reason, never carried. A gate whose miss path
records an error and continues is not a gate. Operational form: **never let
the model that wrote a science-affecting change be the only one to approve it,
and review the diagnosis, not just the code.** Three times now — 2026-08-05,
2026-08-06, 2026-08-18 — a confident diagnosis passed every test written for
it and was refuted by a second reader of the same evidence.

**2. No claim in `README.md`, `CHANGELOG.md` or `docs/` that a reader cannot
reproduce on a current machine.** A claim about a failure needs the same
evidence as a claim about a success.

## 5. Version policy

**The number is decided at S20, on the recorded evidence — not before** (owner
decision 2026-08-18). The evidence so far, recorded so the ship-time decision
is one paragraph:

- A v1.0.0 build does **not refuse** an L6 sidecar that carries a crop — it
  silently ignores the `mac4dstem_load_specification` attribute and restores
  scan-indexed results against the **full** extent: right numbers at wrong
  positions, no warning. Worse than "cannot read". (Verified 2026-08-18: the
  sidecar carries no format gate a v1.0.0 build checks.)
- S5 adds a replay record to the sidecar — a second format extension. Whether
  new sidecars gain a minimum-reader marker (so this class of question is
  decidable next time) is settled in S5, where the format changes anyway.
  **Settled 2026-08-24 (S5):** every sidecar now carries
  `mac4dstem_min_reader_schema` — the oldest schema that interprets the file
  *without misreading it* ("6" when a reduced specification is recorded,
  "5" otherwise), the session schema is bumped to "6" and derived from one
  constant so it can never silently stay put again, and readers AND
  rewriters refuse whole (both numbers named) when a file demands more than
  the build supports. The unfixable half is stated where the marker is
  defined: v1.0.0 checks nothing, so the marker protects the *next* format
  change, not the last one.
- Full-extent sidecars without a replay record remain byte-compatible either
  way; an ordinary v1.0.0 user loses nothing.

Interim releases, if any, stay `v1.0.x` (bug fixes and claim corrections
only).

## 6. Done criteria

1. **The two-spec fixture is green in `scientific`** — the same analysis under
   a reduced specification and at full extent, compared, each case naming the
   invariance it claims. Not a self-consistency check.
2. **The F1 queue is empty** and the promote control was driven on screen.
3. **A real rehearse → overnight-promote completed unattended**, driven once
   by the release owner end to end.
4. **The colleague-sidecar row passes on the clean account** — a cube opened
   with someone else's sidecar restores their view, results and recipe.
5. **The reduced-file export round-trips through vendored py4DSTEM** — origin
   on the beam — and the refusal is gone.
6. **The four defects + `H5Eset_auto2` + DM4 + caption are fixed**, each
   through its gate, each control verified to bite.
7. **Q calibration refuses what it cannot measure** (estimator-internal gate,
   `.fileMean` fixed), fixture-pinned.
8. **WS₂ is admitted through the P1.3 contract** and `polycrystal_2D_WS2`
   reaches ACOM with fit-overlay acceptance on screen.
9. **The four review leads are each verified or dismissed in writing.**
10. **`tools/run-tests.sh all` is green on the current OS** with the sidebar
    test resolved or formally quarantined — and `README.md` / `CHANGELOG.md`
    state only what a reader can reproduce.
11. **Every session that touched `AppState` extracted its seam.**
12. **The floor is macOS 26** (retires the legacy-`.icns` item as moot).
13. **Signed, notarized, stapled, clean-account launch, full Track B standing
    pass recorded** — and the version number decided on §5's evidence.
14. **CI runs `unit` + the synthetic half of `scientific` on every push**, and
    the README badge is the aggregate claim (S21).

(7–8 move to the v2.x criteria if the cut line is exercised.)

## 7. The gates — how a session guards against a confident wrong diagnosis

This repo's documented failure mode is a diagnosis that passes every test
written for it and is still wrong. It has happened **three times**, most
recently 2026-08-18 — twice in one day, both refuted by a second agent reading
the same code. The guard is structural, not a reminder. Every session in §8
names one of three gates:

**Gate A — mechanical / UI.** Ordinary `/code-review` (Opus per
`docs/development-process.md` §2). If it changes what the app draws, a Track B
row is queued — written against what the build actually does (the F1.1
lesson: a row nobody can pass spends the one resource Track B is expensive
in).

**Gate B — science / `Core/`.** An adversarial review by a **separate agent
briefed to refute**, plus a `tools/` fixture. Every negative control names
the line it breaks and why the failure follows — "it went red" is not
evidence (the L4 phantom-control lesson). The highest-stakes case (S8) runs
the review at the Fable 5 tier.

**Gate D — diagnosis-driven work.** Before any code changes, the session
writes down, in this order:

1. **The diagnosis** as currently believed, with its evidence.
2. **The observation that would refute it.**
3. **The predicted outcome** of the discriminating experiment.

Then it **runs the experiment**. A fix may only land on a diagnosis that
survived its own refutation test, and a second agent reviews the diagnosis
**against the primary evidence** — the log, the fixture output, not the diff —
before the session closes. This is exactly the move that caught all three
wrong diagnoses; it is the entry ticket now, not the postmortem.

**Standing session rules, all gates:**

- A session touching `AppState` extracts one seam first
  (`docs/development-process.md` §7 — cheapest true seam, ranked by state
  ownership).
- At most **one Gate-B science campaign in flight at a time** — fixture
  campaigns and adversarial-review capacity are the scarce resources.
- Every session closes by stating **what was not verified**. Every claim
  written into docs carries its evidence and date.
- Acceptance is evaluation only: never change app code to make a Track B row
  pass — that is a finding.
- Before trusting any new test: break the code it covers and watch it fail.

## 8. The session plan

Owner passes (TB) are the scarce resource; the order front-loads what unblocks
them. "Parallel" means the sessions are independent — in a solo-dev repo they
still run one at a time, but either order works and nothing blocks.

| # | Session | Gate | Depends on | Notes |
|---|---------|------|-----------|-------|
| S0 | This plan written; CLAUDE.md repointed; superseded docs bannered. **Outstanding:** the free-space preflight in `tools/run-tests.sh` (~15 lines, decided in v2-scope §6.6) | A | — | Docs half done 2026-08-18 |
| S1 | **Sidecar under the sandbox.** Un-silence `H5Eset_auto2` *first* (it is the diagnostic instrument), then the three-cold-opens experiment on the restore failure, then fix `recordedLoadSpecification` (`AppState.swift:1416-1431`, `:1801-1808`) and the restore path per the outcome. Seam: sidecar/restore state | **D** | S0 | Unblocks F1.3f. Predicted: deterministic ⇒ bookmark/sandbox; ~1/3 ⇒ race |
| S2 | **The two-spec analysis fixture** (`tools/` name at build time; goes into `scientific`). Virtual image + disk detection under a reduced spec vs full extent. Ground truth is the **full-extent run on the overlap** — never cropped-vs-cropped. Scan-crop cases compare exactly; detector-crop/bin cases compare through re-referenced coordinates; **each case states which invariance it claims**. Also close the L3 residual: exercise `FourDArray.tile(yRange:from:)` at `lowerBound > 0`. **Seed the metamorphic property suite here:** invariances as tests over randomized fixtures — translation equivariance (the `measureOrigin` class of defect), bin intensity conservation, crop/analysis commutation — so this class is caught by machine, not by late manual reasoning. **Create `tools/lib/sources.manifest`** (one shared source list; this and future runners include it — the fix for the 2026-08-17 five-of-eight-runners breakage), and compile the fixture with the app's isolation flags, closing the recorded `swiftc`-defaults blind spot | **B** | — | Parallel with S1 |
| S3 | **Drop `.automatic`** from model and UI (behaviour is unchanged — it already streams); build the **promote control** ("reopen at full extent", placement decided in-session). Seam | A | S0 | Parallel with S4 |
| S4 | **Configurator finish.** `contentVersion` value-dependence first (`LoadConfiguratorView.swift:142`, `DatasetInspector.swift:230`), then the single-DP picker + real-space dims (owner requests, 2026-08-18), the sheet clipping (`:44`), the missing `progress:` argument (`AppState.swift:1487-1490`); and the two the release owner raised on 2026-08-19 while driving the build — say what a detector **crop** costs versus a **bin** (they trade against different things and the panel presents them as siblings), and refuse a detector crop that excludes the direct beam *at configure time*, since the existing refusal in `CalibrationReReference` only fires when there is already a calibration to re-reference and so is silent on a first open | A | S0 | Parallel with S3 |
| S5 | **Promote run I — the replay record.** Which analyses ran, with which parameters, serialized with the session — this is what turns the sidecar into a full recipe, and it is a sidecar format change (§5 evidence; the minimum-reader marker is decided here) | B-lite | S3 | Round-trip fixture extends `tools/load-spec-roundtrip` |
| S6 | **Promote run II — unattended execution.** Sequential replay at full extent, keep-awake assertion, morning summary. A failed step **halts honestly** — it must never continue silently past a failure | A | S5 | Track B row queued |
| TB1 | **Owner pass:** F1 queue to empty (F1.3b re-drive first), the promote row, one real rehearse → overnight promote, the colleague-sidecar row (foreign sidecar, clean account), the aspect-stretch decision once previews draw | — | S1, S3–S6 | Agent continues W2 meanwhile |
| S7 | **Error honesty.** iDPC gate consults `originFitIsQuantitative` (`AppState.swift:3806`); `DPC.integrateIDPC` returns a typed error instead of a zero image; tile-read errors attributed correctly (`TiledDiskDetection.swift:42`); caption truncation fixed — and the **full provenance record written into the exported image's metadata** beside the burned caption, so the pixels stop being the only carrier. **Bounded `try?` audit of `Core/`**: every hit becomes a typed error or gains a comment saying why swallowing is correct — the zero-fill and tile-error defects are two instances of one class; kill the class. **This session's seam is the readiness/gating type**: one `@Observable` policy owner for every "may I?" question, so a gate can only exist once — the iDPC defect is literally two call sites deriving the same policy differently | **B** | — | Parallel with TB1 |
| S8 | **Strain frame.** Owner design decision in-session (rotate into scan frame vs label diffraction-frame + export the R–Q transform; parity reference `get_rotated_strain_map`, `latticevectors.py:409`). Resolve or explicitly re-scope **#18** here | **B**, Fable 5 tier | S7 done or parked | Highest-stakes review of the phase |
| S9 | **The 8 GB death.** Local-vs-NAS `footprint` experiment on the 17 GB DM4 (predicted: local flat, NAS climbs toward file size ⇒ `.mappedIfSafe` fell back to a full read), then fix — refuse or stream, never silently allocate the file. Secondary: bound the tile budget by *free* RAM; re-examine the "GPU budget" label (`LoadConfiguratorView.swift:255`) | **D** | NAS access | |
| S10 | **Reduced-file export.** Teach `transformedCalibration` the detector crop, lift the refusal, and have the exported file carry the S5 recipe. Fixture: export a cropped view, open it in vendored py4DSTEM, the origin lands on the beam | **B** | S5, S8 | Wrong output here escapes the app — full adversarial pass |
| S11 | **Leads triage.** Verify or dismiss, in writing, each of: ACOM omitting `power_radial=1.0`; the Q-cal estimator vs py4DSTEM's radial-profile fit; HDF5 discovery assuming `[Ry,Rx,Qy,Qx]` without axis metadata; the strain weighting deviation absent from provenance. Plus the bounds-convention sweep (index-vs-centre on continuous positions). Confirmed items become open-items entries with owning sessions | B-lite | after TB1 | Findings feed S12 |
| S12 | **Q-cal design.** Read the campaign's `constant_rms`/`parabola_rms` (settles #29's direction cheaply — the data exists and has never been read). Design the estimator-internal plausibility gate and the sane-origin/measure-Q split. **Weigh the `measureOrigin` coarse step** (translation-equivariant Gaussian vs the binned-block deviation) with evidence, and recommend in-or-out for S13 | Plan | S11 | Owner sees the design |
| S13 | **Q-cal implement.** The in-estimator check (median innermost radius vs reference shell), the `.fileMean` fix, the split predicates, fixture + adversarial review; the origin step per S12's recommendation | **B** | S12 | |
| S14 | **WS₂ I.** Literature CIF (2H, P6₃/mmc, a ≈ 3.153 Å, c ≈ 12.323 Å; source cited in the header; owner confirms the variant). Import fixture: hexagonal + two-species is what nothing else covers | **B** | S13 (review capacity) | Never invent the lattice |
| S15 | **WS₂ II.** Structure factors, symmetry reduction, expected-orientation fixture | **B** | S14 | |
| S16 | **WS₂ III.** ACOM on `polycrystal_2D_WS2`, adversarial review, fit-overlay Track B row queued | **B** | S15 | |
| TB2 | **Owner pass:** WS₂ fit overlay + everything queued since TB1 | — | S16 | |
| S17 | **Sidebar intermittent.** Instrument the run-to-run variable (measured heights, display scale, window-server state across runs), then fix the threshold on a principled number or formally quarantine with the claim adjusted. **Was 60 ever a threshold, or one machine's measurement rounded up?** | **D** | — | Any time; must precede S19 |
| S18 | **Polish sweep.** Colorbar/scale-bar collision, #38 scroll monitor, the scan-extent two-orders display, comparison-panel `contentVersion` (`ProductWorkspaceViews.swift:719`), `pattern(ry:rx:)` honouring a resident cube, #37 re-measure, and the **resident staging-copy elimination** — bind the resident `MTLBuffer` at the tile's byte offset (`setBuffer(_:offset:)`) instead of buffer → `[Float]` → new `MTLBuffer` (~0.375 × working set of pure waste, found by the 2026-08-17 review) | A | late | Bounded: this list, nothing more |
| S19 | **Claims restatement.** README/CHANGELOG to what a reader can reproduce; `docs/releasing.md` gains `make-dmg.sh`; `LSMinimumSystemVersion` → 26 | A | S17, S21, green `all` | The CI badge from S21 becomes part of the restated claim |
| S20 | **Endgame.** Version number decided on §5's evidence; `/code-review ultra` on the release branch (owner triggers); `/security-review`; sign → notarize → staple; clean-account launch; full Track B standing pass A–F; **record the `tools/performance-baseline` table for the release** (so performance regressions become visible release-to-release the way parity regressions already are); tag | — | everything | |
| S21 | **CI on the public repo.** GitHub Actions macOS runner: `unit` + the synthetic-fixture harnesses of `scientific` on every push. The README badge then *is* the aggregate claim, and the refusal rule's second clause becomes mechanical — a stale claim cannot recur unnoticed. **Excluded and said so in the workflow file:** `real-data-acceptance` and every harness needing gitignored multi-GB data. Free for a public repo | A | S2 (manifest); before S19 | Sits in W5; can run any time after S2 |

**Owner-decision moments, so they never ambush:** TB1 and TB2 (driving time),
the strain-frame choice (S8), the aspect-stretch decision (TB1), the S12
design review, the WS₂ variant confirmation (S14), the version number (S20).
Everything else runs on the decisions recorded in this file.

**Sizing, honestly:** ~21 agent sessions plus two owner passes and the
endgame. The severable block (S11–S16 + TB2) is 6 sessions + one pass; the
binding core is ~15.

### Session kickoff (copy-paste)

```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/v2-release.md — §1 and §7 carry
the claim and the gate rules, §8 is the plan. Take the next unstarted session
in §9's checklist and follow its brief in §8.

Follow docs/development-process.md (Explore on Haiku to locate code, implement
on the default model) and take the gate the session names. Gate D sessions
write the diagnosis, the refuting observation and the predicted outcome BEFORE
touching code, then run the experiment. Gate B sessions get a separate agent
briefed to refute, plus a tools/ fixture whose negative controls name the line
they break. Never let the model that wrote a science-affecting change be the
only one to approve it — review the diagnosis, not just the code.

If the session touches AppState, extract one seam first. If it changes what
the app draws, queue the Track B rows and say the work is unverified on screen
until they come back. Break every new test before trusting it. When it lands:
tick §9, update docs/open-items.md, state what was NOT verified, stop. Commit
only if asked.
```

## 9. Status

- [x] **S0** — docs written 2026-08-18; free-space preflight landed
  2026-08-18 (`tools/run-tests.sh` `require_free_space`, 8 GB for
  xcodebuild modes / 4 GB for harness-only, exit 69 before any build).
  Deviation: none.
- [x] **S1** — 2026-08-18/19. Sidecar under the sandbox: the HDF5
  error-detail instrument landed, the EPERM denial was observed (C10 closed
  end to end), and the fix shipped on the new `App/SessionSidecarLocator.swift`
  seam with the refusal surfaced in the dataset inspector. Gate D — survived;
  5 deviations, all found by the second reader and fixed rather than argued
  with. Track A: `unit` 220 passed / 1 failed (the S17 sidebar intermittent).
  F1.3g/F1.3h PASSED on screen. Not verified: scoped-access start/stop pairing
  (untestable in an unsandboxed host) and the renamed-sidecar label.
  Full record: [`docs/archive/v2-session-records/s1.md`](archive/v2-session-records/s1.md).
- [x] **S2** — 2026-08-19. The two-spec analysis fixture:
  `tools/two-spec-analysis-test` (214 checks) joined `scientific`, with
  `tools/lib/sources.manifest` created, metamorphic properties P1–P4 seeded,
  and the L3 `tile(yRange:from:)` residual closed under a scan crop. Gate B —
  the refuter refuted four claims, all corrected in place; 4 deviations.
  Eight negative controls, each naming the line it breaks. Track A: no
  aggregate suite run recorded this session (the fixture's own 214 checks
  are the evidence). Not verified: no pre-existing runner migrated to the
  manifest; the isolation flags observe, not enforce.
  Full record: [`docs/archive/v2-session-records/s2.md`](archive/v2-session-records/s2.md).
- [x] **S3** — 2026-08-19. `.automatic` dropped from `Residency` (defaults
  `.streamed`; behaviour unchanged) and the promote control built —
  `promoteToFullExtent()` in the inspector's Loaded-view section — on the
  `App/RecentDatasets.swift` seam; all eight standing build-warning classes
  cleared. Gate A ran as an eight-finder review: 15 findings, 11 fixed
  in-session; 2 deviations. Track A: `unit` exit 0 (232 cases), `scientific`
  exit 0 (35 harnesses). Not verified: the promote control on screen
  (F1.14/F1.15 queued) and a real reduced→promote on a multi-GB cube.
  Full record: [`docs/archive/v2-session-records/s3.md`](archive/v2-session-records/s3.md).
- [x] **S4** — 2026-08-24. Configurator finished: value-dependent
  `contentVersion`, the restored `progress:` handler, the single-DP pane,
  scan/detector dims, the crop-vs-bin cost caption, the configure-time
  direct-beam refusal, and the three sidecar-identity items (Save As… /
  Change…, open-path recognition, `SessionSidecarFormat`). Gate A (4-finder)
  refuted or hardened 10 findings before landing; 3 deviations. Track A: MCP
  `test_macos` 260/0, `real-data-acceptance` exit 0, `scientific` exit 0;
  `unit` REFUSED by the S0 preflight (exit 69, ~4 GB free). Not verified on
  screen: everything — F1.16–F1.21 queued, F1.3i re-armed behind F1.20.
  Full record: [`docs/archive/v2-session-records/s4.md`](archive/v2-session-records/s4.md).
- [x] **S5** — 2026-08-24. The replay record: `SessionReplayRecord` + the
  `SessionReplay` seam, five recording sites, serialized with the session,
  restored on open, carried by every save; schema "6" +
  `mac4dstem_min_reader_schema` with refusal on read AND rewrite (§5's
  decision); the rewrite-erases-the-crop defect and the S3-carried recovery
  finding fixed. Gate B-lite: 17 findings, 14 fixed in-session; 3 deviations.
  Track A: MCP `test_macos` 282/0, `load-spec-roundtrip` exit 0;
  `unit`/`scientific` not re-run (disk unchanged since S4's refusal). Not
  verified: everything on screen, and replay execution itself (S6's scope).
  Full record: [`docs/archive/v2-session-records/s5.md`](archive/v2-session-records/s5.md).
- [x] **S6** — 2026-08-25. Unattended execution: `promoteAndReplayRecipe()`
  replays the recorded pipeline through the user's own entry points, halts
  honestly at the first refusal/failure/cancel, prices certain refusals
  before the click (`ReplayPlanner`), holds the machine awake, and never
  mutates the recipe; seam `App/ReplayRun.swift`. Gate A ran as a six-finder
  review: 24 findings, 10 fixed in-session; 4 deviations. Track A: MCP
  `test_macos` 321/1; `unit` 320/1 after the vendored-dylib re-sign (both 1s
  the S17 sidebar intermittent). Not verified: everything on screen
  (F1.22–F1.23), a real multi-GB overnight, keep-awake vs actual sleep.
  Full record: [`docs/archive/v2-session-records/s6.md`](archive/v2-session-records/s6.md).
- [ ] **TB1**
- [x] **S7** — 2026-08-25. Error honesty on the new `App/SessionGates.swift`
  seam: physical iDPC takes the origin-fit gate, `DPC.integrateIDPC` throws
  typed errors (no zero images), tile errors attributed (`FullScanError`),
  the S5-F9 save-refusal gate, the wrapped caption + full provenance in PNG
  metadata, and the 28-site `try?` audit of Core/. Gate B (separate refuter,
  Opus): 12 findings, 11 fixed in-session; 3 deviations; the gate run also
  found and fixed two pre-existing S5-era runner breaks. Track A:
  `scientific` exit 0 (35 harnesses), MCP `test_macos` 336/2, `unit` 335/1
  exit 65 (the S17 intermittent; the /2 adds the retired UI target). Not
  verified: on-screen (F1.24–F1.27), the real NAS modal escalation, the
  demo-bookmark probe (TCC).
  Full record: [`docs/archive/v2-session-records/s7.md`](archive/v2-session-records/s7.md).
- [x] **S8** — 2026-08-25. Strain frame: owner decided scan frame, live-derived
  — stored map stays detector-frame; display/export re-express it from the
  CURRENT calibration (`Core/Analysis/StrainFrame.swift`), the frame said on
  all three carriers; seam `App/StrainProduct.swift`; fixture
  `tools/strain-frame-test`; #18 localized by instrumented diff, re-scoped
  to a 5-minute owner probe. Gate B (fresh Fable-tier refuter): 8 findings,
  6 fixed — two green-suite wrong-science mutations hid at the 90° test
  constant; 2 deviations. Track A: `scientific` exit 0 (36 harnesses), MCP
  `test_macos` 363/2, `unit` REFUSED by the preflight (exit 69, 7 GB free).
  Not verified: on-screen (F1.28/F1.29), a real rotation-calibrated strain
  session, the #18 owner probe.
  Full record: [`docs/archive/v2-session-records/s8.md`](archive/v2-session-records/s8.md).
- [x] **M1 — tidy session** — 2026-08-26 (maintenance, not release scope;
  brief archived: [`docs/archive/tidy-session-plan.md`](archive/tidy-session-plan.md)).
  T1 `tools/free-space.sh` (report by default, `--clear` deletes only its
  named debris behind a structural path guard; freed 5.9 GB → 14 GB free);
  T2 the S1–S8 records moved verbatim to
  [`docs/archive/v2-session-records/`](archive/v2-session-records/) with
  stubs above; T3 18 closed entries (312 lines out of the live file) moved
  verbatim to
  [`docs/archive/closed-items-2026-08.md`](archive/closed-items-2026-08.md),
  tombstones where live items lean; T4 CLAUDE.md rewritten to current truth
  (one canonical kickoff); T5 the S8 symmetric-constants lesson into
  `development-process.md` + the adversarial-review skill; T6 the
  resequencing line below; T7 the owed `unit` re-run — **360 passed /
  1 failed, exit 65**, exactly the S17 intermittent, no heights retrievable
  (terminal route, as recorded). Kickoff tax (CLAUDE.md + v2-release.md +
  open-items.md): **2409 → 1901 lines** (1838 before
  the Gate A findings were fixed back in; CLAUDE.md alone 261 → 235). **Gate A ran as an 8-finder +
  verify review: 8 verified findings, 7 fixed in-session** — the sharpest:
  the script's `du|sort` report died under `set -e` if a target vanished
  mid-`--clear` (empirically reproduced); `--clear` could delete an
  IN-FLIGHT run's temp directory against the header's own claim (now
  age-guarded >1 h + a do-not-run-during-builds caution); two archive links
  broke at the moved file's depth; a tombstone claimed gate unification
  "awaits S7's seam" when S7 shipped the seam and the real blocker is TB1's
  load-anyway decision; a live retarget-before-save residual and the
  #36/#43 tombstones had been dropped; the S2 stub manufactured a Track A
  claim its record never made; CLAUDE.md's aggregates are now dated to
  their own runs. 1 finding recorded to open-items with an owner (the
  shared temp-prefix/roots constant for producer and reaper). **Deviations,
  stated:** (1) T7's "only if T1 freed ≥ 8 GB" was read as "the 8 GB
  preflight floor is cleared" — T1 freed 5.9 GB but left 14 GB free ≥ the
  floor, and the brief's own expected-outcomes list anticipated the run;
  (2) T1 also clears workspace `DerivedData` — regenerable debris beyond
  the brief's parenthetical three (`state/`/`locks/` untouched); (3)
  relative links inside moved entries were re-based to the archive's
  location to keep their referents, stated in the archive header.
  `mac4DSTEM/` untouched; archived text otherwise byte-verbatim
  (machine-checked twice, independently by the Gate A reviewers).
- [x] **S10** — 2026-08-26. Reduced-file export: the cropped/binned-view
  refusal lifted behind real checks (frame refusals + the ellipse rescale
  the export always owed), derivation + recipe provenance stamped on the
  exported file, and the S6-carried frame mapping landed — a
  detector-reduced rehearsal now replays at full extent with re-expressed
  parameters, said on both carriers. Gate B (fresh refuter, live
  mutations): 8 findings, 4 fixed in-session — sharpest: the exported
  recipe mapped from the wrong frame after a promote (fixed by the
  `exportableRecipe` frame guard); two surviving mutations became tests;
  4 deviations. Track A: `scientific` exit 0 (**37 harnesses**), `unit`
  376/1 exit 65 (the S17 intermittent), MCP `test_macos` 378/1, zero
  warnings. Not verified: on-screen (F1.30/F1.31), a multi-GB round-trip,
  the recorded restore-path frame hole.
  Full record: [`docs/archive/v2-session-records/s10.md`](archive/v2-session-records/s10.md).
- [ ] S9 — when NAS access and disk allow
- *Resequenced 2026-08-26 (M1/T6): S10's dependencies (S5, S8) are met;
  chosen order **S10 → S21 → S17**; S9 when NAS access and disk allow; TB1
  sittings 2–4 whenever the owner sits.*
- [ ] S11 · [ ] S12 · [ ] S13 · [ ] S14 · [ ] S15 · [ ] S16 · [ ] **TB2**
- [ ] S17 · [ ] S18 · [ ] S19 · [ ] S20 · [ ] S21

Tick a session only with a record of what shipped and what deviated. Since
M1 (2026-08-26): the full record goes **verbatim** to
`docs/archive/v2-session-records/s<N>.md` and §9 keeps a ≤ ~12-line stub —
date, ship statement, gate + outcome, deviation count, Track A exit codes,
"not verified" in one line, archive pointer. Closures leave
`docs/open-items.md` for the dated closed-items archive, a tombstone staying
only where something live leans on them.
