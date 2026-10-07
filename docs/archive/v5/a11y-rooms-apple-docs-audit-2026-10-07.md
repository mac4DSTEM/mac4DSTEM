# Keyboard / VoiceOver audit of the rooms the first check did not cover (2026-10-07)

Companion to `swiftui-a11y-apple-docs-check-2026-10-07.md` (the **first check**; its row numbers are "1st #n" below). Same method: seven
Haiku readers, one per room, read the files **at HEAD** (`git show HEAD:…`, other sessions were editing the tree) and looked every
API up in the Apple documentation MCP; the supervisor re-opened the pages named below and dropped or demoted what it could not
confirm. Nothing was built, run or driven: every verdict is a reading of the code and is **unverified on screen** until a drive
marks it. VoiceOver ("VO") and Full Keyboard Access ("FKA") are the two modes meant. No frozen-shell file is cited, so no row is
marked "needs the owner's picture". Verdicts: OK / RISK (docs do not settle it, drive it) / GAP (something Apple asks for is missing).

## Doc facts the rows rest on (opened by the supervisor)

- **`help(_:)`** (`documentation/SwiftUI/view/help.md`, macOS 13+): "Adding help to a view configures the view's accessibility hint
  and its help tag (also called a tooltip)". **So a `.help` text is also the VoiceOver hint of the view it is attached to.** The
  readers' premise "help-only = VoiceOver cannot hear it" is therefore wrong, and those rows are re-framed below: the risks are
  hint **length** (Apple: "a brief phrase"), and hints sitting on a container instead of the control that has focus.
- **`accessibilityHint(_:)`**: "Provide a hint in the form of a brief phrase, like 'Purchases the item'."
- **HIG VoiceOver** (`documentation/HIG/voiceover.md`): "Provide alternative labels for all key interface elements … Add labels to
  any custom elements"; "Make charts and other infographics fully accessible … If people can interact with the infographic …
  make these interactions available to people using VoiceOver"; "Specify how elements are grouped, ordered, or linked";
  "Inform VoiceOver when visible content or layout changes occur" (names `AccessibilityNotification`); "Support the VoiceOver
  rotor"; "Exclude purely decorative images".
- **HIG Focus and selection** (`documentation/HIG/focus-and-selection.md`): rely on system focus effects; with full keyboard access
  on macOS "you only need to support focus for content elements … not for controls like buttons, sliders, and toggles".
- **`accessibilityZoomAction(_:)`** (`documentation/SwiftUI/modifiedcontent/accessibilityzoomaction.md`, macOS 13+): a handler
  receiving `.zoomIn` / `.zoomOut`; the page's example pairs it with a `MagnificationGesture`. This is the documented twin for
  every pinch-only view (comparison panels, row 6.3) and complements the named zoom actions of 1st #13.
- **`accessibilityRepresentation(representation:)`**: replaces the view's accessibility elements; says nothing about label/value set before it.
- **`TextField`**: `init(_:text:)` "creates a text field with a text label generated from a localized title string"; the
  `label:` form's label "describes the purpose of the text field" (`documentation/SwiftUI/textfield/init-textpromptlabel.md`).
  Hence the title string is the field's spoken name.
- **`Stepper`**: the `label:` closure is "a view describing the purpose of this stepper" (reader, URL in the Bragg row).

Correction to the first check (not edited there: this task writes one file): 1st #28 ("key list only in `.help`, discoverability") is
withdrawn as stated — `.help` is also the VO hint, so the keys are spoken; only its length remains a wording question.

