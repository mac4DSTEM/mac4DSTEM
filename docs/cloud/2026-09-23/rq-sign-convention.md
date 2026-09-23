# R–Q rotation sign convention: decision memo, 2026-09-23

Read-only; nothing executed. Every finding is **read-verified at HEAD `3d0134a`** (py4DSTEM
`References/py4DSTEM-dev` @ `f050d207`). The measurement (app −80.1° T vs py4DSTEM +80.0° T, real
cube; planted ±25°/−60°, 48×36) is the refuter's, `docs/archive/v3/rq-frame-class-2026-09-23.md`
§Independent refutation, not re-run here.
Open item: `docs/open-items.md:24-39`. No ADR covers the R–Q sign (`docs/decisions.md`: ADR 024 is
the rotation *null* only; ADR 006 is the DEVIATION-note rule). **The choice is the owner's.**

## 1. The chain

**App: axis reading.** `DatasetDescriptor.swift:15,38-41`: shape = [Ry, Rx, Qy, Qx], so `ry` = file
axis 0, `rx` = axis 1 (scan fast index), `qy` = axis 2, `qx` = axis 3. CoM: `CenterOfMass.metal:36`
`scanIdx = gid.y*p.rx + gid.x`; `:50-56` `sumIX` over the inner `x < p.qx` loop, so app `cx` is
along file axis 3, `cy` along axis 2.
**App: solve.** `AppState+Calibration.swift:242` calls `RotationCalibration.solve(com:, width: d.rx,
height: d.ry)`; `RotationCalibration.swift:139-168` forms (x', y') = R(θ)·(a, b), (a, b) = (cx, cy)
or (cy, cx) if transposed, curl = ∂y'/∂x[i±1] − ∂x'/∂y[i±width]. App frame: x = scan/detector column,
y = rows (`:24-26`). Stored by `CalibrationSession.swift:55-56`.
**py4DSTEM: axis reading.** `datacube.py:59` dim_names [Rx, Ry, Qx, Qy]; `:172-177` R_Nx = shape[0].
CoM `phase_base_class.py:679-700`: `kxa` spans `shape[-2]`, so `com_x` is along Qx = axis 2.
**py4DSTEM: solve and apply.** `phase_base_class.py:1090-1118`: (x', y') = R(θ)·(com_x, com_y),
curl = ∂y'/∂Rx − ∂x'/∂Ry; applied `:1253-1270`. Calibration `QR_rotation`: `calibration.py:671-684`
(radians + degrees twin); applied as `R(θ)·(flip ? (qy,qx) : (qx,qy))` at `braggvectors.py:528-545`;
`rotation.py:210-235` documents it as "counterclockwise rotation of real space with respect to
diffraction space", same R(θ) Q→R form as DPC. Also read by `strain.py:967-968`.
**Where the sign enters.** App (x, y) = P·py (x, y) in **both** spaces, P = swap. Then
P·R(θ)·P = R(−θ) and P·F·P = F, so θ_app = −θ_py, flip identical — exact for any θ, and the 180°
ambiguity is preserved (−(θ+π) ≡ −θ+π). Matches the refuter's table in every row.

**Internal consumers of `calibration.rotationRad` (grep `rotationRad|transposeQR`, `mac4DSTEM/`):**

| consumer | file:line | frame of its formula |
|---|---|---|
| DPC/iDPC field rotation | `AppState+DPC.swift:119-123` → `DPC.swift:53-63`; iDPC `DPC.swift:291-296,337-352` (cx ↔ fast axis) | app |
| 180° flip | `AppState+DPC.swift:87-104` | sign-neutral |
| strain scan frame | `AppState+ResultPresentation.swift:351-352` → `StrainFrame.swift:63-65,157-176` | app (transcribed; `tools/strain-frame-test/reference.py:1-20`) |
| ptychography positions | `PtychographyPreparation.swift:114-200` via `ParallaxPhysicalCalibration` | app (D002: py `positions[:,0]` = app column; `d002-d003-gate-d.md:55-61,199-204`) |
| parallax preprocess | `ParallaxPreprocessing.swift:59-63,97-101` | **carried, never read** except by ptychography |
| displays | `AppState+Calibration.swift:268-271`, `AppState+DPC.swift:102`, `PrepareSettings.swift:301-305`, `WorkspaceInspector.swift:1002,1016-1019`, `StrainFrame.swift:81-83` | app |
| provenance keys | `ResultExport.swift:486-493` (`qr_rotation_rad/deg`; `:1415-1416` claims "machine parity with py4DSTEM's QR_rotation") | app, mislabelled |
| ACOM / phase maps | no read in `Core/Crystal/` (grep null — absence of a read, nothing more) | — |

