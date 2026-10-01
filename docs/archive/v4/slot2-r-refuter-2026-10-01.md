# Slot 2 lane R — refuter (Fable 5.1), 2026-10-01

# Lane R (R3 + R2) — independent refuter, 2026-10-01 (Fable 5.1, read-only; experiments under $SP/R/refute/)

Read: BRIEF.md, report.md, RULES.md, CLAUDE.md, the uncommitted diff (parallax-ptycho-real-probe/main.swift, singleslice-ptychography-test/{main.swift,run.sh,truth.py}),
Core/Analysis/SingleslicePtychography.swift 340–630 and 719–727, py4DSTEM ptychographic_methods.py 1811–1925 + 2097–2180,
singleslice_ptychography.py 610–1015, phase_base_class.py `_constraints`, ptychographic_constraints.py 29–57 + 421–470 + 1139–1200;
logs harness-4, mut/all, gr-compare, ref64-{gd,dm,mask}, sweep-1, seeds-fixp-1, sens-1.

## (a) R3 truth harness — HOLDS WITH CORRECTIONS
- Independence: the generator (truth.py `make`) is separate numpy code, but it is the SAME forward model both engines assume
  (fractional Fourier probe shift, periodic patch, |fft2|²) and the reconstruction STARTS FROM THE EXACT PROBE (scaled to the
  mean intensity; noiseless, pure-phase, so the scaling is the true one). This is a self-consistency test of the inverse operator
  and the defocus convention, not a test of probe recovery or of a model mismatch. Fine for R3's purpose (does the port invert
  what it models, at the right sign); it cannot catch a shared convention error and it says nothing about real-probe robustness —
  the record must say so (one line). The wrong-sign control (Pearson 0.12–0.21, registration fails by 9–25 px) shows the score is
  sign-sensitive, which is the control that matters.
- Bars vs distribution (harness-4.log, seeds-fixp-1.log): GD Pearson ≥ 0.95 vs measured 0.980–0.987 on 5 fixtures; rms ≤ 0.03 vs
  0.017–0.018; app–py ≤ 5e-2 vs 1.8e-2 max (2.8×); wrong-sign < 0.5 vs 0.12–0.21; shift < 0.2 px vs ≤ 0.024. Supported by 5
  fixtures (3 defocus × seed 1 + 2 seeds at df400), and NOT vacuous: check (5) proves the clamp-off run lands at 0.20–0.31 above
  the 5e-2 bar, and the mutation log shows the wrong-sign check flips (0.9833 vs 0.9834) when the control is built at +D.
  CORRECTION: the DM nm 1 parity bar (limit 0.1 over 8 it) is pinned on a map the lane itself shows is expanding from iteration 1
  (per-it gap 2.7e-2 at it ≤ 8, 2.7e-1 by it 16 on df200; 25 % at it 3 on graphene). Measured on 3 fixtures only (seeds 2/3 ran at
  nm 0.02), margin 3.7× on a chaotic trajectory — this is the one bar that can go red on a different Accelerate build without any
  port change. Keep the nm 0.02 bar (10× margin, 5 fixtures through 8 it); PRINT the nm 1 gap instead of pinning it, or pin it at
  ≤ 4 iterations.
- Mutations spot-checked in mut/all.log: clamp-off → "GD error history differs … 0.19666 (limit 5e-2)" (the new bar); neg-control-off
  → "WRONG-SIGN … 0.9833 vs 0.9834" (the new check); scorer-mean → Pearson 0.98646 vs 0.98333 (the cross-check); dm-nm-mismatch → the
  new DM parity check ("851 (limit 0.1)"). As the report itself says, defocus-sign and dm-projection-a are caught by PRE-EXISTING
  checks first, so the harness never reaches the new ones for those two — the "6 mutations red" claim is true of the harness, but
  only 4 of the 6 exercise the NEW checks. Say "4 new checks broken, 2 mutations caught upstream".