## 1 · Prepare

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 1.1 | CalibrationReadinessRow.swift:263-284 (`manualScale`; Q at :218/:230, R at :240) | Manual Q / R scale fields and unit pickers | **Checked in code:** both fields are titled "Manual scale", both pickers "Unit per pixel"; the Q/R kind is only in the visible row title (`InspectorRow("Manual")`) | HIG VoiceOver: labels for key elements | GAP | med | VO-arrow Q then R: names must differ. Fix: pass "Q pixel size" / "R pixel size" into the field title and picker label |
| 1.2 | PrepareSettings.swift:425-452, 336-353; LayoutPolicy.swift:378 | Semi-axis a/b, Ellipse angle θ, fit annulus radii | **Checked:** the unit is a visible `Text` next to the field; the accessibility label is the bare title, so VO hears a number without px / ° | HIG VoiceOver | GAP | med | VO on each field. Fix: unit in the accessibility label or value |
| 1.3 | PrepareSettings.swift:259-262, 316-323, 361, 457-466; CalibrationReadinessRow.swift:204-212 | Origin method picker, Flip 180°, Fit/Apply Ellipse, Calibrate from Selected Material | Explanations are `.help` = also the VO hint, but long (origin method ~50 words) | `help(_:)`, `accessibilityHint(_:)`: brief phrase | RISK (length) | low | Listen to each. Fix: split `.help` (tooltip) from a one-phrase `.accessibilityHint`; add the phase-model name to the Calibrate hint |
| 1.4 | CalibrationReadinessRow.swift:56-70 | Readiness row: `.contain` container carrying the unlock hint | A hint on a container may not be spoken when focus is on a child | `accessibilityElement(children:)`: `.contain` makes children separate elements | RISK | low | VO-focus each readiness row; if the hint is silent move it to the status element |
| 1.5 | PrepareSettings.swift:177-183 | Readiness verdict label with warning/check symbol | The symbol may be read in addition to the text | HIG: exclude decorative images | RISK | low | `.accessibilityHidden(true)` on the `Image` |

