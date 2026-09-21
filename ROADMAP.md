# mac4DSTEM roadmap

Imported 2026-09-03 from the "mac4DSTEM v3 Themes" artifact of 2026-08-28
(seven parallel surveys of the pinned py4DSTEM source against `Core/`: 166
findings, 45 high-value gaps, 77 absent, 54 partial, 7 absent by recorded
decision; the ranking is a recommendation, sizes are rough). The first v3
feature to land bumped the version to v3.0.0, released 2026-09-11
(`docs/releasing.md` § Releases).

## Decided 2026-08-28

Recorded in full at `docs/decisions/031-v3-sequencing.md`.

1. **v3 is a sequence, not a bet.** Order comes from two scarce resources —
   one Gate B campaign in flight, the owner's driving time — plus dependencies.
2. **Grain segmentation and multi-phase ship together** — segment the
   grains, then identify each one's phase.
3. **The notebook exports the recipe as py4DSTEM code, no comparison** — a
   translation, with an inline `DEVIATION` note at each step.
4. **Materials Project as an importer that embeds** the fetched structure in
   the session sidecar with its provenance, so recipes reproduce offline.
5. **Precipitates enter v3 as a design session, implementation unscheduled**
   — a per-object result, its export/sidecar life, and what density refuses without a denominator.
6. **A run layer (`AnalysisRunner` with an injected host)** is the recorded
   next consolidation item, unscheduled; run functions stay on `AppState`.

## Parity themes

Ranked by value to a working microscopist.

| # | Theme | Absent today | Size · depends on |
|---|---|---|---|
| 1 | **Calibration foundation** — everything else stands on it | **Landed 2026-09-17 as v3.1** (`docs/v3-features.md#calibration-v31`): vacuum probe from a separate scan, beamstop-tolerant origin (`get_origin_friedel` + beamstop mask), origin validity mask (count on screen; the spatial overlay is still owed). The CoM beam centre in `probeSize` is parked (Gate D: marginal). Unverified on screen until the owner drives it. | done · drive + `all` gate + v3.1.0 cut owed |
| 2 | **Amorphous and nanocrystalline** — a modality the app lacks | polar / polar-elliptical transform (gates the rest); radial profile I(q); pair distribution function (scattering factors already ported); radial variance / fluctuation microscopy | large · polar transform first |
| 3 | **Strain where disk detection fails** — the peak-finding path finds no basis on three of four training datasets (`py4dstem-pipelines.md` §9.2/§10.3) | whole-pattern fitting; user-supplied reference lattice (absolute strain); strain from the ACOM solution | medium–large · — |
| 4 | **From maps to the numbers a paper reports** | grain segmentation (size distribution, boundary misorientation, twin fraction); multi-phase identification (which phase is where); full point-group coverage | medium · point-group coverage first |
| 5 | **Interoperability** | read a native py4DSTEM EMD (probe, Bragg vectors, calibration); the notebook export | medium · pinned py4DSTEM env exists |
| 6 | **Detector realism** | per-position detector shift (the origin map exists); arbitrary detector masks (the GPU path takes a weight image); hot-pixel filtering; ARINA reader, MIB packed modes | small each · — |
| 7 | **Phase-contrast depth** | direct ptychography (SSB / OBF / WDD); mixed-state; probe-position correction | large · — |

