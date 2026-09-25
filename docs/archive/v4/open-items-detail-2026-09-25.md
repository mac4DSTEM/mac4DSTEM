# Open-items detail — 2026-09-25 cold-start trim

Full wording of the "Other named science/presentation residuals" section of
[`docs/open-items.md`](../../open-items.md) as it stood at `4bdc2e9`, compressed
there to one line per item on 2026-09-25 (the cold-start set had grown to 850
lines). Nothing here is closed; the live entry is the short one.

---

### Other named science/presentation residuals
Full original wording for the first four: `archive/open-items-detail-2026-09-23.md`.
- **Al-Mg-Si cube's peak set not clean** (2026-09-12): only 39 % of detected
  vectors explained by the best Al orientation — a detection statement, not
  a matcher failure (matcher refuses 99.0 % rather than inventing).
- **β″ zone axis for ⟨110⟩Al not chosen** (known, scoped): no ⟨110⟩Al variant
  is viewed down its needle axis; which axes it DOES present is unanswered.
- **The ellipse "Fit anyway" mark doesn't survive a session round trip**:
  `PixelCalibration` carries a/b/θ only — a sidecar wire-format decision.
- **A challenged matrix verdict is drawn like one by exclusion**: same grey
  for "matrix took it back" vs "too little to index." Presentation, no Gate D.
- **The hexagonal IPF colour key may be labelled wrong way round** (2026-09-11):
  the colour function and both label strings are established; which triangle
  corner each sits under is not. Owner: settle against the convention, pin
  with a unit test, before calling it presentation-only.
- **Single-slice ptychography's export guard may miss its mode**
  (`ResultExport.swift:1627` vs `:1478`): not established that the publish
  path uses the distinct case. Gate D — a scale bar is a scientific number.
- **The Quantitative badge consults no origin gate**: only ACOM is wired
  (`ACOMWorkflow.swift:145-150`); Strain snapshots the origin and nothing
  reads it; DPC snapshots nothing. A 2026-09-11 fix was Gate-B rejected and
  reverted (changed no behaviour). Ships as a stated limitation. Gate D+B owed.
- **A radius-only aperture drag destroys the fitted origin** (2026-09-11):
  `ApertureOverlay.emit` rounds the centre and hands the whole `Aperture` to
  `updateAperture`, which trips the centre-change branch on rounding alone
  (`AppState.swift:3112`). Cheap, Gate D (a number can move).
- **"Computed this session" reports what EXISTS, not what was computed**
  (2026-09-11): a restored sidecar shows both readiness rows green having
  computed nothing (bare predicates, `WorkspaceInspector.swift:563-565`).
  Presentation only.
- **Moving the detector destroys the origin fit with no durable warning**
  (2026-09-11): the aperture centre IS the calibration; only a transient
  status line notices. Owner: confirmation, banner, or refuse.
- **Bullseye disk detection accepts noise** — two of three fixes landed
  2026-09-05 (flat mode + Use File's Probe, parity 878/878 and 164/164);
  open: an outer-edge probe size for structured probes. Owner: drive Map ▸
  Bragg disks, Flat + Use File's Probe, Min relative intensity ~0.05.
- **The one-peak warning is below the fold; Strain unlocks without it**
  (driven 2026-09-09, `archive/v3/drive-2026-09-09.md` finding 16): Strain
  gates on Bragg vectors existing, not on being usable. Presentation +
  readiness question, no Gate D (mechanism established by reading, no number
  moves).
- **Twisted bilayer graphene finds only the beam at defaults**: one accepted
  peak at `relativeToPeak` 0 AND 1 — the relative threshold isn't what
  removes the disks; not diagnosed which stage swallows the ring. Gate D
  owed with a per-pattern funnel.
- **Learned detector above 256 px: probe/pattern anchor mismatch** (Gate B):
  the probe channel crops clamped-centred while pattern windows use
  `windowOrigins` — the opposite of every training input. No Python
  reference above 256 px; nothing shipped is above 250 px. Owed: one
  synthetic >256-px case scored both ways before the windowed path is
  quoted as measured.
- **#18 — the training campaign can't reproduce the app's Si_SiGe strain**
  (2026-09-02): resolved mechanism (campaign's origin fit is ~7 px off,
  poisoning clustering scale; the app's own gate rejects that fit). Two
  candidate fixes exist, neither made (own Gate B). Detail:
  `archive/open-items-detail-2026-09-18.md`.
- **CIF import can silently accept a wrong crystal** (2026-09-01): a non-P1
  declaration with a partial ops list can still import the wrong cell
  (Gate B escape E2, recorded not fixed) — needs a 230-entry IT-number→
  group-order table the importer lacks. Owner: unclaimed, Gate B when picked up.
- **ACOM orientation/export coverage gaps** (2026-08-31): exported Euler
  angles differ from py4DSTEM/orix by frame rotation `P` (median 38.55°
  naive misorientation, math right, label wrong); every gated ACOM harness
  builds its own peaks through the function it tests, so two frame-mutation
  bugs stay green. Owner: relabel-vs-convert decision, then Gate B.
- **DPC's banner contradicts its badge — corrected 2026-09-04**: the badge
  and banner agree; the real defect is `PhaseSettings`' always-shown
  qualitative banner over quantities `quantitativeStatus` calls quantitative.
  No version field exists to migrate existing sidecars/PNGs on a fix. Owner:
  the trust-fixes session, a judgement call.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.
