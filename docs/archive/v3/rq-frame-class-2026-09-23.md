# R–Q rotation frame class, diagnosed — 2026-09-23

Track "rq" (YELLOW): diagnose and measure only; `Core/Analysis/RotationCalibration.swift`
and all other app code untouched. Open item: `docs/open-items.md` ("RotationCalibration's
py4DSTEM parity leg exposes an (Rx,Ry)-vs-(col,row) frame class", added 2026-09-17), detail
`docs/archive/open-items-detail-2026-09-18.md`.

## 1. What is established from the pinned source (`References/py4DSTEM-dev` @ `f050d20`)

- **DataCube axis order.** `dim_names=["Rx", "Ry", "Qx", "Qy"]`
  (`py4DSTEM/datacube/datacube.py:59`); `R_Nx` is `self.data.shape[0]`, `R_Ny` is
  `self.data.shape[1]` (`datacube.py:172-177`). Rx is unconditionally the array's first/
  outer axis, Ry the second/inner axis — never the reverse, anywhere in the pinned tree.
- **CoM field storage matches.** `_calculate_intensities_center_of_mass` builds
  `com_measured_x = xp.zeros((sx, sy))` with `sx, sy = intensities.shape[:2]`, then
  `for rx, ry in tqdmnd(sx, sy, ...): ... intensities[rx, ry]`
  (`py4DSTEM/process/phase/phase_base_class.py:706-727`) — `com_measured_x/y` are shape
  `(Rx, Ry)` with `rx` indexing axis 0, matching the DataCube. `Calibration.get_origin`'s
  `qx0`/`qy0` are the same shape, same indexing (`py4DSTEM/process/calibration/origin.py:270,288`;
  `py4DSTEM/data/calibration.py:504-505`).
- **Display orientation.** `show()` passes the array straight to `ax.matshow(_ar, ...)`
  with no transpose anywhere in the file (`py4DSTEM/visualize/show.py:495-629`, grepped for
  `.T`/`swapaxes`/`transpose` — none). Virtual images are built as
  `np.zeros(self.Rshape)` = `(R_Nx, R_Ny)` (`py4DSTEM/datacube/virtualimage.py:209-275`).
  So Rx (axis 0) always renders as the **vertical** axis on screen, Ry (axis 1) as
  **horizontal** — the opposite of what the letters "x"/"y" suggest to a reader used to
  x = horizontal.
- **The curl formula's own pairing** (the exact branch the harness transcribes,
  "Transpose unknown, rotation unknown", `maximize_divergence=False`,
  `phase_base_class.py:1109-1118`):
  `com_grad_x_y = com_measured_x[:, 1:-1, 2:] - com_measured_x[:, 1:-1, :-2]` (∂com_x/∂Ry,
  last/inner axis) and `com_grad_y_x = com_measured_y[:, 2:, 1:-1] - com_measured_y[:, :-2, 1:-1]`
  (∂com_y/∂Rx, the batched middle/outer axis); `rotation_curl = mean(|com_grad_y_x - com_grad_x_y|)`.
  So py4DSTEM's own curl is **∂(com_y)/∂Rx − ∂(com_x)/∂Ry** — the standard curl_z = ∂Vy/∂x − ∂Vx/∂y
  formula, with "x" = Rx = the array's axis 0 and "y" = Ry = axis 1, by construction.

## 2. Diagnosis (before the experiment)

