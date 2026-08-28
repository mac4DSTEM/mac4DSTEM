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
   awake.

   > **Correction, 2026-08-28 — the word "overnight" is now ahead of the
   > evidence.** Done criterion 3 was narrowed the same day (owner decision) to
   > a bounded unattended run on a multi-GB cube, because the owner will not be
   > running overnights. The *capability* is unchanged — sequential replay at
   > full extent, keep-awake asserted, honest halt on failure — but nothing
   > will have been verified across a multi-hour idle, a display sleep or a lid
   > close. **Either the release verifies an overnight before shipping this
   > sentence, or the sentence says "unattended" instead of "overnight".**
   > S19 owns the restatement; this note exists so the choice is made
   > deliberately and not by nobody noticing. New scope, decided 2026-08-18: without it, promotion at 60 GB means
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
2026-08-18 — the threshold is unmeasurable on one machine; ~~manual
load-into-memory stays~~ — **see the correction below**; the mechanism stays in
the code and `.automatic` can return when a second-machine sweep makes a
threshold defensible). A visible promote control.

> **Correction, 2026-08-27 — "manual load-into-memory stays" describes a
> capability that was never built.** The decision above is left as recorded; only
> this clause is wrong, and it is wrong under every option. What stayed is the
> `.resident` *enum case* and the admission mechanism, exercised by
> `tools/virtual-detector-residency`, `tools/residency-sweep` and
> `mac4DSTEMTests/DatasetResidencyTests`. **No shipping control requests it:**
> `DatasetResidency.mode` is `.streamed` (`App/DatasetResidency.swift:34`), its
> only mutator `request(_:on:)` has **no caller under `mac4DSTEM/`**, and
> `AppState.preloadResidentCube()` says so in its own comment
> (`App/AppState.swift:2701-2703`). The app always streams. Three reviewers
> independently hunted for a missed route — menus, launch arguments, defaults,
> environment, replay/recipe/sidecar, the promote run, the configurator,
> `#if DEBUG`, URL schemes — and closed all of them.
>
> This matters because it is the sentence a later session scopes from, and it
> sits in the *product* paragraph of a workstream titled "close the load
> pipeline as a product". It has already cost two Track B rows: **F1.1**
> (withdrawn 2026-08-18) and **F1.36** (withdrawn 2026-08-27), both queued ahead
> of an affordance that does not exist, plus the stage-table row that generated
> them (struck the same day).
>
> **Whether to ship a control, or to restate residency as harness-only
> infrastructure, is an open owner decision** — the options and their costs are
> in the S18 session record. Nothing about it blocks the cut line: §3 already
> defers `.automatic` and the second-machine sweep to post-v2. The promote run (replay record + unattended execution). The
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
the severable block — **S11 landed 2026-08-28, so what is actually severable
now is S12–S16 + TB2**, and S11's `power_radial` finding goes with them: cutting them to a fast v2.x weakens no other workstream
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
3. **A real rehearse → promote completed UNATTENDED on a multi-GB cube**, over
   a bounded window, machine held awake, with the morning-summary path
   exercised and a failure made to halt honestly.
   **Narrowed 2026-08-28, owner decision.** This previously read "a real
   rehearse → *overnight*-promote … driven once by the release owner end to
   end". The owner will not be running overnights, and the honest response is
   to narrow the criterion rather than to claim a run nobody made. What this
   version does NOT establish, and what §1's wording and the README must
   therefore not imply: behaviour across an actual multi-hour idle, a display
   sleep, or a lid close. **If the claim says "overnight", that is the sentence
   to change** — S19 owns restating it.
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
| S9a | **Never silently allocate, whatever the volume.** Bound the tile budget by *free* RAM, refuse or stream rather than allocate a file-sized buffer, and re-examine the "GPU budget" label (`LoadConfiguratorView.swift:255`). **Split out 2026-08-28** because it needs no NAS and no 17 GB of free disk, and because it is right on every user's hardware regardless of what killed this one machine. **It is NOT the fix for the 8 GB death** — it is a guard that would have prevented it; the diagnosis still owes S9b, and this row must not be written up as closing it | A | — | Runs any time |
| S9b | **The 8 GB death — the diagnosis.** Local-vs-NAS `footprint` experiment on the 17 GB DM4 (predicted: local flat, NAS climbs toward file size ⇒ `.mappedIfSafe` fell back to a full read). **The "local" arm may be an external SSD** (owner, 2026-08-28) — it is a real filesystem, so `mmap` behaves as it does locally and the contrast with a network share is preserved; reading it in place also removes the disk constraint that has blocked this row. The NAS arm still needs the NAS, and without both arms there is no discriminator | **D** | NAS access | |
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
| S19 | **Claims restatement.** README/CHANGELOG to what a reader can reproduce; `docs/releasing.md` gains `make-dmg.sh`; `LSMinimumSystemVersion` → 26 — **and `MACOSX_DEPLOYMENT_TARGET`, which is still `14.0` in FOUR configurations of `mac4DSTEM.xcodeproj`. Partly pre-empted 2026-08-28:** `README.md` now says macOS 26 or later and `CHANGELOG.md` records that v1.0.0's declared 14 floor was never tested below 26, so docs and binary currently disagree in the safe direction. S19 closes the gap by raising the build setting; until then the DMG still installs on macOS 14 | A | S17, S21, green `all` | The CI badge from S21 becomes part of the restated claim |
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
- [~] **TB1** — **sitting 1 COMPLETE 2026-08-27; sittings 2–4 still owed.**
  The blocker that held sitting 1 open for nine days is gone: **F1.3b
  diagnosed under Gate D and fixed** — inside SwiftUI's sheet the hosted
  `MTKView`'s `CAMetalLayer` sits at `contentsScale == 0`, and a layer at
  scale 0 cannot display a drawable while `drawableSize`, `currentDrawable`
  and the uploaded texture all read healthy. Fix:
  `MetalImageView.ScaleAwareMTKView`. 5/5 green cold opens against a 3/3 red
  matched control; three narrower repairs ablated to red. **A second defect
  surfaced once the panes drew:** `dccc2f5`'s letterbox was computed and never
  applied — the code, its comment and its open-items entry all asserted a
  `.frame` nobody had written, and it could not be checked because F1.3b hid
  it. Both fixed. **Rows driven and PASSED:** F1.3b, F1.3c (re-run against a
  drawn pane — the crop half, the last place a silently wrong crop could hide),
  F1.3d in full, F1.3e, F1.6, F1.16. **F1.17's clipping half FAILS again**
  (finding, not fixed — eval-only). **Queued:** F1.37 (the letterbox shrank the
  scan pane's hit target) and F1.38 (the fix touches every image surface; one
  workspace checked). **Gate D + Gate B:** the pre-registered diagnosis was
  refuted by its own discriminator before the right one was found, and a
  separate refuter then supplied the causal leg the evidence lacked (scale 0 is
  *sufficient* to reproduce the symptom in plain AppKit; a wrong-but-nonzero
  1.0 renders fine) while refuting three claims — the stated origin of the 0
  (a detached layer reads 1.0, so what writes the 0 is still **unknown**),
  "perfect correlation across every run" (one run), and the repair chronology.
  All corrected in place, in four files. **Track A on the shipped tree:**
  `unit` **387 passed / 4 skipped / 0 failed, exit 0**; `scientific` exit 0
  (**37 harnesses**, zero FAIL lines, grepped not tailed); build zero warnings.
  One `unit` run refused mid-session with **exit 69** (the S0 preflight — my own
  scratch DerivedData; cleared and re-run green) and one reported a spurious
  failure because the app was running against the same defaults domain during
  the gate — both recorded in `docs/open-items.md`. **Not verified:** sittings
  2–4 (sidecar, promote, multi-GB, clean account), F1.8, F1.37, F1.38, and what
  writes the 0.
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
- [x] **S9a** — 2026-08-28. The tile budget now takes the lesser of the GPU hint
  and `physicalMemory / 24`, holding the three-tile peak near 12% of RAM.
  Measured on the 8 GB M3 the death happened on: per-tile **683 → 341 MB**,
  three-tile peak **2048 → 1024 MB** — the old figure matching this entry's
  own ~2.0 GB prediction exactly. **PHYSICAL, not free, memory is the bound**
  (owner decision): tile size sets float-partial grouping and the tiled reducers
  are order-dependent in their low bits, so a free-memory bound would make the
  numbers depend on what else was running; free memory is for refusing only.
  The misleading "GPU budget" row is now "GPU working-set limit" with a caption
  saying it is hardware, not an allowance. Gate A. Track A: `scientific` exit 0
  (38 harnesses), `unit` 387/4/0 exit 0, build zero warnings.
  **Not verified:** the label on screen (**F1.39**), and the perf cost —
  `tools/performance-baseline` pins `maximumTileRows` in every tiling benchmark,
  so it cannot see the default budget at all. **S9a is explicitly NOT the fix
  for the 8 GB death**; that diagnosis is still S9b's.
  · [ ] **S9b** — the local-vs-NAS diagnosis, still gated
  on NAS access (the local arm may be an external SSD)
