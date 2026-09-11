# Gate D — the origin calibration un-ticks after Imaging (2026-09-11)

Owner drive, `downsample_Si_SiGe_exp.h5`. BOTH triggers apply: a scientific
number can move (every downstream product was computed against a different
origin), and the cause is not established.

## The observation, from the owner's screenshots — facts only
1. Prepare, 14:17-14:18: `Origin & probe` = "Not quantitative", **Origin:
   Measured**, probe 3.74 px, Fit RMS 9.72 px over 90% of positions.
   "Computed this session": Origin calibration GREEN, R-Q rotation GREEN.
2. Imaging, 14:19: "Computed this session": Origin calibration NOT GREEN,
   R-Q rotation still green.
3. Prepare again: `Origin & probe` = "Mixed", **Origin: Manual** · Probe 3.74 px
   (Measured in app). Toolbar action has changed to "Calibrate Origin".
4. Every later product (Bragg disks 248111 peaks, strain, ACOM, DPC) ran after
   that. ACOM provenance: `origin_reference apertureCentre`,
   `origin_reference_is_measured false`.
5. The final Info panel reports `Aperture (detector px) Center x 64.0,
   Center y 64.0` on a 128x128 detector — i.e. EXACTLY the geometric middle.
6. The strain map is badged **Quantitative** throughout.

## H1 — the diagnosis as currently believed
`AppState.updateAperture(_:)` (AppState.swift:3110) is the only writer that
clears the fitted origin. Its centre-change branch deliberately discards
`calibration.origin` AND `recordedOriginX/Y`, sets `originProvenance = .manual`,
stashes the maps in `supersededFittedOrigin`, sets `canRestoreFittedOrigin` and
writes a transient `statusText`. `referenceOrigin` (Calibration.swift:723) then
falls through past `.fittedMaps` and `.recordedMean` to `.apertureCentre`, which
the UI renders as "Manual" and whose `isMeasuredBeamCentre` is false — matching
fact 4 exactly. Its only caller is `ImagePanes.swift:204 onEdited`, the drag on
the diffraction pane. So: the owner dragged the detector centre in Imaging, and
the app did what it was designed to do (Gate B note, 2026-08-28).
Under H1 the DEFECT is not the clearing but that it is effectively silent: the
warning is one transient status line, and the persistent signal is a tick
quietly going grey, which is what the owner actually noticed.

## H2 — the alternative
Something other than a centre change cleared the origin. `applyDetectorPreset`
(AppState.swift:3332) is already EXONERATED: it writes `aperture.inner/outer`
only, never the centre, and never calls `updateAperture`. So under H2 the
culprit is workspace navigation, `runVirtualDetector`, or a path not yet read.

## The observation that would REFUTE H1
Fact 5. The aperture centre is exactly (64.0, 64.0) — the DEFAULT geometric
middle of this detector. If the owner had dragged the centre, landing on exactly
64.0/64.0 is a coincidence; and if the centre never changed from its default,
`updateAperture`'s branch never ran and H1 is false.
Second, weaker refuter: no "Restore Fitted Origin" control is visible in the
Prepare screenshot taken after the change, although H1 says
`canRestoreFittedOrigin` must be true. (Weak: it may sit inside the collapsed
"Fit diagnostics & advanced correction" section.)

## Predicted outcome, written BEFORE the experiment
- If H1 holds: with a fitted origin present, `applyDetectorPreset` followed by
  `runVirtualDetector`, and a workspace switch to Imaging and back, all leave
  `calibration.origin` NON-NIL; and only `updateAperture` with a changed centre
  clears it, leaving `originProvenance == .manual`, `canRestoreFittedOrigin ==
  true`, and `referenceOrigin(...).kind == .apertureCentre`.
- If H2 holds: at least one of those non-drag paths returns `origin == nil`.

## Separate question, same evidence, NOT to be conflated
Fact 6: the strain map is badged **Quantitative** while the origin is
`.apertureCentre` and `origin_reference_is_measured` is false. Whether that
badge is correct is its own question — a whole-scan-mean strain reference
cancels a CONSTANT origin offset, so it may be defensible — but it must be
established, not assumed. Recorded here so it is not lost.

## Evidence added 2026-09-11, after the pre-registration was written

**The owner, asked directly, says he DRAGGED the detector to a new position**
in Imaging (not a preset, not a size change). This is witness testimony, not an
instrument reading, and it is recorded as such — but it is the only direct
evidence of the action, and it supports H1's premise that
`updateAperture`'s centre-change branch ran.