**Calibration foundation (theme 1) — pre-registration, v3.1.** Sequenced
least-risk first (Gate B capacity is one campaign at a time). The **origin
validity mask leads** (owner, 2026-09-17): surface the per-position `kept` mask
the robust origin fit already computes and discards, completing the 2026-08-28
admit-with-fraction decision from a scalar to a spatial map — disclosure only,
no shipped number moves, a unit gate. **Landed 2026-09-17:** item 1 (mask + D4
count + step-3 measured); the CoM centre in `probeSize` **diagnosed and parked**
(marginal, two-sided); and **`get_origin_friedel`'s Core algorithm ported**
(`FriedelOrigin.swift`, beamstop-tolerant, opt-in/additive) with a gated parity
harness at ~1e-6 px against py4DSTEM, `get_beamstop_mask` ported (pixel-identical to
scipy on the real Au_ref beamstop cube) and **wired as an origin-method picker**; and
the **vacuum probe from a separate scan** (a "Vacuum Scan…" probe source). **All four
Calibration-foundation items landed 2026-09-17** (item 2 parked as marginal); the UI
additions are unverified on screen. Full registration:
[`docs/v3-features.md#calibration-v31`](docs/v3-features.md#calibration-v31),
decision [`docs/decisions/033-v3.1-origin-validity-mask.md`](docs/decisions/033-v3.1-origin-validity-mask.md).

**Theme 4's point-group coverage is also a Materials Project dependency, not
only a grain-segmentation one** (found 2026-09-19). Today's
`ACOMCrystalSymmetry` implements exactly two point groups by hand in Swift —
cubic and hexagonal — so a live Materials Project connection (item 4 above)
will hit the "can identify, can't orientation-map" wall far more often than
today's curated CIF imports do; py4DSTEM is no more general by default
(its own built-in plotting is cubic-only too — full coverage there needs
the external `orix` library, which Swift has no equivalent of). **Both
items are pre-registered together, next session:**
[`docs/v3-features.md#materials-project`](docs/v3-features.md#materials-project).

## Beyond py4DSTEM — the differentiators

All requested by the owner; all out of v2 by the 2026-08-18 decision ("each
is its own product").

- **Needle-shaped precipitate pipeline** (2026-08-06, re-requested
  2026-08-26) — per-object, real-space segmentation driving per-object
  analysis and a calibrated-area density; a per-object result is not a map,
  which is the expensive part to get wrong. **Superseded 2026-09-11**: the
  route is no longer real-space segmentation but classifying each scan
  position by its full diffraction pattern
  (`docs/v3-features.md#precipitate-classification`, `docs/decisions/019-precipitates-by-classification.md`).
- **EDX correlation** (2026-08-26) — a data-model change before a feature: a
  second signal with its own reader and units, registered onto the scan grid
  with the transform recorded. Unclaimed.
- **Live acquisition · copilot** — named, nothing designed. Unclaimed.
- **Settings window, Xcode-style sidebar** (owner, 2026-09-21) — grows the
  scene the Materials Project key opened. Sections: *General* (what Open
  Dataset does by default, sidecar location, keep the Mac awake during long
  runs, clear recents); *Appearance* (theme System / Light / Dark, default
  colormap for maps and for diffraction, log or linear intensity by default,
  scale bar, inspector density); *Analysis* — machine knobs only: streaming
  memory budget, engine preference, whether the learned detector is offered;
  *Materials Project* (key, last fetch); *Advanced* (log verbosity, reveal
  the log, reset). **Never a threshold, radius or floor** — those are
  properties of a dataset and live in the session (ADR 029). State owner:
  one `AppPreferences` over `UserDefaults`, injectable for tests; the
  scene is a `NavigationSplitView` (allowed), never a split view. **Landed
  2026-09-21** (`900fe7b`), unverified on screen.
- **Bottom area as a second workspace, Xcode-style** (owner, 2026-09-21) —
  the bar above the log gets real height and live numbers (step, positions
  done / total, patterns per second, MB streamed, ETA, residency), and can
  be dragged up as far as the user wants to reveal a second central area:
  the log today, the lineage graph when it exists (side by side or one at
  a time — undecided). Builds on the log's existing dragged height
  (`LayoutPolicy`); must stay a SwiftUI drag-resized area, never
  `VSplitView` (decision 009). Inspector to follow Xcode's label-column
  form; the Phase mapping room is the trial. Unclaimed, unscheduled.
- **Lineage graph with real rewind** (owner, 2026-09-21) — every derived
  product shows its inputs as a graph, and clicking a node rewinds the
  parameter state, not a text history. Nothing exists today beyond the
  linear `SessionReplayRecord` and per-product provenance; a record with
  step ids and input edges (a sidecar wire-format decision, owed) comes
  first, a lineage list in Results second, the graph view only after the
  drive row is empty. Unclaimed, unscheduled.
- **Learned disk candidates** (owner, 2026-09-05; Core ML on the Neural
  Engine, 2026-09-07) — the first ML feature.

**Learned disk candidates — pre-registration.** A second `DetectorClass`
beside the classical one: a Core ML U-Net paints a disk-centre heatmap on
the Neural Engine, and the existing correlation/centroid refinement measures
each candidate to sub-pixel; opt-in, off by default. **Verdict (step 3):
passed 2026-09-08** — on the frozen hand-labelled test set the net finds the
same real disks with far fewer inventions (256 px: 0.667 / 0.840 against the
classical 0.487 / 0.485). Full pre-registration:
[`docs/archive/v3/learned-detector-preregistration-2026-09-07.md`](docs/archive/v3/learned-detector-preregistration-2026-09-07.md).

## Leave alone; where the app is ahead

Not chased: py4DSTEM's visualization layer, `utils/` helpers for their own
sake, `.automatic` residency (needs a second machine). Ahead of py4DSTEM and
part of the product story: the load-specification and promote workflow,
provenance that survives export and reopen, refusals that name what failed,
the session sidecar as a sharing unit.

## Next planned sequence — registered 2026-09-19

1. **Release v3.1.0:** the three acceptance cubes are restored; run `all` and the archive rehearsal before the credentialed cut. Full-cube Friedel bar/ETA remains an on-screen check, not a gate. No feature slips in.
2. **Materials Project importer:** build the pre-registered, user-initiated importer with offline provenance; settle its UX choices before UI code.
3. **Orientation coverage:** prepare monoclinic 2/m first if the owner confirms it; it unlocks β″ and is a separate Gate D/B feature.
4. **Scientific debts and phase validation:** diagnose R–Q; decide T1 and Parallax experiments; use the paper truth set before detector or learned-model work.

## How a v3 feature is done

Each feature is pre-registered the way the train's steps were (plan §9–§11 of
the archived v2.5 plan are the models): what it touches and which owner holds
its state, the tests written before, the decisions owed to the owner. Built on
the packages and sessions, one Gate B campaign at a time, `/pickup` with the
feature named.
