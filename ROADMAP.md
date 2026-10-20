# mac4DSTEM roadmap

Surveyed 2026-08-28 against the pinned py4DSTEM source (166 findings, 45 high-value gaps, 77 absent, 54 partial, 7 absent
by recorded decision; the ranking is a recommendation, sizes are rough). Releases are in `tools/release/README.md` §
Releases. What is live now is `docs/status.md`; this file is the forward plan.

## Decided 2026-08-28

Recorded in full at `docs/decisions/031-v3-sequencing.md`.

1. **Grain segmentation and multi-phase ship together** — segment the grains, then identify each one's phase.
2. **The notebook exports the recipe as py4DSTEM code, no comparison** — a translation, with an inline `DEVIATION` note at each step.
3. **Materials Project as an importer that embeds** the fetched structure in the session sidecar with its provenance, so recipes reproduce offline.
4. **Precipitates**: a per-object result, its export/sidecar life, and what density refuses without a denominator.
5. **A run layer (`AnalysisRunner` with an injected host)** is the recorded next consolidation item, unscheduled; run functions stay on `AppState`.

## Parity themes

Ranked by value to a working microscopist.

| # | Theme | Absent today | Size · depends on |
|---|---|---|---|
| 1 | **Calibration foundation** — everything else stands on it | **Landed 2026-09-17 as v3.1, shipped in v4.0.0** (`../_archive/mac4DSTEM/docs/v3-features.md#calibration-v31`): vacuum probe from a separate scan, beamstop-tolerant origin (`get_origin_friedel` + beamstop mask), origin validity mask (count on screen; the spatial overlay is still owed). The CoM beam centre in `probeSize` is parked (marginal). The spatial overlay stays owed. | done |
| 2 | **Amorphous and nanocrystalline** — a modality the app lacks | polar / polar-elliptical transform (gates the rest); radial profile I(q); pair distribution function (scattering factors already ported); radial variance / fluctuation microscopy | large · polar transform first |
| 3 | **Strain where disk detection fails** — the peak-finding path finds no basis on three of four training datasets (`../_archive/mac4DSTEM/docs/archive/qc-run-findings-2026-08.md` §9.2/§10.3) | whole-pattern fitting; user-supplied reference lattice (absolute strain); strain from the ACOM solution | medium–large · — |
| 4 | **From maps to the numbers a paper reports** | grain segmentation (size distribution, boundary misorientation, twin fraction); multi-phase identification (which phase is where); full point-group coverage | medium · point-group coverage first |
| 5 | **Interoperability** | read a native py4DSTEM EMD (probe, Bragg vectors, calibration); the notebook export | medium · pinned py4DSTEM env exists |
| 6 | **Detector realism** | per-position detector shift (the origin map exists); arbitrary detector masks (the GPU path takes a weight image); ARINA reader, MIB packed modes (hot-pixel filtering landed in Preprocess, 2026-10-01) | small each · — |
| 7 | **Phase-contrast depth** | direct ptychography (SSB / OBF / WDD); mixed-state; probe-position correction | large · — |

**Theme 4's point-group coverage is also a Materials Project dependency, not
only a grain-segmentation one** (found 2026-09-19). Today's
`ACOMCrystalSymmetry` implements exactly two point groups by hand in Swift —
cubic and hexagonal — so a live Materials Project connection will hit the
"can identify, can't orientation-map" wall far more often than today's
curated CIF imports do; py4DSTEM is no more general by default (its own
built-in plotting is cubic-only too — full coverage there needs the
external `orix` library, which Swift has no equivalent of). **The Materials
Project importer landed 2026-09-21** (decode/standardise/refuse a cell,
classify via the CIF importer's own function, Keychain key, mp-id sheet, 39
tests; `../_archive/mac4DSTEM/docs/v3-features.md#materials-project`) — shipped in v4.0.0;
a live fetch was tested 2026-09-23 (it worked); S6's comparisons owed. Point-group coverage beyond
cubic and hexagonal remains unclaimed.

## Beyond py4DSTEM — the differentiators

Each is its own product, out of v2 by the 2026-08-18 decision.