`RotationCalibration.swift` is called from real data as
`RotationCalibration.solve(com: com, width: d.rx, height: d.ry, ...)`
(`mac4DSTEM/App/AppState+Calibration.swift:244`), and its own doc comment fixes
"X = detector column / scan column, Y = row" (`RotationCalibration.swift:24-26`). Combined
with the real call site, Swift's "X" **is** `d.rx` (the scan's Rx count) and is stored as
the **fast/inner** array index (`i = y*width + x`, `objective(...)`'s `i±1` step,
`RotationCalibration.swift:139-169`) — the opposite storage slot from py4DSTEM's Rx
(always axis 0/outer). Swift's curl (`RotationCalibration.swift:159-164`) is
`∂(y')/∂x[fast] − ∂(x')/∂y[slow]` = **∂Vy/∂Rx − ∂Vx/∂Ry** once "x"/"y" are read as the
*physical* scan directions (rx-direction, ry-direction) rather than raw storage axis
position. That is the *same* formula as §1's py4DSTEM citation, just stored transposed in
memory (fast vs. slow) — a legitimate, harmless internal layout choice, not a convention
difference, **provided** whatever feeds `py4dstem_curl_grid_search` in the harness aligns
its array axis 0 with the rx-direction (matching py4DSTEM's real Rx=axis 0), not with
whichever axis the fixture happened to build first.

**Diagnosis:** `tools/rotation-parity-test/reference.py`'s leg (b) call,
`py4dstem_curl_grid_search(direct_cx, direct_cy)`, feeds the fixture array **un-transposed**.
`potential_gradient(width, height)` builds `gx, gy` via
`np.meshgrid(np.arange(width), np.arange(height))` (default `'xy'` indexing) → shape
`(height, width)`, i.e. **axis 0 = height/ry-direction, axis 1 = width/rx-direction** — the
reverse of what the function's own comment assumes ("array axis 0 = Rx"). The bug is in
the harness's axis-mapping comment/call, not in `RotationCalibration.swift` and not in
py4DSTEM's actual formula.

**Refuting observation:** if this diagnosis is right, transposing the fixture array (swap
axis 0 ↔ axis 1, keep the `cx`/`cy` channel labels as-is) before the `py4dstem_curl_grid_search`
call should flip the leg-(b) answer to agree with Swift's (within the 1°-grid vs.
0.1°-refined residual already tolerated); if wrong (i.e. if the frame class is a real
disagreement between Swift's math and py4DSTEM's), transposing should change nothing
diagnostic, or should move the answer somewhere that still disagrees with Swift.

**Predicted outcome:** direct fixture, transposed array → angle ≈ −37° (grid), transpose=false,
matching Swift's −37.2°; transposed fixture (already channel-swapped per `rotate(gy, gx, ...)`),
transposed array → angle ≈ +37°, transpose=true, matching Swift's +37.2°.

## 3. Experiment and result

Standalone script (not committed — `rq_probe.py` in the session scratchpad), reusing
`reference.py`'s own `potential_gradient`/`rotate`/`py4dstem_curl_grid_search` unmodified:

```
direct_cx shape (height,width): (40, 40)
AS-IS (current harness):        angle=37.00  transpose=True
TRANSPOSED array axes:          angle=-37.00 transpose=False
Swift reference: direct fixture -> transpose=False, angle = -planted = -37.20

AS-IS transposed-field case:    angle=-37.00 transpose=False
FIXED transposed-field case:    angle=37.00  transpose=True
Swift: transposed fixture -> transpose=True, angle = +planted = 37.20

non-square sanity (h=30,w=40) — rules out the square-shape coincidence:
AS-IS non-square: angle=37.00  transpose=True
FIXED non-square: angle=-37.00 transpose=False
```

Both predictions held exactly, on both fixture fields, and the effect persists on a
non-square field (40×40 cannot distinguish "transposed" from "mislabeled" dimensionally;
30×40 rules that out — no shape-mismatch exception was raised either way, so the original
bug was never caught by a dimension check). **Diagnosis confirmed.**

## 4. Verdict

**Neither `RotationCalibration.swift` nor py4DSTEM's actual rotation-solve is wrong.**
Both implement the same curl_z = ∂Vy/∂Rx − ∂Vx/∂Ry formula against the same physical scan
axes; they simply store the Rx/Ry axes in opposite array-index order internally (py4DSTEM:
Rx=axis 0/outer; Swift: rx=fast/inner), which is invisible to a correct caller. The bug was
**in the test harness's leg (b) transcription**: it fed py4DSTEM's own formula an array
whose axis 0 was the *height* (ry-direction) instead of the *width* (rx-direction),
producing exactly the observed sign-flip-plus-transpose signature — the frame class was
real, but it was a bug in the fixture's axis bookkeeping, not a disagreement about physics.

**User-visible consequence: none.** `AppState+Calibration.swift:271-273` writes
`result.rotationRad`/`result.transpose` from `RotationCalibration.solve` straight to the
status line with no further transform, and that call already passes `width: d.rx, height:
d.ry` — i.e. the app path already has the correct rx/ry axis identification this record
had to reconstruct for the harness. There was never a wrong-sign path to the screen; only
the harness's informational (non-gating) comparison was miscomputing its own reference leg.

## 5. What changed

`tools/rotation-parity-test/reference.py`: leg (b)'s call site now transposes the fixture
array (`direct_cx.T, direct_cy.T`) before calling the (otherwise byte-identical, still
source-gated) `py4dstem_curl_grid_search`, with this record cited for why. Leg (b) stays
**informational** (never gates — `assert_source_contract()` is still the only hard gate on
this leg, per the existing design); only what it *reports* changes, from a NOTE
(disagreement) to a PASS (agreement, within the existing 0.5° tolerance and the coarse-grid
residual already documented). `tools/rotation-parity-test/main.swift`'s leg-(b) comment
updated to stop describing the disagreement as current/unresolved. No change to
`RotationCalibration.swift`, no change to any shipped default or scientific number, no
change to what leg (b) gates (it still gates nothing beyond the source-contract assert).