- Scorer: registration = argmax of the circular cross-correlation of mean-removed, crop-windowed phase maps + 1-D parabolic
  refinement per axis; phase offset = arg Σ o·conj(t) on the crop; Pearson of the phases; rms of the offset-removed wrapped
  difference. Correct for small phases (truth ≤ 0.6 rad, no wrap); the Swift twin is cross-checked against truth.py's at 2e-3
  (check 1) and the mutation shows the cross-check bites. Degenerate output: a flat phase gives varianceA = 0 → Pearson = .nan →
  `nan >= 0.95` is false → the check FAILS (sweep-1.log indeed prints "pearson nan" for the collapsed DM objects). A blurred object
  could pass 0.95 — the bar is a correlation, not a resolution test; acceptable, but the record should not call 0.98 "reaches the truth"
  without the rms (0.017 rad on a 0.097-rad-std truth = 18 % residual, i.e. GD at 32 it is NOT converged — the error history is
  still falling at it 32 in sens-1.log). Wording.
- The harness's py4DSTEM run is at fix_probe_com=False and object_positivity irrelevant (complex); py4DSTEM's DEFAULT is
  fix_probe_com=True. So "app = py4DSTEM" is at matched non-default settings on the py side; flipping the clamp default alone does
  not give parity at py4DSTEM's defaults (the probe-CoM constraint is a second switch, app default off). State it.

## (b) "the ported DM IS py4DSTEM's DM_AP" — HOLDS (operator read), with one correction on the inference
Side by side (SingleslicePtychography.swift 439–535 vs `_projection_sets_fourier_projection` 1811–1925 and
`_projection_sets_adjoint` 2097–2180): a = −α, b = 1, c = 1+α, x = 1−a−b, y = 1−c identical; first iteration prev = overlap on both
(py: `exit_waves is None → overlap.copy()`; app: `iteration == 0 ? fourier : retained`); projection amplitudes·F/|F| with the
|F| = 0 branch → (measured, 0) on both (py: exp(i·angle(0)) = 1); exit = x·prev + a·overlap + b·projected; adjoint: object REPLACED
by Σ conj(P)·E × 1/sqrt(1e-16 + ((1−nm)·ΣP²)² + (nm·max)²), probe likewise from the PRE-UPDATE patches — same on both; error
normalised by Σ amp² on both; constraints after the full pass. Positions rounded half-even on both. No operator difference
missed, and the E0 run shows iteration-1 errors agree to 6e-7 on bit-identical inputs. Settings that could make py4DSTEM converge
where the app does not: none in the loop — the lane tried nm 1/0.5/0.2/0.1/0.05/0.02 and fix_probe; py4DSTEM's remaining
DM-relevant switches (fix_probe_com, constrain_probe_amplitude, fix_probe_aperture, butterworth/gaussian/tv) are all exposed or
off by default in the app too and are regularisers, not the operator. No vendored tutorial uses DM_AP (grep: 0 hits outside the
process/phase sources).
CORRECTION of the inference "the algorithm diverges on both sides, remove it": what was shown is that py4DSTEM's single-pass
DM_AP (one overlap-projection pass with the joint probe update, no inner iterations) diverges in float32 at every nm tried. See the
refuter's float64 run below for whether that is intrinsic or a precision/probe-update matter — it decides whether A is
"finish-or-remove" or premature.