**Boundary crossings (all unconverted):**
- py4DSTEM file import: `H5Reader.swift:818` → `AppState+Open.swift:468` (provenance `:473`). The
  origins beside it ARE swapped (`AppState+Open.swift:478-492`).
- Sidecar / EMD read: `BraggVectorEMDWriter.swift:718-720` → `SessionCalibrationFramePolicy.swift:82`
  → `AppState+Open.swift:922-924`.
- Export: `ResultExport.swift:1294-1304` ("sole save boundary where app detector x/y becomes
  py4DSTEM qy/qx") → `BraggVectorEMDWriter.swift:1690-1697`; peaks beside it ARE swapped (`:2029-2032`).
- Tool mirrors: `tools/reduced-export-test/main.swift:153`, `tools/training-dataset-campaign/main.swift:202,268`.

## 2. Is the app self-consistent?

**Inside the app, yes (read-verified).** Every internal formula that consumes θ (DPC, iDPC, strain,
ptychography) is written in the app's relabelled frame, the same frame `RotationCalibration` solves
in. D002's refuter reached the same conclusion for ptychography by harness (`d002…:199-204`).
**The wrong numbers are at the boundary, where one convention's value feeds the other's consumer:**
1. **Import (wrong number).** A py4DSTEM `QR_rotation` (py sign) lands in `rotationRad` and drives
   DPC/iDPC, the strain scan frame and ptychography positions, all app-frame: they apply −(correct θ).
   Error 2θ (mod 180°) in the field/tensor/position rotation.
2. **Export (wrong number in py4DSTEM).** py4DSTEM applies the app's θ to peaks the app already
   axis-swapped (`braggvectors.py:528-545`): again 2θ, 20° mod 180° on the refuter's cube.
3. **`ParallaxPhysicalCalibration` mixes conventions in one struct** (`ParallaxPreprocessing.swift:
   38-41`): `originQX/QY` are py4DSTEM order (`:97-99`), `rotationRad/transpose` app order (`:100-101`),
   unlabelled. Today harmless: its only θ reader (ptychography) is app-frame and reads the origin as
   row = `originQX` (`PtychographyPreparation.swift:70,76`). A latent trap for the next py4DSTEM port.
4. **Two rotations on screen, two conventions.** Parallax "Fitted rotation" (`PhaseSettings.swift:
   722-725`, `AppState+PhaseContrast.swift:187-191`) is fitted in py4DSTEM's file-faithful frame
   (`ParallaxAberrationFitting.swift:154-157` row = py qx; `:192` mirrors `parallax.py:2289`;
   header `:30` says "py4DSTEM's … convention"); the R–Q line is app-frame. No number is computed from
   both (`forceRotationAngleDegrees` is never set outside its file — grep). Whether py4DSTEM's
   `rotation_Q_to_R_rads` and DPC's `_rotation_best_rad` share a sign on the same data: **not established here**.
5. **`ellipseTheta`: no conversion owed (read-verified).** Kept in py4DSTEM's frame end to end:
   `EllipseCalibration.swift:35,120` (qx = row), `Calibration.swift:896-903` (explicit swap at use).
   It is a precedent for storing py4DSTEM-native and converting at use.

## 3. Options

**(A) Display py4DSTEM's sign; convert at display and at the file boundary.** Touches B's files plus
every display site in §1 (5 sites + provenance keys), and the objective plot's x-axis and marker at
`WorkspaceInspector.swift:1002`, a **frozen-shell file** (CLAUDE.md: changes only against an
accepted picture). Changing the text of existing rows falls under "Drive before more surface".
Risk: one missed display site produces two signs on screen. Gain: numbers match a py4DSTEM notebook
and plausibly the parallax fitted rotation (item 4, unverified).
**(B) Keep the app's sign; convert only at the import/export of `QR_rotation`, with a `DEVIATION`
note.** Negate at the three app↔PixelCalibration points, keeping `PixelCalibration` py4DSTEM-native
as the origins already are: `AppState+Open.swift:468`, `SessionCalibrationFramePolicy.swift:82`,
`ResultExport.swift:1304`, plus the tool mirrors (§1). Sidecars: `HDF5Types.swift:51`
`currentSchema = 6` has to go to 7, and schema ≤ 6 sidecars restore with the legacy (app) sign. Raise
`mac4dstem_min_reader_schema` (`:53-62`), because a v4.0.0 reader ignoring the change would misread the sign
("dangerous to ignore"). Rename or convert the `qr_rotation_*` provenance keys and fix `:1415-1416`.
Internal numbers and every internal harness are unchanged. Risk: the screen still shows −py4DSTEM's
value; this is disclosure, not a wrong number, but it needs a label. Already-exported v4.0.0 files carry
the app sign and are not repairable in place (release note).
**(C) Read file axis 0 as rx.** Touches `DatasetDescriptor`, the CoM shader, every scan/detector
index consumer, the origin/peak swaps, and re-derives D002. Every harness below changes. Largest blast
radius, for a result B reaches at three lines.

**What pins the current sign** (grep `mac4DSTEMTests`, `tools/`):
- Internal sign (kept by A/B, flipped by C): `CalibrationReReferenceTests.swift:537-548` (+30° → −30°);
  `tools/rotation-parity-test/main.swift:87,111`; `tools/strain-frame-test/reference.py:17-20`;
  `tools/singleslice-ptychography-test/reference.py:218-240` (incl. its `wrong_sign` variant).
- Boundary. `tools/calibration-test/main.swift:60` pins `PixelCalibration` = 0.375 from a real
  py4DSTEM file, and `tools/sidecar-result-test/verify_py4dstem.py:30,72-73` pins −0.625 written, −0.625
  read. Under B as placed above, both stay green: they test the py4DSTEM-native snapshot, not the
  app-level value. So **no current test pins the app↔py4DSTEM sign**, and a new one has to.
- Informational: `rotation-parity-test` leg (b), `main.swift:122-133` / `reference.py:172`, not file-faithful (archive §3).

**Gate D pre-registration for the sign conversion (any option):**
- *Diagnosis:* both scan and detector pairs are relabelled by the same swap P, so θ_app = −θ_py,
  flip unchanged. `QR_rotation` crosses at `AppState+Open.swift:468` / `ResultExport.swift:1304`
  without it.
- *Refuting observation:* any case where θ_app ≠ −θ_py beyond the 1°/0.1° grid residual (0.2°),
  or where the flip differs, on a non-square field at an asymmetric angle (not 0/45/90). Or: an
  imported py4DSTEM `QR_rotation`, negated, gives *more* mean |curl| on that file's own CoM field
  than un-negated.
- *Predicted outcome:* (i) the real cube `Particle_1_Stack_1…bin8.h5` imported with py4DSTEM's +80.0°
  yields app −80.0° and applying it matches the app's own solve (−80.1°) within 0.2°; (ii) app θ
  exported → py4DSTEM `get_QR_rotation()` = −θ, and `braggvectors` calibrated peaks equal the app's
  scan-frame peaks, swap-mapped, to float tolerance; (iii) app → sidecar → app is the identity for
  schema 7, and a schema-6 sidecar restores its stored value unchanged; (iv) every internal-sign pin
  above stays green, unedited.
- *Experiment:* the refuter's head-to-head (`rq-frame-class` §Independent refutation, reproduce block), extended with the
  import and export legs through py4DSTEM's own `DPC` and `braggvectors`. Add a file-faithful leg (b)
  (keep axis 0, `com_x = cy`, `com_y = cx`; assert θ_py = −θ_app). Break each new assertion by
  deleting the negation and confirm it goes red. The fixture is `real_py4dstem_origin_maps.h5` with
  an activation-level assertion (−0.375). The refuter is independent, and the diagnosis is what gets
  reviewed.

## 4. Recommendation (conservative; the owner decides)

**B now, A's display question separately.** The wrong numbers (§2 items 1-2) live only at the
boundary. B fixes them without moving any internal number or any harness that D002, S8 and ADR 024
already validated, and it matches how origins, peaks and `ellipseTheta` are handled. It needs a
`DEVIATION` note at the conversion ("app θ = −py4DSTEM QR_rotation; file axis 0 read as ry") and a
disclosed label on the R–Q row (e.g. "app frame; py4DSTEM QR_rotation = −θ"). Whether to also
*display* py4DSTEM's sign (A) is a presentation choice. It touches a frozen-shell file and should
wait for a driven build and for item 4's convention question. C is not recommended.