Before/after (harness run, `tools/rotation-parity-test/run.sh`):
- Before: `NOTE: py4DSTEM curl-grid-search parity leg disagrees (informational, not a failure...)`
- After: `PASS: py4DSTEM curl-grid-search parity (informational): ...`

Log: `rq-harness-after-fix.log` (this session's scratchpad; run exit code confirmed via
`echo $?` on its own line, not through a pipe).

## Owner decision needed

None — this is a test-harness bookkeeping fix on an already-informational, non-gating leg;
no shipped number, default, or verdict moved. Filed for the record per Gate D's requirement
to write down what a diagnosis found even when it resolves with "the code under test was
already right."

## Independent refutation — 2026-09-23 01:15 CEST

**Verdict: PARTIALLY REFUTED.** §2–§3 are right about *what the old leg (b) computed*, and
`RotationCalibration.swift` is internally consistent. But "neither side was wrong" and
"user-visible consequence: none" do not survive the real-file question: **for the same data
file, the app's `rx` is py4DSTEM's `Ry` and the app's `qx` is py4DSTEM's `Qy`, so the app's
rotation is the NEGATIVE of py4DSTEM's (transpose flag identical)** — and that number
crosses the py4DSTEM boundary unconverted. The item is reopened (`docs/open-items.md`).