## 2 · Imaging

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 2.1 | PaneOverlays.swift:563-584 | Aperture overlay: `.ignore` element + label + value, then `accessibilityRepresentation { sliders }` (centre X/Y, inner, outer) | Gesture handles have a slider twin — good. But label/value are set **before** the representation (same shape as 1st #19, V31) | `accessibilityRepresentation`: replaces the elements; silent on earlier label/value | RISK | med | VO on the virtual-detector pane: does it speak "Virtual detector circle" + the value, and offer four adjustable sliders; FKA: do the sliders take focus, do arrows step them? |
| 2.2 | PaneOverlays.swift:571-574 vs 711-712 | Centre X/Y slider range | **Checked:** slider is `0…patternWidth-1`, the drag clamps to `0…patternWidth`; a dragged centre on the far edge is outside the slider's range | HIG Keyboards/VoiceOver (consistency) | RISK | low | Drag to the far edge, then VO-increment; fix: same range as the clamp |
| 2.3 | PaneOverlays.swift:565-568, 580-581 | Value string / outer-radius slider by shape | The value always speaks "inner radius N" even for circle and point; for a rectangle "outer radius" is a half-side | HIG VoiceOver: accurate, current labels | RISK | med | VO on a rectangle and a circle. Fix: per-shape label and value ("Half-width"; no inner radius unless annulus) |
| 2.4 | ImagingSettings.swift:75, 110-112 | Notes "Drag the detector…", "Drag on the real-space image to scrub…" | Instruction names only the drag; the detector's slider route is not mentioned; **the region (real-space) drag has no VO/keyboard path** (see 1st #18) | HIG VoiceOver: interactions available to VO | GAP (region) / RISK (wording) | med | VO on the real-space pane with Region shape = Rectangle/Circle: any control moves the region? |
| 2.5 | ImagingSettings.swift:143-166 | BF/ADF/HAADF presets | Labels "Apply Bright Field preset" etc. — good; the geometry is in `.help` = the hint | `help(_:)` | OK | — | none |

## 3 · Bragg Disks

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 3.1 | MapSettings.swift:476-480; ImagePanes.swift:282-298 | "Label centres on click" | **A centre can only be placed by a `SpatialTapGesture` on a clear overlay** — no key, no action, no element; the toggle is reachable, its purpose is not | HIG VoiceOver (interactions for VO); HIG Keyboards "Support Full Keyboard Access when possible" (reader, unchecked) | GAP | high | With FKA / VO try to label a centre. Fix needs a keyboard or action route (owner decision before code: it is new behaviour) |
| 3.2 | MapSettings.swift:603-709 (five Steppers: Maximum peaks, Relative reference peak, Reference min. radius, Min. peak spacing, Edge boundary) | `Stepper(value:in:) { Text("300") }` + `.accessibilityLabel(title)` | **Checked in code.** The visible number is the stepper's label; the accessibility label replaces it with the row title, so the current value may not be spoken. AdjustmentSlider adds `.accessibilityValue` (InspectorRows:398-399); these do not | `Stepper` label = "a view describing the purpose"; accessibilityValue = the value | RISK (pending drive) | high | VO-focus each stepper and read it. Fix: add `.accessibilityValue(<the same text>)` |
| 3.3 | MapSettings.swift:478, 480, 504-514 | Disabled toggle / "Save to Sidecar" | The reason is `.help` (= hint). **A disabled control is skipped by FKA/VO focus order, so the hint on it is not reached** — the reason is effectively invisible | `help(_:)` | RISK | med | Disable the control, try to reach it. Fix: show the reason as a visible `InspectorNote` (small new text) or keep the control enabled and explain on press |
| 3.4 | MapSettings.swift:212, 243, 322, 333-339, 540-542 | Kernel source, kernel mode, Detector, Threshold, Split | Explanations in `.help` = hint; Threshold's range/direction rides on it | `accessibilityHint(_:)` brief phrase | RISK (length) | low | Listen; shorten where long |
| 3.5 | MapSettings.swift:421-431 | Validation issue labels (red octagon / orange triangle) | Severity is icon + colour; spoken text is the message only | HIG Color: do not rely solely on colour (reader, unchecked) | RISK | low | Prefix "Error:" / "Warning:" in the label |
| 3.6 | MapSettings.swift:248-263 | Ring-probe warning appearing dynamically | No announcement when it appears | HIG VoiceOver: "Inform VoiceOver when visible content … changes" | RISK | low | Post an `AccessibilityNotification` when `ringHint` becomes non-nil |
| 3.7 | MapSettings.swift:637-645 | "Minimum absolute intensity" unit "CC" | Spoken as letters; meaning only in the hint | — (not found) | RISK | low | Spell the unit out in the value |

## 4 · Crystal Maps

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 4.1 | PhaseMappingSettings.swift:592-601 | Zone-axis `TextField("u v w", …)` in `InspectorRow("Zone axis")` | **Checked in code.** The title string is the field's spoken name: VO says "u v w", never "Zone axis" | `TextField(_:text:)`: the title string becomes the label | GAP | high | VO-focus the field. Fix: `.accessibilityLabel("Zone axis")` |
| 4.2 | PhaseMappingSettings.swift:653-663 | "Parallel to matrix" `TextField("Any rotation", …)` | **Checked.** `.labelsHidden()`, title is the placeholder "Any rotation": VO names the field by its placeholder | same | GAP | med | `.accessibilityLabel("Parallel to matrix")` |
| 4.3 | PhaseMappingSettings.swift:624-637 | Excitation slab field (empty = global value) | The effective global value is a grey prompt only; VO hears an empty field; the label at :637 sits on a container | HIG VoiceOver: relationships that are visual only | GAP | med | Field `accessibilityValue` "0.300 Å⁻¹, global" when empty |
| 4.4 | PhaseMappingSettings.swift:538-550 | Malformed zone-axis / relationship caption | Error text appears with no announcement | HIG VoiceOver: inform when content changes | GAP | med | Announce, or put the error in the field's value |
| 4.5 | MapSettings.swift:1201-1229 | ACOM Center X / Y / Half-size steppers | **Checked.** `Stepper(value:in:) { Text("\(x)") }`, "Center X" is separate static text in `InspectorRow`: VO may say "123, adjustable" without a name | `Stepper` label = purpose | RISK | med | VO-focus each; fix: `.accessibilityLabel("Center X")` + value (same family as 3.2) |
| 4.6 | MapSettings.swift:1111-1120 | "Phase model" Menu labelled by the model name | VO hears a bare "Al" as the switcher | HIG VoiceOver | RISK | low | Label "Phase model", model name as value |
| 4.7 | PhaseMappingSettings.swift:441-444, 353-374, 639-722 | Al–Mg–Si preset, Matrix evidence, Evidence line, Min. intensity, Ignore peaks beyond | Multi-sentence `.help` = long hints | `accessibilityHint` brief phrase | RISK (length) | low | Listen; shorten hint, keep tooltip |
| 4.8 | MapSettings.swift:1066-1067 | Orientation-accuracy note | Date, scope and error cause only in `.help` (also a repo-honesty point: a number without its provenance) | HIG VoiceOver: concise description of what it conveys | RISK | med | Put "planted Al, 2026-09-15" in the visible note |
| 4.9 | PhaseMappingSettings.swift:513-515, 744-783; :117-131 | Phase colour swatch / `LegendSwatch` Canvas; "best" zone-axis row marked by bold only | Key is visual only; rank 0 unmarked | HIG VoiceOver: describe visual-only relationships | RISK | low | Name the colour or hide; add "best" to row 0's label |

## 5 · Reconstruction

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 5.1 | ReconstructionSettings.swift:579-588; InspectorRows.swift:166-179 | Stage headers; Complete / Current / Pending value on the outer VStack, header Button keeps "Expanded/Collapsed" | The stage state is on the container, the glyph is hidden: VO on the header may not say "Complete" | `accessibilityElement(children:)` / HIG VoiceOver | RISK | high | VO-focus each stage header. Fix: carry the stage status in the header Button's value |
| 5.2 | ReconstructionSettings.swift:579-587 | Stage completes after a run | No announcement; checkmark is visual | HIG VoiceOver: inform when content changes | RISK | med | Run Prepare Parallax Preview with VO on; fix: post an announcement |
| 5.3 | ReconstructionSettings.swift:179, 188, 366, 379, 391, 422, 483 via InspectorRows.swift:491-521 | "Use Parallax Fit" and sibling buttons: `.help(help ?? title)` | **Checked premise:** `.help` is the hint (`help(_:)`). The Use Parallax Fit hint is ~430 characters incl. the branch-sign warning, read after the label | `accessibilityHint`: brief phrase | RISK | med | Time it with VO. Fix: split tooltip from a brief hint; the sign warning moving to a visible note is new surface (owner) |
| 5.4 | ReconstructionSettings.swift:909-912 (Canvas :876-907) | Scientific-history plots: sample picked by `DragGesture` only | VO has increment/decrement (:918-929, good); **FKA without VO has nothing: not focusable, no arrow keys** | `onKeyPress`, `focusable` | GAP | med | Tab to the plot. Fix: `.focusable()` + ←/→ stepping the same selection |
| 5.5 | ReconstructionSettings.swift:175, 251, 259 | `.help` on an `InspectorRow` (Defocus, Limit transmission, Pure phase) | The hint lands on the row's HStack, not on the field/toggle that has focus | `help(_:)` configures the hint of the view it is attached to | RISK | low | Tab to Defocus with VO; move `.help` onto the control |

## 6 · Results

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 6.1 | ResultsSettings.swift:55-85 | Saved-product row; the product on show is marked by an eye icon + weight | VO hears name + size, not that it is the one displayed | `accessibilityValue(_:)`: state as a value | GAP | med | VO on the current row. Fix: `.accessibilityValue("Shown")` |
| 6.2 | ResultsSettings.swift:87-97 | A / B compare buttons | Label "Load X into comparison A" — good; which slot holds which product is not exposed | HIG VoiceOver | RISK | low | Add loaded-state to the label |
| 6.3 | ResultsWorkspace.swift:297-308 | Comparison panels: `MagnifyGesture` zoom only | No keyboard / VO zoom (distinct from 1st #13, which covered the image panes) | `accessibilityZoomAction(_:)` exists for exactly this | GAP | med | Try keyboard zoom in the comparison row. Fix: `.accessibilityZoomAction` (+ named reset) — no new surface |
| 6.4 | ResultsWorkspace.swift:309-325, 343-348 | Comparison hover readout (`onContinuousHover`) | The sample value exists only under the pointer; VO/FKA get the static caption only | `accessibilityValue(_:)`; HIG VoiceOver infographics | GAP | med | VO on a panel: no value. Fix: expose the current sample as the panel's value (a keyboard cursor needs the owner's picture) |
| 6.5 | ResultsWorkspace.swift:328-340, 351-352 | Colourbar range and zero mark | Visual-only in this file (`Colorbar.swift` not read) | HIG VoiceOver | RISK | med | VO over a panel: is the range spoken? Fix: low/high/units as the bar's value |
| 6.6 | ResultsWorkspace.swift:93-97, 116-119 | Export Data… / Save to Results disabled | Reason in `.help` on a **disabled** button — not reachable by focus (as 3.3); Save to Results has no reason at all | `help(_:)` | RISK | low | Reach the disabled button by FKA/VO; show the reason as text |

## 7 · Output and Lineage

| # | File:line (HEAD) | Control | Hears wrongly / cannot do | Apple says | Verdict | Sev | Drive check / fix |
|---|---|---|---|---|---|---|---|
| 7.1 | BottomWorkspace.swift:73; LineageGraphView.swift:66-70, 164, 248 | Output log, lineage detail, provenance and narrow-list `ScrollView`s | None is focusable; whether a plain ScrollView scrolls from the keyboard on macOS is **not settled by the docs** | Focus cookbook: focusable views with key handlers (reader) | RISK | high (pending drive) | Tab from Clear into the log, press Down / Page Down / Space. If nothing scrolls: `.focusable()` + `onKeyPress` |
| 7.2 | LineageGraphView.swift:116-120, 201-225 | Graph: ←/→/↑/↓ move `selectedID` | **Checked in code.** Selection changes; VO focus does not follow and nothing is announced | HIG VoiceOver: inform on change; `AccessibilityNotification` | RISK | med | VO on: Tab into the graph, press arrows, record what is spoken. Fix: announce the selected node or move VO focus |
| 7.3 | LineageGraphView.swift:117, 267, 145-152 | `.focusable()` + `.focusEffectDisabled()` on graph/list; nodes `.buttonStyle(.plain)` | The system ring is off; selection is an accent stroke. A non-selected focused node may show nothing | `focusEffectDisabled(_:)`: disables focus effects; HIG Focus: rely on system effects | RISK | med | Tab through nodes with FKA, look at every stop |
| 7.4 | LineageGraphView.swift:116, 132-136 | Graph container; edges drawn in a Canvas | Container unlabelled; topology visual-only except node by node via "Inputs" | HIG VoiceOver: concise description of an infographic | RISK | med | VO: what does the container announce. Fix: label "Run graph" + a summary value |
| 7.5 | BottomWorkspace.swift:37-54 | Pane titles "Output" / "Lineage" | No header trait, so the rotor cannot jump between panes | HIG VoiceOver: titles and headings | RISK | low | `.accessibilityAddTraits(.isHeader)` |
| 7.6 | BottomWorkspace.swift:168-170 | Provenance rows: display rounds to 5 significant figures, exact value in `.help` | VO speaks the hint after the label; the exact value is only a hint | `help(_:)` | RISK | low | Listen; fix: exact value as `accessibilityValue` |
| 7.7 | LineageGraphView.swift:372-376, 155-157, 521 | Rewind to Here (consequence visible, confirm dialog); node label "Step s5, Disk detection, stale", symbol hidden, selected trait | Good practice | HIG VoiceOver | OK | — | none |

## Ten drive checks, in order of value

1. **Imaging 2.1 / V31 (1st #19):** VO on the virtual-detector pane — does a `.ignore` + `accessibilityRepresentation` element keep its label/value and offer four adjustable sliders? Then FKA reaching them. One drive answers both rows.
2. **Zone-axis and relationship text fields (4.1, 4.2):** VO must say "Zone axis" / "Parallel to matrix", not the placeholder.
3. **Bragg-disk and ACOM steppers (3.2, 4.5):** VO on each — is the value and the name both spoken?
4. **Output log / lineage scroll (7.1):** keyboard scrolling without a pointer.
5. **Lineage arrows with VO on (7.2, 7.3):** is the new selection announced, is a focused node visible.
6. **Manual Q/R fields and ellipse fields (1.1, 1.2):** distinct names, units spoken.
7. **Label-centres (3.1):** try to place a centre with FKA/VO — expected to fail; settles whether it needs an owner decision.
8. **Reconstruction stage headers (5.1) and the Use Parallax Fit hint (5.3):** is "Complete" spoken; how long is the hint.
9. **Comparison panels (6.3, 6.4, 6.5):** keyboard zoom, a sample value, the colourbar range.
10. **Disabled controls with a `.help` reason (3.3, 6.6)** and the Results "Shown" state (6.1): can focus reach them, is the reason or state spoken.

## Fixes needing no new on-screen surface — one implementation lane

All are accessibility modifiers, labels, hints or key handling; none moves a scientific number (no Gate D). Each still needs the drive above, and the reader's "unverified" caveat holds.

- **Names:** `.accessibilityLabel("Zone axis")` / `("Parallel to matrix")` (4.1, 4.2); "Q pixel size" / "R pixel size" through `manualScale` (1.1); "Center X/Y", "Half-size" on the ACOM steppers and "Phase model" on the Menu (4.5, 4.6); "Run graph" on the lineage container (7.4); `.isHeader` on pane titles (7.5).
- **Values:** `.accessibilityValue` on the five Bragg steppers and the ACOM steppers (3.2, 4.5); units on the ellipse / annulus fields (1.2); "Shown" on the current product (6.1); stage status on the stage header Button (5.1); the global value on the empty slab field (4.3); exact value on provenance rows (7.6); per-shape aperture label/value and the centre-slider range (2.2, 2.3).
- **Hints:** split `.help` into tooltip + one-phrase `.accessibilityHint` in `InspectorAdaptiveButton` (5.3, 1.3) and on the long-help rows (3.4, 4.7); move row-level `.help` onto the control (5.5, 1.4); `.accessibilityHidden(true)` on the verdict symbol (1.5).
- **Key handling / zoom:** `.focusable()` + ←/→ on `ScientificHistoryPlot` (5.4); `.accessibilityZoomAction` on the comparison panels (6.3) and on the image panes as the documented twin of the named actions; `.focusable()` + `onKeyPress` on the Output / lineage ScrollViews **only if** drive 4 shows they do not scroll (7.1).
- **Announcements:** `AccessibilityNotification` for the ring-probe warning (3.6), stage completion (5.2), the malformed zone-axis caption (4.4) and the lineage selection (7.2).
- **Wording that changes visible text** (put to the owner, not the lane): ImagingSettings notes naming the slider route (2.4), the Orientation-accuracy provenance (4.8), the "click the scan preview" caption (1st #20).

Needs the owner: a keyboard/action route for Label centres (3.1), the region drag (2.4, 1st #18), the scan navigator (1st #18), pan alternatives (1st #17), a keyboard cursor on comparison panels (6.4), visible reasons for disabled controls (3.3, 6.6), and any focus-ring change in the lineage graph (7.3).
