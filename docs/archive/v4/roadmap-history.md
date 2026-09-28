# Roadmap — superseded sections (moved 2026-09-23)

Verbatim sections moved out of `ROADMAP.md` when it was brought current for
HEAD after the v4.0.0 release (2026-09-23). Each is superseded by the cited
evidence; nothing here is live.

## "Next planned sequence — registered 2026-09-19" (superseded: items 1 and 2 both done)

Superseded by `docs/status.md` § Handoff and `docs/releasing.md` § Releases
— v3.1.0 shipped as part of v4.0.0 (2026-09-23, `d9fd32e`) and the
Materials Project importer's S4a/S4b/S5 landed 2026-09-21 (first live
fetch still pending). Original text:

1. **Release v3.1.0:** the three acceptance cubes are restored; run `all` and the archive rehearsal before the credentialed cut. Full-cube Friedel bar/ETA remains an on-screen check, not a gate. No feature slips in.
2. **Materials Project importer:** build the pre-registered, user-initiated importer with offline provenance; settle its UX choices before UI code.
3. **Orientation coverage:** prepare monoclinic 2/m first if the owner confirms it; it unlocks β″ and is a separate Gate D/B feature.
4. **Scientific debts and phase validation:** diagnose R–Q; decide T1 and Parallax experiments; use the paper truth set before detector or learned-model work.

## "Learned disk candidates — pre-registration" (superseded: shipped in v3.0.0, 2026-09-11)

Superseded by `docs/releasing.md` § Releases (v3.0.0 row: "the learned disk
detector, the flat/file probe kernel"). Original text:

A second `DetectorClass` beside the classical one: a Core ML U-Net paints a
disk-centre heatmap on the Neural Engine, and the existing
correlation/centroid refinement measures each candidate to sub-pixel;
opt-in, off by default. **Verdict (step 3): passed 2026-09-08** — on the
frozen hand-labelled test set the net finds the same real disks with far
fewer inventions (256 px: 0.667 / 0.840 against the classical 0.487 / 0.485).
Full pre-registration:
[`docs/archive/v3/learned-detector-preregistration-2026-09-07.md`](../v3/learned-detector-preregistration-2026-09-07.md).

## "Settings window, Xcode-style sidebar" (superseded: landed and driven)

Superseded by `docs/status.md` § Handoff ("Unverified on screen": the
Settings scene and mp-id sheet were owner-driven 2026-09-21) and by
`docs/releasing.md`. Original text:

**Settings window, Xcode-style sidebar** (owner, 2026-09-21) — grows the
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

## "Bottom area as a second workspace, Xcode-style" (superseded: closed 2026-09-22 night)

Superseded by `docs/status.md` § Handoff ("Window design residuals":
closed 2026-09-22 night, ADR 008/035–037) and `docs/open-items.md`, which
carries the live residuals (the toolbar's leading jump, inspector-kit
gaps, the parked panel-blank lead). Original text:

**Bottom area as a second workspace, Xcode-style** (owner, 2026-09-21,
revised 2026-09-22) — the infobar is the centre column's fixed-height
divider and full-width drag handle, moving from its bottom to its top;
Output / Run / Lineage never change its position. The 2026-09-21
implementation (ADR 034) was driven and rejected. The decided anatomy is
`docs/window-design.md` §1 and §6: full-height collapsible side panels,
room actions in a centre-only header that flexes with them, then the
Prepare reference room. Phase 1 has no recorded owner acceptance. The
lineage graph and copy/search/filter follow later.

## The 2026-09-23 sequence, superseded 2026-09-28 (moved verbatim from ROADMAP.md)

### Next planned sequence — registered 2026-09-23

The 2026-09-19 sequence's first two items are both done: v3.1.0 shipped as
part of v4.0.0 (2026-09-23) and the Materials Project importer landed
2026-09-21 (superseded text: `docs/archive/v4/roadmap-history.md`). Current
order, from `docs/status.md` § Handoff and the 2026-09-23 overnight records:

1. **Owner decisions and one Gate D first:** the known-variants guard shipped on 2026-09-23
   (ADR 038). Still owed: the R–Q displayed sign convention (`docs/open-items.md`); the Al
   lattice constant `DEVIATION` (4.0495 vs 4.04 Å, a `kMax` knife edge); a macOS 27 CI runner;
   the object-level pass bar (T4 draft). Gate D next: the owner's real Al-Mg-Si cube, where the
   matrix almost never wins (`archive/v4/almgsi-drive-2026-09-23.md`).
2. **Materials Project S6:** the live fetch works (owner, 2026-09-23); owed are
   the pre-registered comparisons — Al/θ′/T1 cells vs the paper's CIFs, a
   phase map through them within the S1 band, mp-1185307 refused.
3. **Orientation coverage:** monoclinic 2/m first, once the owner confirms
   it — it unlocks β″ and is a separate Gate D/B feature.
4. **Scientific debts:** the parallax default bin schedule (diagnosed,
   fix owed), the cross-phase completeness guard (candidate built, parked),
   T1's remaining detection-limited recall — each its own Gate D, in the
   order `docs/status.md` § Handoff names.


## Moved from ROADMAP.md at the 2026-09-28 closeout (finished items)

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


- **Settings window, Xcode-style sidebar** (owner, 2026-09-21) — the
  Materials Project key, general/appearance/analysis/advanced sections, one
  `AppPreferences` state owner. **Landed 2026-09-21** (`900fe7b`) and driven
  by the owner the same night. Full design:
  [`docs/archive/v4/roadmap-history.md`](docs/archive/v4/roadmap-history.md).
- **Bottom area as a second workspace, Xcode-style** (owner, 2026-09-21,
  revised 2026-09-22) — **closed 2026-09-22 night**: the macOS 27 rebuild on
  Apple's inspector guidance, driven and accepted by the owner on a real
  cube (ADR 008, 035–037, `docs/status.md` § Handoff). Live residuals: the
  toolbar's leading jump at a long file name, inspector-kit gaps, a parked
  panel-blank lead (`docs/open-items.md`). Earlier, rejected design:
  [`docs/archive/v4/roadmap-history.md`](docs/archive/v4/roadmap-history.md).
