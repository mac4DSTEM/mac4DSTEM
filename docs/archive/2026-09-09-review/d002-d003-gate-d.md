# D002 and D003 — Gate D, 2026-09-09

The two CRITICALs the 2026-09-09 register left standing. Both were diagnosed
before any fix, both predictions were written down before the experiments ran,
both were reviewed by an independent refuter against the evidence rather than
the diff, and both are fixed. The refuter **overturned one claim and narrowed
another**; those corrections are kept here, not tidied away.

What a reader reproduces is the gate, not a log:
`tools/run-tests.sh core`, `tools/datacube-discovery-test/run.sh`,
`tools/singleslice-ptychography-test/run.sh`.

---

## D002 — ptychography scan positions ignored the calibrated R–Q rotation

### Diagnosis
`PtychographyPreparer.prepare` built an axis-aligned raster from
`scanSamplingAngstrom` alone. Its `ParallaxPhysicalCalibration` argument
carries `rotationRad` and `transpose`, and `resolve` **refuses to build at all**
without a finite rotation ("Calibrate the R–Q rotation.") — so the app demanded
the value and then discarded it. py4DSTEM's
`_calculate_scan_positions_in_pixels` (`phase_base_class.py:1893-1917`) rotates
positions about their mean, and on transpose flips the pair **and** swaps the
sampling. No inline `DEVIATION` note existed.

### Prediction, written before running
Run `prepare` three times on one cube, changing only the calibration: all
three position arrays bit-identical.

### Result
Measured on a **non-square** crop (ry 5, rx 9, qy 32, qx 48 — row sampling
0.625 vs column 0.41667):

```
rotation 0° vs 30°:      max |Δposition| = 0.0  ->  IDENTICAL
transpose false vs true: max |Δposition| = 0.0  ->  IDENTICAL
```

Prediction met. With the py4DSTEM rotation patched into a copy of the preparer
the same harness reports `3.686` and `19.2` on that view, so the comparison
detects a change when one exists.

**Refuted along the way.** The first run used the 12×12×64×64 demo cube, which
is square with equal row/column object sampling — there, transpose is a no-op
*by geometry*, and the evidence did not exclude that explanation. The
non-square re-run above is what the finding rests on. A second slip: the
harness's inline "py4DSTEM convention" reference rotated the wrong way
(column-vector, where `AffineTransform` is row-vector, i.e. −θ) and omitted
`positions -= np.min(positions, axis=0).clip(-inf, 0)`. Both are corrected in
the port. Consequence figures: **11.16** object pixels rotation-only,
**17.6** for the full convention, on a scan spanning 35.2 — and it grows with
scan extent, so a 256×256 scan at 30° is roughly twenty times worse.

### The axis mapping, checked rather than assumed
py4DSTEM's `positions[:,0]` is its x axis. Its rotation solver
(`phase_base_class.py:1122-1128`) rotates `_com_normalized_x`/`_y` with the
same two expressions `RotationCalibration.objective`
(`RotationCalibration.swift:73-79`) uses for this app's `cx`/`cy` — and this
app's `cx` is the **column**. So py4DSTEM's axis 0 is this app's column, not
its row. A literal transliteration would have silently transposed the frame.

### Fix and its gate
`PtychographyPreparation.swift` now ports the function in its own order:
rotate about the mean in Å, transpose (flipping positions and sampling
together, locally — the object's own sampling and the probe built from it are
untouched), shift to non-negative, then to pixels, then pad.
`tools/singleslice-ptychography-test` gained 7 position cases against a
source-locked numpy reference; `tools/lib/sources.manifest` now compiles
`PtychographyPreparation.swift` in a gated harness for the first time, closing
`tools-gates-05` from the 2026-08-31 review.

**Broken before it was trusted.** Five mutations, each caught by the case
aimed at it, each dying on the position assertion and not on an unrelated
crash:

| mutation | failed at | max \|Δ\| |
|---|---|---|
| the original code (no rotation at all) | case 1 | 17.6 |
| wrong rotation sign (+θ) | case 1 | 17.600004 |
| transpose without the sampling swap | case 4 | 7.142562 |
| no clip-to-positive | case 1 | 6.442052 |
| axis mapping transposed | case 1 | 17.600004 |