## (c) The clamp — HOLDS
- Gating: ptychographic_constraints.py `_object_constraints` (the block after "# amplitude threshold (complex) or positivity
  (potential)", lines ≈ 455–460 of the pinned file): `if self._object_type == "complex": current_object =
  self._object_threshold_constraint(current_object, pure_phase_object)` — no flag; `_object_threshold_constraint` (29–57) does
  `amplitude = xp.minimum(xp.abs(current_object), 1.0)` unless pure_phase. Called from `_constraints` every iteration
  (singleslice_ptychography.py 953–990). truth.py source-locks both strings. Unconditional: confirmed.
- Explains the GD gap: gr-compare.log, same cube, same −600 Å, same py run: clamp on max 1.7 % (per-it 0.3–1.7 %), clamp off
  (R1 arm a2) max 8.6 % (per-it up to 8.6 %); synthetic clamp-off 0.20–0.31 vs on ≤ 1.8e-2 and the arbiter shows the on-case
  residual is the float32 band. Holds. (R1's "8–15 %" spans its arms; this cube's a2 arm shows 8.6 % — the status line should quote
  the arm it was measured on.)
- Flipping the App default to true: for a user it bounds |O| ≤ 1 each iteration (a transmission function cannot exceed 1 — physically
  motivated, and it is how py4DSTEM resolves the probe/object scaling ambiguity, its own docstring); phase untouched; on the
  pure-phase synthetic the truth score moves < 2e-3. On a real cube with absorption/thickness it changes the amplitude map and the
  probe scale (the ambiguity is re-split), i.e. a number a user sees moves → that flip is a Gate D-trigger change for the lane that
  makes it, with the graphene arm r2d as the before/after. No test pins the old default: grep of mac4DSTEMTests finds only
  `SingleslicePtychographyOptions()` used for export/plumbing (ParallaxStage4Completeness, ParallaxOriginAndMean:176 maxWorkingBytes,
  SingleslicePtychographyExportTests:19) and ResultPresentationTests:36 which pins the EXPORT STRING "constrain_object_amplitude":
  "true" as a literal, not the default. Replay/sidecar reads the stored value (ResultExport.swift:986), so old sessions keep theirs.
  One wording defect in the room: UI/ReconstructionSettings.swift 263–274 — the `.help("Sets reconstructed object amplitude to one
  after every iteration.")` is attached after the Pure-phase row (correct for that row); the "Limit object transmission to 1" row
  has no help. Fine as is; do not describe the clamp as "sets to one".

## (d) float32 as the explanation of the residual gaps — HOLDS for GD, with the scope stated
ref64-gd.log / ref64-mask.log: the SAME float64 code vs its float32 twin differs by 4.2e-3 after one GD iteration from identical
inputs, and by 1.49e-7 once the projection phase is zeroed where |F| < 1e-6·max (predicted in P4 before the run, held). That
isolates the difference to the zero-model Fourier pixels (outside the probe aperture at the flat start), where A·F/|F| takes a
rounding-seeded phase — a mechanism, not a catch-all, and every pair (f64, f32-twin, app, py) sits at ≈ 5e-3 after it 1. The
mask forces both dtypes to the same phase there, so strictly it shows WHERE the difference lives; that those pixels carry rounding
noise in the model and real signal in the data is arithmetic (band-limited probe × flat object). Sound. Scope: it explains the
GD band (≤ 1.8e-2 relative on an error that falls to 4e-5) and the DM split at nm 1 only in the sense that an expanding map
amplifies that band; the refuter's float64 run below shows the DM COLLAPSE itself is not float32.

## (e) Reproducibility of the proposed doc lines — REFUTED as written (fixable)
The status/open-items/plan lines quote: sweep over nm (sweep-1.log), seeds 2/3 and the fixed-probe runs (seeds-fixp-1.log), the
arbiter (ref64-*.log), the graphene arms r2a–d and gr-compare.log, "diverges … at any normalization by 32", "on graphene by 4".
Only the harness numbers (truth.py + main.swift, committed) are reproducible from the diff. synth.py, ref64.py, the sweep /
seeds / sensitivity drivers, graphene.sh, finish.sh, mutate*.sh and the compare script behind gr-compare.log live in $SP/R only —
session logs are not retained. Must-fix: commit them (small .py/.sh, no .npy/.json dumps) under
docs/archive/v4/slot2-r-record-2026-10-01/ with the logs they produced (harness-4, mut/all, sweep-1, seeds-fixp-1, sens-1,
ref64-*, gr-compare, arm-r2*), or cut every number the harness does not print from the doc lines. Also: "P7 … Runtime < 3 min" was
not held (232–234 s) — the plan Log line must carry 234 s, and the harness's new 4-minute cost belongs in status (the scientific gate
got slower by ~3 min).

## Refuter's own experiment ($SP/R/refute/dm64.py, dm64-wrongprobe.py; logs dm64-1.log, dm64-wrongprobe-1.log; 58 s + 26 s, no lock)
The lane's ref64.py operators (verbatim), float64 and float32, truth-scored at 1/2/4/8/16/32/64 it, clamp on, fixtures df200-s1
and df400-s1 (Pearson / rms rad):
| variant | df200 it 8 | df200 it 32 | df200 it 64 | df400 it 8 | df400 it 32 | df400 it 64 |
|---|---|---|---|---|---|---|
| DM α1 joint probe nm 0.02 float32 | 0.989 | 0.038 (collapsed) | nan | 0.987 | 0.976 | 0.842 |
| DM α1 joint probe nm 0.02 float64 | 0.990 | −0.022 (collapsed) | 0.022 | 0.987 | 0.976 | 0.824 |
| DM α1 joint probe nm 0 (true projection) float64 | 0.986 | 0.027 (collapsed) | — | 0.991 | 0.020 (collapsed) | — |
| DM α1 probe FIXED (exact) nm 0 float64 | 0.994 / 0.011 | 0.997 / 0.008 | 0.999 / 0.004 | 0.996 / 0.009 | 0.998 / 0.007 | 0.999 / 0.005 |
| DM α1 probe FIXED (exact) nm 0.02 float64 | 0.992 | 0.982 (error rising 4.7e-2 → 2.0e-1) | 0.993 | 0.993 | 0.990 | 0.995 |
| AP α0 joint nm 0.02 float64 | 0.972 | 0.985 | 0.985 | 0.981 | 0.969 | 0.950 |
| AP α0 joint nm 1 float64 | 0.324 | 0.089 | — | 0.349 | 0.077 | — |
| GD joint nm 1 float64 | 0.940 | 0.983 / 0.018 | 0.994 / 0.011 | 0.950 | 0.985 / 0.017 | 0.995 / 0.010 |
Wrong FIXED probe (df400, nm 0, float64; defocus × 0.9 / 1.1 / 1.25): DM fixed-probe Pearson at 32 it 0.987 / 0.985 / 0.839 with the
DATA ERROR RISING every iteration (5.3e-3 → 2.0e-1 / 1.9e-1 / 4.4e-1); GD joint from the same wrong probe 0.981 / 0.976 / 0.907
with the error falling (→ 3.5e-4 / 3.4e-4 / 1.6e-3); DM joint nm 0.02 0.954 / 0.969 / 0.937, error rising.
Readings: (1) the DM collapse is INTRINSIC to py4DSTEM's single-pass DM_AP with the joint probe update — float64 collapses on
the same fixture at the same iteration count, so "diverges on both sides" is algorithmic, not the float32 band (the lane's
summary line 2 is right; its (e2) wording "float32 sensitivity of an unstable iteration" should not be read as the cause of the
divergence, only of the app–py split). (2) The true projection (nm 0) does not save the joint update; the normalization floor at
nm 1 is fatal for every projection method (AP too), confirming (f) as the it-1 failure cause and refuting it as the late one.
(3) The one converging DM is probe FIXED at the EXACT probe and nm 0 — it then beats GD at every checkpoint (0.999 / 0.004 rad at
64 it) — but it is a fixed point of a known-probe problem; with a probe 10 % wrong its error history climbs monotonically while
the phase merely stays correlated, and it does not beat GD from the same wrong probe. Not offerable as "DM, probe fixed" for
real data on this evidence (and the lane's P5 at nm 0.1 is the same picture with a floor added). (4) AP (α 0, nm 0.02) is the
only stable joint-probe projection variant; it is worse than GD at 64 it and would be new tuning surface, not a parity feature.
(5) On the one real cube py4DSTEM's own DM at the best nm diverges by it 4 (gr/py-dm-m600-nm0.05.log) — option B's "≤ 8
iterations where it beats GD" is a synthetic-only property.

## Must-fix (concrete, before landing)
1. Record reproducibility (e): commit synth.py, ref64.py, the sweep/seeds/sensitivity drivers, graphene.sh, finish.sh, mutate.sh,
   mutate-all.sh, the gr-compare script, and the refuter's dm64.py + dm64-wrongprobe.py, with harness-4.log, mut/all.log,
   sweep-1.log, seeds-fixp-1.log, sens-1.log, ref64-*.log, gr-compare.log, gr/arm-r2*.log, refute/dm64-*.log under
   docs/archive/v4/slot2-r-record-2026-10-01/ — or strip every number the harness does not print from the status / open-items /
   plan lines.
2. Harness: do not PIN the DM nm 1 parity (expanding map, 3 fixtures, 3.7× margin); print it, keep the nm 0.02 pin (10×, 5
   fixtures). tools/singleslice-ptychography-test/main.swift, the `limit` line in check (6).
3. Report/record wording: "6 mutations red" → "4 new checks broken (clamp-off, neg-control-off, scorer-mean, dm-nm-mismatch); the
   defocus-sign and dm-projection-a mutations are caught upstream by R1's probe pin and the 4×6 DM fixture". "GD reaches the
   truth" → "GD at 32 it: Pearson 0.983–0.987, rms 0.017–0.018 rad on a 0.097-rad-std truth, still converging (0.994 / 0.011 at 64)".
   State that the truth harness starts from the exact probe (self-consistency of the inverse + sign; not probe recovery).
4. The clamp line in status/open-items: add that parity was measured at py4DSTEM fix_probe_com=False (its default is True); the
   default flip is one of two switches, and it moves a user-visible amplitude map on real data → whoever flips it runs graphene
   arm r2d before/after and records it (Gate D trigger: a number moves).
5. Plan Log line: harness 234 s (P7's "< 3 min" not held) — the scientific gate's cost grew by ≈ 3 min; say so in status.
6. tools/parallax-ptycho-real-probe/run.sh header: add `--constrain-amplitude` (the lane's own open question 4).

## Second opinion on the owner's DM card
A (remove), and more firmly than the lane put it: the divergence is a property of py4DSTEM's single-pass DM_AP with a joint
probe update, reproduced here in float64 on the lane's own fixtures (collapse at the same iteration), not of the port, the
normalization alone, or float32; the only configuration that converges needs the exact probe held fixed, which is not a real
use; with a probe 10 % wrong its error history rises every iteration; and on the one real cube py4DSTEM itself diverges by
iteration 4 at the best normalization. B's cap ("≤ 8 it, nm 0.02–0.05") is a synthetic-only threshold — exactly the kind of
dataset property CLAUDE.md says not to ship — and C ships a method that fails at its defaults under a label. Removing DM also
deletes the retained exit waves (2× the amplitudes in memory: 1.98 GB vs 0.73 GB per graphene stage, arm-r2*.log) and the
projection-parameter row — the lean-app direction. If the owner wants a projection method later, AP (α 0, small nm) is the
stable one, as a new pre-registered item, not a rescue of this one.

Overall: HOLDS WITH CORRECTIONS — R3 harness sound (one bar to unpin, wording), R2 diagnosis correct and strengthened
(the collapse is intrinsic, float64-confirmed), the clamp finding holds on the source and the logs, the float32 explanation
holds for GD's band; the doc lines fail reproducibility until the scratch scripts and logs are committed.