**The refuting observation is NARROWED, not dissolved.** Fact 5 still has to be
explained: a drag that ends at exactly (64.0, 64.0) is only unremarkable if the
drag QUANTISES to whole detector pixels, in which case 64.0 is simply the
nearest pixel to the central beam. If the drag carries sub-pixel precision,
landing on exactly 64.0/64.0 remains a coincidence and H1 is still in doubt.
Open question for the refuter (attack A): does the diffraction-pane drag
quantise the aperture centre to integers?

**Unaffected by the testimony:** the separate question of whether the strain
map's **Quantitative** badge is correct while `origin_reference_is_measured` is
false. That does not depend on WHY the origin was cleared, only on the fact
that it was, and it is the more serious of the two questions.

---

# Outcome — Gate D closed 2026-09-11, refuter run

## H1 is UNREFUTED and quantitatively strengthened

The refuter dumped the sidecar the owner's session restored from,
`References/training_dataset/downsample_Si_SiGe_exp.mac4dstem.h5.h5`:

```
qx0 map mean 54.5009   (min 50.431  max 58.570)
qy0 map mean 69.3133   (min 62.589  max 76.037)
measured-fitted RMS    9.7202 px
probe_semiangle        3.73834 px
```

`9.7202` and `3.73834` are the owner's on-screen **9.72 px** and **3.74 px**, so
this is his origin. Both paths that install it also move the aperture onto its
mean (`AppState.swift:2937-2938` restore, `:4069-4072` calibrate, via
`SessionCalibrationFramePolicy.swift:104-108`), so with the app's axis swap the
live aperture centre was **(69.3133, 54.5009)** — **10.884 px** from (64.0,
64.0). The centre moved. Further, `originProvenance = .manual` has **exactly one
writer in the repository**: `AppState.swift:3134`, inside `updateAperture`'s
centre-change branch. The "Origin: Manual" the owner read is itself a
reproducing observation that that branch ran.

## The pre-registration's designated refuter was INVALID — recorded, not tidied away

Fact 5 ("the aperture centre is exactly 64.0, 64.0, so a drag is implausible")
could not discriminate, in either direction, for two independent reasons:
- `ApertureOverlay.emit` **rounds the centre to whole pixels** before publishing
  (`PaneOverlays.swift:569-572`: *"Every handle drag goes through here"*). A drag
  always produces an integer. 64.0 is what a drag makes, not a coincidence.
- The Info panel prints `%.1f` (`WorkspaceInspector.swift:317`), so "64.0" is
  anything in [63.95, 64.05).
Elevating a non-diagnostic fact to "the observation that would REFUTE H1" was the
error in the pre-registration, and it is left above verbatim.

## H2 is dead — the exhaustive sweep

Writers that can nil `calibration.origin`: `AppState.swift:2944` (restore,
`!restoredMaps`), `:3122` (`updateAperture`), `CalibrationReReference.swift:178`
and `:212`. `CalibrationReReference.apply` has two production callers,
`AppState.swift:2495` and `SessionCalibrationFramePolicy.swift:123`, **both
inside `activate`** — unreachable from a workspace switch. `selectWorkspace`
(`:1338-1343`) touches navigation only. `applyDetectorPreset` (`:3332`) writes
`inner`/`outer` only. None of the non-`updateAperture` paths sets `.manual`.

**Refuted hypotheses, dated 2026-09-11 — do not re-walk:**
1. A re-`activate` resetting the aperture to `Aperture(centerX: qx/2, ...)`
   (`AppState.swift:2382`) — the only code producing exactly (64,64). Refuted:
   it resets `calibration` wholesale, which would have taken the R-Q rotation
   tick down too, and the owner's screenshots show rotation stayed green. It
   also sets `.geometricDefault`, not `.manual`.
2. A crop/re-reference on workspace entry. Refuted: both `apply` callers are
   inside `activate`.
3. The `!restoredMaps`/`.sessionMean` restore branch (`:2942-2951`). Refuted on
   two counts: it still places the aperture at the session centre
   (`SessionCalibrationFramePolicy.swift:111-115`), and it leaves
   `recordedOriginX/Y` set, so `referenceOrigin` would return `.recordedMean`,
   not the `.apertureCentre` the ACOM provenance actually shows.
4. A drag-coordinate mapping bug in `centerHandle`. NOT pursued to a conclusion —
   the inverse map uses the same `geometry.size` used to draw, so it is
   self-consistent, but refuting it properly needs the app driven.

## The causal link to Imaging

Nothing about the Imaging workspace clears anything. `.image` defaults to
`analysisMode == .virtualDetector`, which is the condition that puts the
draggable `ApertureOverlay` on screen at all (`ImagePanes.swift:199`). Imaging is
where the drag becomes possible, not where the origin is destroyed.
