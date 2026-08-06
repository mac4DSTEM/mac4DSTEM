# Phase 2 — planning draft

**Status: DRAFT for a dedicated planning session. Nothing here is decided.**
Written 2026-08-06, immediately after the `v1.0.0` tag, so the session can react
to concrete proposals instead of starting from a blank page. Every section ends
with a recommendation; the session's job is to accept, change, or reject each
one and then move the settled parts into their permanent homes
(`docs/v2-scope.md`, `docs/development-process.md`, `ROADMAP.md`).

---

## 1. Phase name vs version number — keep them separate

These are independent axes and conflating them causes bad version numbers.
"Phase 2" is how much work it is. Semver is about **compatibility**.

| Ships | Version | Why |
|-------|---------|-----|
| Developer ID signing, notarization | none, or `v1.0.1` | Changes no source; can be a release built from the existing tag |
| Load pipeline (L2–L5): resident cube, crop/bin on open | **`v1.1.0`** | Features, backward compatible |
| L6, *if* crop/bin provenance changes the session sidecar or export format so `v1.0.0` cannot read them | `v2.0.0` | A real break, and the only plausible trigger currently on the roadmap |

**Recommendation:** plan for `v1.1.0`. Decide the `v2.0.0` question *at L6*, on
the evidence of whether the format actually breaks — not in advance.

---

## 2. Testing — split the automation into two tracks

The core finding from the v1.0.0 endgame: **the numeric suite and the human eye
catch disjoint classes of defect, and the repo currently pretends the automation
covers both.**

Evidence, all from 2026-08-06:

- With all 30 harnesses green, ten minutes of manual use found two real
  defects — a colormap control absent from the only workspace that needed it,
  and a readiness row contradicting its own detail line.
- The QC playthrough has **never** produced screenshots. Every run to date used
  `--no-screenshots`, so its "visual acceptance" role has always been nominal.
- `QCPlaythroughUITests` never touches a disk-detection control — no
  `minRelative`, no `minPeakSpacing`, no correlation power — and records a peak
  *count* without judging it. A run that detects only the central beam produces
  a number and a green step. Verified by inspection.
