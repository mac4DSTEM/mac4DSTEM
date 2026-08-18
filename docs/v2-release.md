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

**W5 — Verification debt and release mechanics** (S17–S20). The sidebar
intermittent diagnosed or honestly quarantined, claims restated to what a
reader can reproduce, the polish sweep, floor raised to macOS 26, then the
full release pipeline.

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
| S2 | **The two-spec analysis fixture** (`tools/` name at build time; goes into `scientific`). Virtual image + disk detection under a reduced spec vs full extent. Ground truth is the **full-extent run on the overlap** — never cropped-vs-cropped. Scan-crop cases compare exactly; detector-crop/bin cases compare through re-referenced coordinates; **each case states which invariance it claims**. Also close the L3 residual: exercise `FourDArray.tile(yRange:from:)` at `lowerBound > 0` | **B** | — | Parallel with S1 |
| S3 | **Drop `.automatic`** from model and UI (behaviour is unchanged — it already streams); build the **promote control** ("reopen at full extent", placement decided in-session). Seam | A | S0 | Parallel with S4 |
| S4 | **Configurator finish.** `contentVersion` value-dependence first (`LoadConfiguratorView.swift:142`, `DatasetInspector.swift:230`), then the single-DP picker + real-space dims (owner requests, 2026-08-18), the sheet clipping (`:44`), the missing `progress:` argument (`AppState.swift:1487-1490`) | A | S0 | Parallel with S3 |
| S5 | **Promote run I — the replay record.** Which analyses ran, with which parameters, serialized with the session — this is what turns the sidecar into a full recipe, and it is a sidecar format change (§5 evidence; the minimum-reader marker is decided here) | B-lite | S3 | Round-trip fixture extends `tools/load-spec-roundtrip` |
| S6 | **Promote run II — unattended execution.** Sequential replay at full extent, keep-awake assertion, morning summary. A failed step **halts honestly** — it must never continue silently past a failure | A | S5 | Track B row queued |
| TB1 | **Owner pass:** F1 queue to empty (F1.3b re-drive first), the promote row, one real rehearse → overnight promote, the colleague-sidecar row (foreign sidecar, clean account), the aspect-stretch decision once previews draw | — | S1, S3–S6 | Agent continues W2 meanwhile |
| S7 | **Error honesty.** iDPC gate consults `originFitIsQuantitative` (`AppState.swift:3806`); `DPC.integrateIDPC` returns a typed error instead of a zero image; tile-read errors attributed correctly (`TiledDiskDetection.swift:42`); caption truncation fixed | **B** | — | Parallel with TB1 |
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
| S18 | **Polish sweep.** Colorbar/scale-bar collision, #38 scroll monitor, the scan-extent two-orders display, comparison-panel `contentVersion` (`ProductWorkspaceViews.swift:719`), `pattern(ry:rx:)` honouring a resident cube, #37 re-measure | A | late | Bounded: this list, nothing more |
| S19 | **Claims restatement.** README/CHANGELOG to what a reader can reproduce; `docs/releasing.md` gains `make-dmg.sh`; `LSMinimumSystemVersion` → 26 | A | S17, green `all` | |
| S20 | **Endgame.** Version number decided on §5's evidence; `/code-review ultra` on the release branch (owner triggers); `/security-review`; sign → notarize → staple; clean-account launch; full Track B standing pass A–F; tag | — | everything | |

**Owner-decision moments, so they never ambush:** TB1 and TB2 (driving time),
the strain-frame choice (S8), the aspect-stretch decision (TB1), the S12
design review, the WS₂ variant confirmation (S14), the version number (S20).
Everything else runs on the decisions recorded in this file.

**Sizing, honestly:** ~20 agent sessions plus two owner passes and the
endgame. The severable block (S11–S16 + TB2) is 6 sessions + one pass; the
binding core is ~14.

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

- [~] **S0** — docs written 2026-08-18; free-space preflight outstanding.
- [ ] S1 · [ ] S2 · [ ] S3 · [ ] S4 · [ ] S5 · [ ] S6 · [ ] **TB1**
- [ ] S7 · [ ] S8 · [ ] S9 · [ ] S10
- [ ] S11 · [ ] S12 · [ ] S13 · [ ] S14 · [ ] S15 · [ ] S16 · [ ] **TB2**
- [ ] S17 · [ ] S18 · [ ] S19 · [ ] S20

Tick a session only with a one-line record of what shipped and what deviated,
same convention as the load-pipeline plan's §5.