**Corrected 2026-09-11 (Gate B).** That table says "five mutations, each caught
by the case aimed at it". It is **four** distinct transformations: `wrong
rotation sign (+θ)` and `axis mapping transposed` are the *same edit* in this
code — transposing the mapping changes only the sign of the `sin` terms, and
the per-axis padding and the symmetric transpose-swap are label-invariant,
which is why both rows report the identical `17.600004`. The harness therefore
cannot distinguish a wrong axis mapping from a wrong rotation sign at all. Both
are caught; neither is identified.

Real code: exit 0, 7 cases, 17 planted wrong conventions each rejected.

### DEVIATION kept
py4DSTEM pads BOTH axes by `region_of_interest_shape[0]/2`
(`object_padding_px = (float_padding, float_padding)`, then `[0][0]` and
`[1][0]` — both index 0). This app pads each axis by its own half-extent,
differing only on a non-square detector. Left as it was: outside D002's scope,
and changing it would move a number nobody asked about (`open-items.md`).

---

## D003 — H5Reader's attribute readers overran a one-value buffer

### Diagnosis
`H5Aread` reads the ENTIRE attribute into the caller's buffer and cannot know
its size. All three attribute readers sized for one element:
`readIntAttribute` 4 bytes, `readDoubleAttribute` 8, `readStringValue` one
`char*` (variable-length) or `H5Tget_size + 1` (fixed). `H5Aget_space` was not
among the symbols the app loaded, so no guard was possible.

### Prediction, written before running
A 3-double attribute writes 24 bytes; a 4-element fixed string of per-element
size 8 writes 32.

### Result — measured against the repo's own bundled `libhdf5.dylib`
Buffer filled with a canary, highest changed byte counted. Independently
re-measured by the refuter with a fresh `malloc` per case, two fill patterns
and a full changed-byte count — same numbers, no undercount, no write below
the buffer:

| attribute | elements | bytes written | app's buffer | `H5Aread` status |
|---|---|---|---|---|
| control | 1 double | 8 | 8 | 0 |
| `trip` | 3 doubles | **24** | 8 | 0 |
| `flags` | 3 × int32 | **12** | 4 | 0 |
| `units` | 4 × S8 | **32** | 9 | 0 |
| `vunits` | 4 varlen | **32** | 8 | 0 |

Prediction met. **`H5Aread` returns success in every overrunning case**, so
this was the only available signal.

Stack corruption confirmed by direct probe, not inference: sentinels around
the pattern show the 8 bytes above `value` overwritten with
`0x4004000000000000` = 2.5, the attribute's second element. Not heap-boxed.

The visible consequence is a wrong scientific number, not a crash. With a
3-element `Q_pixel_size`, `pixelCalibration()` returned
`qSize: 0.25, qUnits: "1/A", qrFlip: true` — the first element of each — having
written 24 bytes into 8.

### OVERTURNED: the crash claim
The diagnosis originally said this "crashes `H5Reader` inside
`discoverPrimaryDataset`, exit 133". That is true of one prebuilt binary
(40/40) and **false of a fresh build from the same sources with the same
documented command** (40/40 clean, cube discovered). Identical module name and
byte size, `MallocGuardEdges`, `MallocScribble`, `MallocNanoZone=0` — none
reproduced it. The SIGTRAP is allocator-layout luck. Restated: the overrun
*can* crash; the reproducible evidence is the canary and the stack probe.

### NARROWED: reachability
Reachable-on-open is real by reading (`H5Reader.swift:290-291, 395-396,
780-796, 841`). What is **not** shown is any real writer that emits a
multi-element `units`/`name`: py4DSTEM's own EMD v13 reader treats them as
single strings and emdfile writes them that way, and no producer was found in
`References/`. D003 is a real latent overrun with an **unproven trigger
frequency**, and the fixtures are hand-made.

### Prior art the first draft missed
`core-data-01` in the 2026-08-31 review is **confirmed, high** — "Sidecar HDF5
string reads assume scalar variable-length storage without checking the file
type or extent" — and its `remainingVerification` asks literally for nonscalar
runtime evidence. D003 supplies it. `D029`/`D053` in the new register repeat
it. `BraggVectorEMDWriter.swift` still carries the same gap (`open-items.md`).

### Fix and its gate
`H5Aget_space` added; `attributeIsScalar` reuses the existing
`elementCount(spaceID:)`; the three readers refuse a non-scalar. This applies
the file's own policy — every DATASET reader there already guards the same way
— rather than inventing one. An `H5T_ARRAY(double,3)` datatype in a scalar
dataspace would defeat a naive count guard, but HDF5 refuses that conversion
outright (`H5Aread` returns −1, 0 bytes written), so the count guard suffices.

`tools/datacube-discovery-test` gained `d1_multielement_attributes.h5`, whose
multi-element attributes are each paired with a scalar the reader must still
read — so a guard that refuses everything cannot pass.

**Broken before it was trusted**, twice. Against the unfixed reader the case
first failed with the silently wrong calibration above; once the fixture was
tightened so the EMD dim-vector fallback could not supply a value, it failed
with discovery **refusing a genuine rank-4 cube entirely** ("No 4D or 3D
dataset found"), because a 3-element `name` attribute whose first element is
`_labels_` reads as a label stack. Exit 1 unfixed, exit 0 fixed.


---

## Gate B — 2026-09-11

An independent refuter, briefed to refute rather than approve, applied **25**
mutations (20 on the preparer, 5 on `H5Reader`) and cross-checked the port
against py4DSTEM's real `AffineTransform` class extracted by AST, not a
transliteration. Its verdict: *the science is right; the gate around it was not
tight enough to protect it.* Four mutations survived. What follows is what
changed as a result — every fix below was itself broken before it was trusted.

### Could not be refuted
- **The axis mapping is correct** (§N1). `cx` is the detector COLUMN
  (`Shaders/CenterOfMass.metal:59-67`), and `RotationCalibration.swift:86-95`
  pairs `x'` with the scan COLUMN. The app's frame is "index 0 = column" in
  both spaces — a consistent global relabel of py4DSTEM's "index 0 = first
  array axis" — so θ is fitted and applied in the same frame.