- *Resequenced 2026-08-26 (M1/T6), completed 2026-08-27:
  **S10 → S21 → S17**. S9 waits for NAS access and disk; TB1 sittings 2–4
  run whenever the owner sits; S11 follows TB1.*
- [x] **S21** — 2026-08-26. CI on the public repo, authored:
  `.github/workflows/ci.yml` (`unit` + the full `scientific` array on
  `macos-26`, every push/PR, exclusions and red-run caveats stated in the
  file), `tools/lib/py4dstem-ci-constraints.txt` (the parity env's 20 pins),
  the README badge, the CLAUDE.md placement row. Gate A (4 finders + 1
  verifier, all separate agents): 9 findings (7 CONFIRMED / 2 PLAUSIBLE),
  all 9 fixed in-session — sharpest: Xcode 26's Metal toolchain is a
  separate download neither job installed. 2 deviations. Track A: `unit`
  376/1 exit 65 (the S17 intermittent, logged), YAML + constraints + vendored
  `pip` metadata all parse locally. **Activated the same day** (owner
  pushed; runs #1–#2): `scientific` green twice — the parity gate's first
  passes off the dev Mac; run #1 caught a real Xcode-26-only type-checker
  failure (fixed, `5f98ded`); run #2's sole red is the S17 intermittent,
  **reproduced on the runner** — the first second-machine observation
  (logged in open-items). At S21 closeout the badge was red on exactly that
  documented test; S17's local workflow change has not yet had its first
  runner observation. Not verified: the legend decomposition on screen;
  measured heights from CI.
  Full record: [`docs/archive/v2-session-records/s21.md`](archive/v2-session-records/s21.md).
- [x] **S17** — 2026-08-27. Sidebar intermittent: the persisted Display
  disclosure reproduced the historical 1029/945/961pt failure triplet
  exactly; both layout suites now inject private AppStorage and the numeric
  gate says default-collapsed explicitly. Collapsed uncalibrated Prepare is
  formally quarantined as one dynamic skip with CI-exported geometry; both
  disclosure states remain measured and have specific Track B rows. Gate D:
  the first timing diagnosis was refuted, the separate reviewer refuted the
  threshold-only account, then confirmed the controlled discriminator; the
  negative control failed as required. 0 deviations. Track A: `unit` exit 0,
  **378 passed / 4 skipped / 0 failed**. Not verified: Track B, macos-26 CI,
  the badge, `all`, living-board republish. Full record:
  [`docs/archive/v2-session-records/s17.md`](archive/v2-session-records/s17.md).
- [x] **S11** — 2026-08-28. Leads triage, all five items answered in writing
  against `b15ac0b`; every verdict and its evidence is in `docs/open-items.md`,
  under the external-review section (the table) and *Known, scoped, not
  blocking* (the five entries). **3 CONFIRMED, 1 confirmed-but-already-known,
  1 partly dismissed, and the bounds sweep DISMISSED.** Sharpest, and new:
  **`.fileMean`/`.sessionMean` leave `calibration.origin` nil, so
  `calibratedBraggVectors` silently substitutes the detector's geometric
  middle `(qx/2, qy/2)` for the file's recorded beam centre** — in Q
  calibration, strain, ACOM and the Bragg map at once, stamped
  `.measuredInApp`, while the inspector displays the file's origin. Four
  sibling call sites derive that same fallback three different ways; the S7
  class, not a slip. Owners assigned: **S13** (origin fallback, strain
  weighting provenance), **S12** (single-shell Q estimator), **S16**
  (`power_radial`, which leaves with the severable block if it is cut). Gate:
  B-lite, **and its second read has NOT run** — see below. Track A: not run,
  and not owed — nothing under `mac4DSTEM/` was touched. Deviations: 1 — no
  `docs/archive/v2-session-records/s11.md`, because the open-items entries are
  the record and copying them would create the second summary this repo keeps
  getting burned by. **Not verified:** the materiality of `power_radial` (the
  ground-truth driver behind `docs/py4dstem-pipelines.md` §10.1's table was not
  retained), and no failing case was *demonstrated* for the origin fallback —
  it is read from the code path, not from a red test.
- [ ] S12 · [ ] S13 · [ ] S14 · [ ] S15 · [ ] S16 · [ ] **TB2**
- [x] **S18** — 2026-08-27. Polish sweep, the brief's list complete. Shipped:
  one shared `PaneBottomOverlay` (wide case unchanged on purpose), #38's scroll
  monitor scoped by event-time geometry instead of a remembered hover, the
  sidebar dataset card given axis labels, the comparison pane's literal
  `contentVersion: 0` replaced by a payload hash that folds RGBA bytes in,
  `pattern(ry:rx:)` served from the resident cube, and the four tiled reducers
  bound at the tile's byte offset (`TileGPUSource` + `cubeOffset:`) with the
  tiling deliberately unchanged so results stay bit-identical. #37 measured
  (streaming bound 5.4 ms/tile, resident 13.2 ms) — the check granularity is not
  the cost, so **#37 moved to S9** as an I/O item.
  **Three reviews ran.** Gate A (14 agents): code passed, 2 findings, both in
  the session's own documentation — Track B row **F1.36 could not pass on any
  dataset** (it named a control that does not exist; withdrawn, F1.1 class) and
  F1.32 quoted its thresholds against the pane rather than the fitted image box.
  A Gate B **mutation sweep** ran (30 mutations applied): **no mutation produced
  a wrong number from the code** — 12 red, per-call-site sensitive — and it
  demonstrated 3 instrumentation blind spots, all now closed and each broken
  before being trusted. **But the Gate B SECOND READ of the two `Core/` changes
  did NOT run, and this stub said it had.** Corrected 2026-08-28 against S18's
  own record, whose *Not verified* section states it plainly: that session was
  configured not to spawn agents, so the model that wrote items 5 and 6 is still
  the only one that has approved them — the one thing the refusal rule forbids.
  The mutation sweep is evidence, not a second reader. **RAN 2026-08-28 — and both
  changes SURVIVED it.** Twelve mutations across the two, each producing a red
  harness with a distinct named failure; the debt is cleared. It also found that
  the shipped fixture was blind to cropped views (mutating the pattern slice's
  stride stayed green across all 27 assertions), which is now closed by the new
  `tools/resident-cropped-view` harness — `scientific` is 38. Full outcome, and
  what is still not established, in `docs/open-items.md`. *(This line previously read "Gate B (24 agents, 30 mutations
  applied and run)". The record has a `Gate A — 14 agents` section and no Gate B
  section; the agent count was not supported by it. On 2026-08-27 a session
  found this stub disagreeing with CLAUDE.md and resolved it the WRONG way —
  in favour of this stub, because it looked like the one carrying evidence.
  Checking the primary record instead of the two summaries would have settled
  it in a minute, and that is the lesson: §9 is a stub, the session record is
  the evidence.)* A commissioned residency audit found
  **§2 W1's "manual load-into-memory stays" is false** (annotated above; the
  product decision is the owner's) and struck the L2 stage row that generated
  both withdrawn Track B rows.
  **Track B, driven by the assistant** (Screen Recording + Accessibility):
  F1.32 PASSED both halves; **F1.34 FAILED, was fixed, and re-verified on
  screen** — the axis labels truncated, so `(Qx × Qy)` never rendered, while all
  384 tests stayed green because they measure height and column fit and
  truncation changes neither. The first fix did not work; only rebuilding and
  looking caught that.
  Track A: `unit` **384 passed / 4 skipped / 0 failed, exit 0**; `scientific`
  exit 0 (37 harnesses); build zero warnings. 5 deviations.
  Not verified: F1.33 and F1.35 (owner), the `mac4DSTEMUITests` deletion
  (environment refused), `all`, #37 against a real reader.
  Full record: [`docs/archive/v2-session-records/s18.md`](archive/v2-session-records/s18.md).
- [x] **S19** — 2026-08-28. Claims restatement. `run-tests.sh all` run end to
  end on the current tree: **exit 0, 40 harnesses, zero FAIL lines, zero exit-69
  refusals, unit 387/4/0**, counted by grep over the retained log. `README.md`
  now states that reproducible figure and says plainly what the numerical gate
  does NOT cover (what the app draws — pointing at Track B, which exists because
  the gate stayed green through real on-screen defects). `CHANGELOG.md` keeps
  v1.0.0's 30-harness numbers as that release's record with a pointer to the
  current ones. **The macOS floor is closed properly:** `MACOSX_DEPLOYMENT_TARGET`
  raised 14.0 → 26.0 in all **six** configurations (an earlier note said four —
  a truncated grep), verified from the BUILT product rather than the setting:
  the app's `Info.plist` declares `LSMinimumSystemVersion 26.0`. Docs and binary
  agree again, closing the ROADMAP item that had recorded since August that the
  app had never run on the floor it declared. `docs/releasing.md` gains the
  `make-dmg.sh` step, which was missing entirely — the one artefact users
  actually download had no written procedure — including the order that matters
  (staple the app, build the DMG, notarize the DMG). Gate A.
  **Not verified:** the CI badge against this tree (S21's workflow has not run
  since); no clean-account launch on macOS 26 (S20); and the DMG procedure is
  documented, not re-executed.
- [ ] S20

Tick a session only with a record of what shipped and what deviated. Since
M1 (2026-08-26): the full record goes **verbatim** to
`docs/archive/v2-session-records/s<N>.md` and §9 keeps a ≤ ~12-line stub —
date, ship statement, gate + outcome, deviation count, Track A exit codes,
"not verified" in one line, archive pointer. Closures leave
`docs/open-items.md` for the dated closed-items archive, a tombstone staying
only where something live leans on them.