- **Needle-shaped precipitate pipeline** (2026-08-06, re-requested
  2026-08-26) — classifying each scan position by its full diffraction
  pattern, superseded from real-space segmentation 2026-09-11
  (`../_archive/mac4DSTEM/docs/v3-features.md#precipitate-classification`,
  `docs/decisions/019-precipitates-by-classification.md`). Ships unvalidated
  (`validation:"none"`, `docs/status.md` § Handoff). **2026-09-23:** an Al → precipitate false-call guard (`specific ≥ 1`) measured
  423/29241 = 1.45 % against the baseline 1.81 %, checked independently in
  part — the headline number stands, but it is not parameter-free (it rides
  a (count, pair-radius) ridge) and the object-table evidence it cited is
  spurious-singleton removal, not repaired detection
  (`../_archive/mac4DSTEM/docs/archive/v3/precipitate-overnight-2026-09-23.md`). It
  shipped on at k ≥ 1 (ADR 038, 2026-09-23); it first reaches users
  in v4.5.0, inside phase mapping's unvalidated badge.
- **EDX suite — v5.0** (2026-08-26; ADR 052) — "4D-STEM + EDX" (one scan, a diffraction pattern and an EDX
  spectrum at every probe position) and plain EDX spectrum images, in a seventh room "Spectroscopy", ported from
  HyperSpy/eXSpy/RosettaSciIO. A data-model change before a feature: a second signal with its own reader and units, registered
  onto the scan grid with the transform recorded. The full picture and the options: `../_archive/mac4DSTEM/docs/archive/v5/edx-dossier-2026-10-05.md`. Decided: ADR 053–055. Built; see v5.0 below.
- **Live acquisition · copilot** — named, nothing designed. Unclaimed.
- **Lineage graph with real rewind** (2026-09-21) — landed on `main` 2026-09-29 (`aa920d08`, ADR 047: session
  record v2 with step ids and input edges; the graph in the Lineage pane; Rewind to Here restores parameters and marks
  later products stale); ships in v4.5.0.
- **Learned disk candidates** (Core ML on the Neural Engine) — the first ML
  feature, **shipped in v3.0.0** (2026-09-11, `tools/release/README.md` § Releases).

## Leave alone; where the app is ahead

Not chased: py4DSTEM's visualization layer, `utils/` helpers for their own
sake, `.automatic` residency (needs a second machine). Ahead of py4DSTEM and
part of the product story: the load-specification and promote workflow,
provenance that survives export and reopen, refusals that name what failed,
the session sidecar as a sharing unit.

## v4.1 — the plateau (ADR 049, 050)

The feature list is frozen at what v4.0.0 ships; inside it v4.1 means **parity with py4DSTEM for the shipped features**,
and four half-built pieces are finished: ptychography (both methods, against py4DSTEM and a ground truth), training as a
useful feature, preprocessing of raw data in the app, and one new control — keep the cube in memory.

## v5.0 — the EDX suite (ADR 052–062)

Built on SpectroKit (extracted 2026-10-13, ADR 064, 066): readers, simulator, fit, k, absorption, statistics, method and
replay, pools, proposer, Auto ID, Export, and a Spectroscopy room with Velox-style display and line families. EDX
quantification ships badged unvalidated. 4D × spectroscopy correlation stays in this app. After v5.0: per-phase score and
separability matrix, and further EDX items.

## After v4.1 — frozen until reopened

Parity themes 2–7 above and point-group coverage beyond cubic and hexagonal; live acquisition; volumetric density and β″
orientation maps (ADR 046); the Al Materials Project comparison (ADR 048); phase mapping's validation (it ships badged
unvalidated until a dataset with truth passes); ACOM candidate F (ADR 050); what a resident cube allows beyond v4.1 (live
aperture, live detection); the built-in crystal library's size.

**References beyond py4DSTEM.** py4DSTEM is the parity reference; a simulator (abTEM) gives truth; pyxem/orix
(orientation), LiberTEM (disks, strain) and PtyRAD (ptychography) are optional cross-checks. Candidate work, in this
order: (1) abTEM cubes with truth — disks, strain, orientation, ptychography; (2) pyxem template matching against ACOM on
shared peaks (compare misorientation, not Euler angles); (3) PtyRAD on the same simulated cube.