- **The py4DSTEM correspondence is exact.** Run through the real
  `AffineTransform` and `_calculate_scan_positions_in_pixels`
  (phase_base_class.py:1868-1917), the port reproduces every one of the
  harness's cases **to zero at float32 precision** once the documented padding
  DEVIATION is applied. The row-vector form, the −θ sense, rotation about the
  per-axis mean, the transpose flipping positions *and* sampling, and the
  clip-to-non-negative are all confirmed against the source.
- **The raster order is right, and necessary.** py4DSTEM's
  `meshgrid(indexing="ij")` ravels axis-0-major = column-major under this
  mapping; the port emits row-major, which is required because the amplitudes
  are written at `(scanRow * rx + scanColumn)`.
- **The H5Reader guard holds** (§N6), including the claim most likely to break.
  A C probe against the repo's own `libhdf5.dylib` confirms HDF5 itself refuses
  `H5T_ARRAY(f8,3)`, `H5T_ARRAY(i4,3)`, compound and oversized fixed-string
  scalars — `H5Aread` returns −1 and writes **zero** bytes — so the count guard
  suffices even though `H5Sget_simple_extent_ndims` reports rank 0 for all of
  them. All three `H5Aread` sites are guarded; no fourth exists. Each of the
  three guards is separately load-bearing against the `d1` fixture, and the
  fixture's scalar/non-scalar pairing means a guard that refuses everything
  fails (`e4_results_no_attribute.h5`).

### Refuted, and fixed
- **SEVERE — the two calibrated scalars were pinned by nothing.** All seven
  cases ran at `scanSampling 1.0` and `qSampling 0.05`, and positions scale
  linearly in both, so any transformation that is the identity at those values
  was invisible. Three mutations proved it: the scan step **hard-coded to 1.0**
  (the calibrated input deleted from the code), the scan step **squared**, and
  the reciprocal sampling **hard-coded to 0.05** — each **exit 0, all passed,
  17 controls still biting**. The `controlsThatBit >= 12` anti-vacuity guard is
  blind to this: it measures reference-vs-control separation, which does not
  move. This is the S2 lesson in its original shape.
  *Fixed:* `POSITION_CASES` gains **case 7** — `ry 5, rx 9, qy 32, qx 48,
  rotation 37.2°, transpose true, scanSampling 0.37, qSampling 0.0213`, both
  samplings different from every other case, on a non-square scan at a
  sign-discriminating angle. `SCAN_SAMPLING`/`Q_SAMPLING` become per-case
  defaults rather than module constants.
  *Broken before trusted:* all three mutations now die **at case 7 and nowhere
  else** (exit 133); the real code passes 8 cases / 21 controls.
