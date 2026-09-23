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