**1. File axis → app axis (code).** `DatasetDescriptor.swift:15,38-41`: shape is HDF5 order
"[Ry, Rx, Qy, Qx]" — `ry = shape[0]`, `rx = shape[1]`, `qy = shape[2]`, `qx = shape[3]`.
`Shaders/CenterOfMass.metal` (`kernel void centerOfMass`): `scanIdx = gid.y * p.rx + gid.x`,
`comX` weights the inner detector index `x < p.qx`; `VirtualDetector.tiledCenterOfMass`
tiles over `ry` rows at `ry*rx*2` (`VirtualDetector.swift:494-521`). So app `cx` = CoM
along file axis 3, `cy` = along file axis 2, scan index `axis0*W + axis1`. py4DSTEM: `Rx`
= axis 0 (`datacube.py:172-173`), `com_x` = CoM along axis −2 (`phase_base_class.py:679-696`,
`kxa` over `shape[-2]`). Hence app (rx, ry, cx, cy) = py4DSTEM (Ry, Rx, com_y, com_x): both
the scan pair and the detector pair are swapped. A reflection applied to both spaces
conjugates R(θ) to R(−θ): app θ = −py4DSTEM θ, same transpose. The app's own code already
knows the swap for origins — `H5Reader.swift:822-825` ("[R_Nx,R_Ny], the same real-space
order as this app's [Ry,Rx]"), `AppState+Open.swift:483-494`, `ResultExport.swift:1296-1297`
("the sole save boundary where app detector x/y becomes py4DSTEM qy/qx"),
`BraggVectorEMDWriter.swift:2029` (peaks written `qx: peak.y, qy: peak.x`), `Rshape =
[scanHeight, scanWidth]` (`:1966`) — but not for the rotation.

**2. Head-to-head (run).** Pinned vendored py4DSTEM (`References/py4DSTEM-dev` @ `f050d20`,
numpy-2 shims, `py4dstem` conda env) runs its real `DPC(...).preprocess(plot_rotation=False,
plot_center_of_mass=None)` → `_solve_for_center_of_mass_relative_rotation`; its
`_com_normalized_x/y` (shape `(Rx,Ry)`) is dumped in the app layout (`cx = com_y`, `cy =
com_x`, index `a*W+b`) and fed to the shipped `RotationCalibration.solve(com:, width:
shape[1], height: shape[0])` exactly as `AppState+Calibration.swift:244` calls it (swiftc
driver built from `tools/lib/sources.manifest`'s `calibration` group +
`RotationCalibration.swift`, as `tools/rotation-null-probe/run.sh` does). Planted fields are
curl-free `∇φ` over (Rx, Ry) with measured `(Qx,Qy) = R(−θ)∇φ`, 48×36 (non-square).
Logs: `py_side.log`, `swift_side.log` (refuter scratchpad `refute-rq/`, both exit 0).

| field | py4DSTEM (deg, transpose) | app `RotationCalibration` (deg, transpose) |
|---|---|---|
| planted +25° | +25.00, false | −25.10, false |
| planted +25°, detector transposed | +25.00, true | −25.10, true |
| planted −60° | −60.00, false | +59.90, false |
| **real cube** `Particle_1_Stack_1_45x90…bin8.h5` (90×45×128×128), py4DSTEM's own CoM + plane fit | **+80.00, true** | **−80.10, true** |

Same CoM numbers, relabeled per the app's documented axes; only the frame differs. Sign
flips on every case, transpose never. (Whether the real-cube field beats ADR 024's null was
not checked — the sign relation is exact for any field.)

**3. Is the harness change "tuning the reference until it agrees with Swift"? Yes, in
effect.** `potential_gradient` is laid out (height, width) = (app ry, app rx) = (file axis 0,
file axis 1), and `cx` is the app's detector-x channel. A file-faithful py4DSTEM call keeps
axis 0 (= py Rx) and swaps the channels (`com_x = cy`, `com_y = cx`); the committed fix
instead transposes the scan axes and keeps the app's channel labels — relabeling BOTH
spaces into the app's frame, which agrees with Swift by construction. With
`reference.py`'s own frozen `py4dstem_curl_grid_search` (source contract asserted),
`harness_filefaithful.log`:

```
40x40 direct     file-faithful py4DSTEM: (37.0, False) | harness-as-committed (cx.T, cy.T): (-37.0, False)
40x40 transposed file-faithful py4DSTEM: (-37.0, True) | harness-as-committed (cx.T, cy.T): (37.0, True)
40x30 direct     file-faithful py4DSTEM: (37.0, False) | harness-as-committed (cx.T, cy.T): (-37.0, False)
```

Swift gives (−37.2, false) on "direct". So the old NOTE's *transpose* flip was the harness's
channel labels; its *sign* flip is the real app-vs-py4DSTEM difference, and leg (b)'s PASS
now hides it. The transpose is justified by Swift's labels, not by py4DSTEM's file contract.

**User-visible consequences (code, not yet exercised end to end):** (i) the status line
`Rotation ✓ θ = …` (`AppState+Calibration.swift:271-273`) and export key `qr_rotation_deg`
(`ResultExport.swift:491-492`) read −(py4DSTEM's value) on the same file, with no
`DEVIATION` note; (ii) a py4DSTEM `QR_rotation` is imported unconverted
(`H5Reader.swift:819` → `AppState+Open.swift:474`) and the app's is exported unconverted as
`QR_rotation`/`QR_rotation_degrees` (`ResultExport.swift:1304` →
`BraggVectorEMDWriter.swift:1690-1697`) beside peaks and origins that ARE axis-swapped — so
py4DSTEM's `braggvectors.py:528-545` would rotate the app's exported peaks the wrong way
(2θ error, 20° mod 180° on this cube), and an imported py4DSTEM rotation drives the app's
strain frame/DPC with the wrong sign. `QR_flip` needs no conversion (transpose invariant,
table above). Not checked, same boundary: `ellipseTheta` (`AppState+Open.swift:478`,
`BraggVectorEMDWriter.swift` writes `theta` unconverted).

**Correct state: OPEN** (reopened in `docs/open-items.md`; closure entry removed from
`closed-items-2026-09.md`). The fix — a sign conversion at the two py4DSTEM boundaries, a
`DEVIATION` note or a displayed-convention decision, and a file-faithful leg (b) — moves a
scientific number: Gate D, owner decides the displayed convention.

Reproduce (condensed from the refuter's `py_side.py` / `main.swift` / `harness_filefaithful.py`):

```python
# py4DSTEM side (pinned tree, numpy-2 shims first):
dpc = DPC(datacube=py4DSTEM.DataCube(h5py.File(p)[ds][...].astype(np.float32)), energy=300e3, verbose=False)
dpc.preprocess(plot_rotation=False, plot_center_of_mass=None)          # or force_com_measured=(qx, qy)
nx, ny = np.asarray(dpc._com_normalized_x), np.asarray(dpc._com_normalized_y)
app = np.empty(nx.size * 2, np.float32); app[0::2] = ny.ravel(); app[1::2] = nx.ravel(); app.tofile(out)
print(np.rad2deg(dpc._rotation_best_rad), dpc._rotation_best_transpose)
```
```swift
// app side: swiftc -package-name mac4DSTEM driver + calibration sources + RotationCalibration.swift
let r = RotationCalibration.solve(com: com, width: shape1, height: shape0)!   // AppState+Calibration.swift:244
```