- **SEVERE — the origin shift was gated by nothing.** `calibration.originQX`/
  `originQY` drive the detector resample, and the harness read only
  `prepared.positions`, which the origin does not touch. Replacing both with
  `0` left the gate green.
  *The refuter's own remedy was rejected after being tested*: it proposed a
  position case with a non-zero origin, which would be **vacuous** — the origin
  moves amplitudes, and no amplitude from `prepare` is asserted. Implemented
  instead as an **analytic invariant**: at an integer shift the bilinear
  resample reduces exactly to a circular shift, so shifted amplitudes must
  equal the unshifted ones rolled by that many rows (`originQX`) or columns
  (`originQY`), with an anti-vacuity floor on the separation.
  *Broken before trusted:* `origin_ignored`, `origin_axes_swapped` and
  `origin_sign_flipped` all die on it (exit 133); the real code passes with a
  separation of 2.335, far above the 1e-3 floor.
- **HIGH — the axis-mapping note was a non-sequitur citing the wrong branch.**
  It grounded the mapping on the `com_measured_x`/`_y` expressions at
  `phase_base_class.py:1122-1128`. That is the **transposed** branch (`:1120` is
  the comment `# Transposed`; the untransposed one is `:1090-1097`), and more
  fundamentally those expressions are **symmetric under renaming x and y
  together**, so they establish no mapping whatever. The `RotationCalibration
  .swift:73-79` citation pointed at a doc comment and some `let` bindings, not
  the load-bearing code. The conclusion survived; the reasoning did not.
  *Fixed:* the comment now derives the mapping from the **gradient pairing**
  (`phase_base_class.py:1099-1108` against `RotationCalibration.swift:86-95`)
  plus `CenterOfMass.metal:59-67`, and says plainly that the first version was
  wrong.
- **MODERATE — the doc double-counted two mutations as one each.** Corrected
  in §D002 above.

### Recorded as a known limit, not fixed
- **Ground truth is not independent for the axis mapping.**
  `reference.py` hard-codes `np.stack((c.ravel(), r.ravel()), axis=-1)` with a
  comment *stating* "axis 0 = column". Both sides of the comparison share that
  assumption, so a mapping that was wrong in the same way on both sides would
  pass green — the L3 trap. The `axis_mapping_transposed` mutation only catches
  a Swift-side-only transposition. What actually protects the mapping is not
  this harness but the two independent traces above (the Metal kernel and the
  gradient pairing), which is why they are now written into the code. Stated
  here so nobody reads the green run as covering it.
- **"Source-locked" means text-locked, not behaviour-locked.** `reference.py`
  is an idealised float64 re-derivation; py4DSTEM's `AffineTransform.asarray()`
  is float32 and casts `origin` to float32. The divergence is 1e-6 at case 1,
  against a tolerance of 1e-3.
- **The padding DEVIATION, now measured:** exactly `(qy - qx)/2` object pixels
  on the row coordinate — 8.0 px at 32x48, 16.0 px at 48x16, 0 on a square
  detector. A uniform translation along one axis, so relative scan geometry is
  untouched and the reconstruction is unaffected; what moves is the object
  canvas origin and `objectHeight`. Left alone, as D002 recorded.
- **`originQX` names the ROW.** `PtychographyPreparation.swift` adds `originQX`
  to the row and `originQY` to the column. That is correct —
  `ParallaxPreprocessing.swift:98-99` sets `originQX: Double(apertureCenterY)` —
  but it is the opposite sense to the `cx` = COLUMN convention documented a few
  lines below, and the two fields have no consumer anywhere else in
  `mac4DSTEM/` or `tools/`. The new origin invariant pins it executably, so a
  reader who "corrects" the naming now fails a gate instead of shipping it.