- The harness can read a stale peak count (`polycrystal_2D_WS2`: 16,384 logged
  against the app's own later 213,441).

### Track A — numeric regression, headless, automated

Keeps doing what it is actually good at: exact numbers, parity against
py4DSTEM, and catching a change that moves a value it should not.

### Track B — visual acceptance, human, checklist-driven

For anything that changes what the app draws or where a control lives. The
model that worked: **the assistant writes a short checklist of what to open and
what to expect; the release owner runs the app once and sends screenshots.**

Roughly ten minutes of human time, and it outperformed 30 automated harnesses on
its own terms. It is also the only thing that can answer "are these detected
disks *right*?", which is a judgement, not a measurement.

**Recommendation:** adopt both tracks explicitly. Stop describing the QC
playthrough as visual acceptance — retask it as Track A and say so in
`CLAUDE.md`, which currently calls it "the acceptance test".

**Open question for the session:** is the XCUITest playthrough worth repairing
at all, or should Track A shrink to the numeric harnesses that already run under
`tools/run-tests.sh`? It is buggy, slow, and needs a Screen Recording grant it
has never had.

---

## 3. Dataset policy — two primary, two on demand

| Dataset | Role | Recommendation |
|---------|------|----------------|
| `sim_Au_data_all_binned` | Simulated, known answer. The parity anchor. | **Primary** |
| `downsample_Si_SiGe_exp` | Experimental. Where the real problems live — #46, #29 and #18 are all on this one. | **Primary** |
| `Particle_1…bin8` | Repeats Si_SiGe's failure mode at a different probe radius (≈10.6 px). | On demand |
| `polycrystal_2D_WS2` | Cannot reach ACOM without a WS₂ model (#11). | On demand — **and see the WS₂ CIF entry in `post-v1-ideas.md`**, which would change this |

This is a coverage argument, not a speed one: one clean simulated case and one
hard experimental case cover the two failure modes that matter, and the other
two mostly repeat them.

**Recommendation:** two primary; run the other two when a change plausibly
touches what makes them different.

---

## 3a. The workflow this is all actually for (release owner, 2026-08-06)

Stated in the owner's own terms, because it changes what the load pipeline is
*for* and it settles an open question in `load-pipeline-plan.md`.

**Today, with py4DSTEM.** Take a 50–60 GB dataset. Bin it in diffraction space
(bin 2 or 4) and work with the binned file **locally**, because that is fast and
convenient. Figure out the analysis there. Then take the notebooks to the HPC
and run the same analysis on the **full** dataset — which "usually involves
resetting values for the centre of the diffraction patterns, etc."

**The vision for mac4DSTEM.** Open the large dataset, load **only a subregion of
real space** *and* **binned diffraction patterns**, and do the analysis on that
reduced cube. Then re-run the same analysis on the **full** dataset — which may
take hours, overnight, or a stronger Mac, and that is fine, *because the
analysis was already validated on a representative subset*. Disk detection,
strain, orientation: known to work before the expensive run starts.

### Why this changes the design

The reduced cube is **not the deliverable**. It is a *rehearsal*, and the whole
value is that the rehearsal transfers. Three consequences:

1. **It answers `load-pipeline-plan.md` §7: a cropped/binned cube is a
   *view*.** If it were a new dataset, "re-run at full extent" would mean
   redoing the analysis from scratch, which is exactly the manual step the owner
   wants to stop doing. As a view, removing the specification *is* the promotion
   to full extent.
2. **The `LoadSpecification` must be a first-class, re-applicable object** —
   recorded in the session, carried in provenance, and separable from the
   analysis parameters so the same parameters can be re-run under a different
   specification. This is a stronger requirement than "load less data".
3. **Every parameter in detector or scan pixels must be re-referenced
   automatically when the specification changes.** This is the differentiator.
   py4DSTEM makes the user fix the centre by hand — the owner's "resetting
   values for the centre of the diffraction patterns" is precisely py4DSTEM
   defect #1 in §2 of the load plan. The parameters that move:
   - origin / centre (per-position fitted map — the hard one)
   - probe radius, `minPeakSpacing`, edge exclusion (detector pixels)
   - **absolute intensity thresholds** — binning *sums*, so these scale by
     `bin²`, which is the trap most likely to silently change a result
   - ellipse fit (detector coordinates)
   - Q pixel size (scales by bin factor)

### The product claim worth aiming at

> *An analysis validated on a cropped, binned view re-runs unchanged on the full
> dataset, with every calibration re-referenced for you.*

That is a genuine advantage over the reference implementation, it is testable
(same analysis, two specifications, compare), and it is what makes the app worth
using on a 60 GB cube instead of a notebook. It is also a plausible **end-of-v2**
target rather than a single stage — it needs L2 through L6 to be true.

---

## 4. Shrinking `AppState` — one seam per stage

`AppState.swift` is **4,064 lines**; `ContentView.swift` is 1,763.

Splitting into `extension AppState { }` across files is cosmetic: same mutable
state, same observable surface, every method still able to touch every property.
`ROADMAP.md` P3.2 already warns against it — *"Don't widen scientific-state
mutation access just to reduce line counts."*

Real decomposition = extract a responsibility **with its own state**, behind a
narrow interface. Precedent: `AnalysisOperationController` in `Core/Workflow/`.

The seams already exist as MARK sections:

| Section | ~Lines | Order |
|---------|--------|-------|
| Fit-verification overlays | 115 | **First** — presentation only, no scientific state; proves the pattern cheaply |
| DPC | 130 | |
| Strain mapping | 175 | |
| Disk detection | 215 | |
| ACOM | 260 | |
| Calibration | 760 | **Last** — owns `calibration` + `provenance`, which everything reads |
| *(unmarked, lines 1–1932)* | 1930 | State, loading, session, workflow. The real facade |

**Recommendation:** a budgeted rule — *every L-stage that touches `AppState`
extracts one seam before it lands*, at a green test boundary. Six stages, six
extractions, no big-bang refactor. As an aspiration this has lost to every
deadline so far; as a per-stage cost it ships.

**Decision owed:** `AppState` is `@Observable` and `@MainActor`. Either the
extracted type is itself `@Observable` and `AppState` holds it (cleaner; view
code changes), or `AppState` keeps thin forwarding properties (view API
preserved; less benefit). Choose deliberately.

---

## 5. Environment — stop losing hours to the machine

On 2026-08-06 three consecutive full-suite runs produced three *different*
failure sets, none related to the code, all caused by a full disk. They were
nearly diagnosed as real regressions.

Contributing facts: `xcodebuild test` writes a ~300 MB system log archive to
`/var/tmp` **per run**; `References/` is 3.3 GB, of which 3.0 GB is the training
datasets the scientific harnesses require; the machine is 256 GB and near full.

**Recommendation:** a preflight in `tools/run-tests.sh` that fails immediately
with "need N GB free, have M" rather than letting the suite fail in a way that
looks like a code defect. Cheap, and it would have saved an hour.

---

## 6. Practices to keep, because they demonstrably worked

1. **Adversarially review the *diagnosis*, not just the code.** Three times now
   a science-affecting fix passed every test written for it and was still wrong
   or narrower than claimed. On 2026-08-06 the review established that the #46
   gate's threshold is ~2× looser than the estimator's real failure onset — a
   finding the green suite could never have produced.
2. **A test written for a fix proves nothing until it fails without the fix.**
   Make the negative control mandatory, not customary. It caught a UI test that
   failed against the fix *and* the old code for an unrelated reason.
3. **One maintained status document.** `docs/open-items.md` as the only live
   list, with phase records frozen under `docs/archive/`. This scaled fine
   across v1.0 — 11 live docs, 5 archived — and is worth keeping.

---

## 7. What the session should produce

- `docs/v2-scope.md` — the scope contract, so "is this in scope?" has an answer
  the way `docs/v1-scope.md` provided one.
- The version policy from §1, recorded in `ROADMAP.md`.
- The testing and dataset policies from §2–§3, recorded in
  `docs/development-process.md`.
- The `AppState` rule and the `@Observable` decision from §4.
- **Resolution of `docs/load-pipeline-plan.md` §7's remaining open item:**
  is a cropped/binned cube a *view* of the original or a new dataset? The plan
  recommends *view* and is written for it, but it is unconfirmed — and L3 cannot
  start cleanly without the answer, because it determines session-restore and
  export behaviour.
