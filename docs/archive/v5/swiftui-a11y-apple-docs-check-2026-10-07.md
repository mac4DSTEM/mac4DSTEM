# SwiftUI keyboard / VoiceOver work vs Apple's documentation (2026-10-07)

Scope: commits `37252cdc..24163cc4`, read-only. Method: four Haiku readers each took one file group and looked every API up in
the Apple documentation MCP (`search_apple_docs`); the supervisor re-opened the doc pages behind the rows marked **checked**
and dropped what it could not confirm. The MCP serves SwiftUI/framework pages; the **HIG was not searched** by the supervisor,
so no row rests on HIG text except where marked "(reader, unchecked)" — except the *Focus and selection* page (`documentation/HIG/focus-and-selection.md`), which the supervisor opened for rows 6, 9 and 24. Nothing was built, run or driven: every verdict is a
reading, and every row is **unverified on screen** until a drive marks it. Doc paths are under
`https://developer.apple.com/documentation/swiftui/`.

## Doc facts the rows rest on (checked)

- `focusEffectDisabled(_:)` (macOS 14+): "controls whether this view can display focus effects, such as a default focus ring or hover effect"; an outer modifier overrides an inner one. No guidance beyond that — drawing a replacement ring is the app's job.
- `onKeyPress(characters:phases:action:)` (macOS 14+): fires while the view has focus; default phases `[.down, .repeat]`; `.handled` consumes, `.ignored` lets dispatch continue.
- `accessibilityRotor(_:entries:)`: the page's example puts the rotor on a `ScrollView` made a `.contain` element; the `entryID` overload "requires that the Rotor be attached to a `ScrollView`, or an Accessibility Element directly within a `ScrollView`". The namespace form (`AccessibilityRotorEntry(…, id:in:)`) was not shown to share or lift that requirement.
- `accessibilityRepresentation(representation:)`: "replaces default accessibility elements with different accessibility elements"; the representation view is hidden and non-interactive and is used only to generate elements. The page is silent on whether label/value set before it survive.
- `accessibilityHint(_:)`: "a brief phrase, like 'Purchases the item'" — what happens after performing the action.
- `AccessibilityChildBehavior`: `.ignore` hides children; `.contain` makes them children of the new element; `.combine` merges properties.

## Rows

V-rows are those of `swiftui-review-verification-2026-10-07.md`. Verdict: OK = used as documented; RISK = documented behaviour does not settle it, drive it; GAP = something Apple/HIG asks for that is missing.

| # | File:line (current) | API | What Apple says | Verdict | Drive check / fix | V-row |
|---|---|---|---|---|---|---|
| 1 | PeriodicTableView.swift:114-121 | `accessibilityRotor("Mapped")` on a `.contain` VStack, entries by namespace id | Rotor docs expect a `ScrollView` (or an element directly in one). The table is inside the inspector's ScrollView but not directly under it (`SpectroscopyInspectorHost` → `SpectroscopyInspectorSections`) — **checked** | RISK | VO-Cmd-U rotor list must show "Mapped"; choosing an entry must move VO focus to that cell and scroll it into view. | V20 (rotor was "not tried") |
| 2 | PeriodicTableView.swift:107-110, 118-119 | Rotor entries for quantified lanthanides/actinides when the fold is closed | Docs silent on entries without a rendered target (reader) | RISK | Quantify a lanthanide with the fold closed, pick it in the rotor: no dead end, no jump to a wrong cell. Fix if it fails: open the fold, or filter entries to rendered cells. | V20 |
| 3 | PeriodicTableView.swift:171-176 | `accessibilityLabel(sym)` + `accessibilityValue(state)` + `accessibilityActions { ForEach … Button }` | Label = the thing, value = its state when it differs; no role word in the label (button trait carries it) (reader) | OK | Drive-1 AX already saw "Fe", off → mapped, actions Off / Fit only / Quantify. | V20 PASS (AX) |
| 4 | PeriodicTableView.swift:128-142 | Plain-style `Button` per cell, kept enabled for unavailable cells | Not covered by a fetched page | RISK | VO on H/He/Li/Be: it is announced as a pressable button that does nothing — check the value says it is unavailable. Full Keyboard Access: Tab count across 90+ cells is accepted in the code comment; confirm Tab still leaves the table (Tab out of the grid in a sane number of presses). | V20 (FKA "not tried") |
| 5 | PeriodicTableView.swift:82, 94 | `accessibilityReduceMotion` gating the fold animation | "UI should avoid large animations" (reader, page `environmentvalues/accessibilityreducemotion`) | OK | Reduce Motion on: fold toggles instantly. | V20 (not tried) |
| 6 | MapsGridView.swift:215-223 | `focusable()` + `focused()` + `focusEffectDisabled()` + custom inset stroke | Disabling the system effect is allowed; the replacement indicator is the app's duty — **checked** | OK | Stroke only while focused, also in a window opened with `open` (drive 1 saw none there, unexplained — re-test, it is the open item here). | V21 |
| 7 | MapsGridView.swift:215-220 | label "ColorMix", value region caption, conditional "Clear region" action | Value only when it differs from the label (reader) | OK | VO reads the tile once (header "ColorMix" at :292 is a separate text — check no double read). | V21 PASS |
| 8 | MapsGridView.swift:234-244 | `onKeyPress` delete / forward-delete / "\u{8}" / "\u{7F}" and Escape | Handler runs only with focus; `.ignored` passes the key on — **checked** | OK | Backspace cleared the region in drive 1; also try ⌦ (forward delete) and Escape with no draft (must pass through). | V21 |
| 9 | SpectrumStripView.swift:585-598 | `.focusable()` `.focusEffectDisabled()` `.focused()` then `onKeyPress` ×6 (←/→ with `[.down,.repeat]`, `+=`, `-`, Home, Esc) | `onKeyPress` default phases are `[.down,.repeat]`; handled/ignored as above — **checked** | OK | Drive 1 passed ←, −, =. Not tried: ⌘+/⌘− must stay untouched (the `characters:` match must not eat ⌘-modified presses); hold ← for key repeat; a modifier+arrow. | V22 (⌘± "not tried") |
| 10 | SpectrumStripView.swift:170-183 | `accessibilityElement()` + stable label, changing value, six `accessibilityAction(named:)` | Named actions are exposed to assistive tech and invoked on the element (reader, page `view/accessibilityaction-named`) | OK | Drive 1: six actions listed, value moved with Zoom/Pan. | V22 PASS |
| 11 | SpectrumStripView.swift:85-92 (header divider) | `focusable` + ↑/↓ `onKeyPress` + `accessibilityAdjustableAction` | Adjustable action is the documented route to increment/decrement (reader) | OK | Not part of the 21 commits' V list: with VO, Adjust (VO-Up/Down) resizes maps/spectrum; ↑/↓ with focus does the same. | — |
| 12 | SpectrumStripView.swift:105-106 | Pin chip: label "Unpin Pin 1", hint "1 024 pixels" | Hint = what happens after the action, a brief phrase — **checked**. "1 024 pixels" describes the pin, not the outcome | RISK (wording) | The hint is a pixel count, not what the click does; "Removes the pin" fits the doc. Listen to it. | V23 PASS |
| 24 | SpectrumStripView.swift:173-174, 585-586; MapsGridView.swift:226-231 | Custom focus stroke replacing the system ring | HIG *Focus and selection*: "Rely on system-provided focus effects … Consider creating custom focus effects only if it's absolutely necessary" — **checked**. The same page says that with full keyboard access on macOS you "only need to support focus for content elements … not for controls like buttons, sliders, and toggles" | RISK (deliberate deviation) | The owner chose the stroke (the system ring is invisible on these custom canvases); state it as a deviation, and in a drive compare with the system ring once (`focusEffectDisabled(false)`) only if the stroke looks wrong. Also: the strip takes focus on click/drag, so the stroke shows after pointer use (`focusable(interactions:)` could restrict it, unchecked). | V21, V22 |
| 25 | SpectrumStripView.swift:592-599 | `+`/`=`/`-` via `onKeyPress(characters:)` | Handler excludes only ⌘ (`press.modifiers.contains(.command)`) — **checked in code**; ⌃ and ⌥ combinations still zoom | RISK | With the strip focused, ⌃+ / ⌥+ / ⌥- should not zoom (⌥-drag is the range gesture). | V22 |
| 26 | SpectrumStripView.swift:153, 270-286 | Right-click candidate-lines menu and ⌥-drag range readout behind a one-element Canvas | Canvas offers no per-element accessibility (reader, page `canvas`); HIG VoiceOver: make interactions available to VoiceOver (reader, unchecked) | GAP | VO Actions on the plot lists no "candidates" entry: a keyboard/VO user cannot add an element from the spectrum (the table does it). Record the gap or add an action. | V24 |
| 27 | SpectrumStripView.swift:177-183 | Value changes on keyboard pan/zoom, no accessibility notification | HIG VoiceOver: report visible changes (reader, unchecked) | RISK | VO on, press ←/+: is the new span spoken? If silent, post an announcement; if VO re-reads on its own, nothing to do. | V22 |
| 28 | SpectrumStripView.swift:154-161 | Key list only in `.help` | — | RISK (discoverability) | A keyboard-only user cannot find the keys; consider an accessibility hint phrased as outcome ("Arrow keys pan; plus and minus zoom"). | V22 |
| 13 | ZoomPan.swift:154-162 | `accessibilityAction(named:)` Zoom in / out / Reset zoom on the pane container | API use correct (reader) | OK | Drive 1: both panes list the three actions, 2× steps. | V13 PASS |
| 14 | ImagePanes.swift:403-407, 992-1003 | Actions attached to a `.contain` container | Docs do not say which element hosts actions under `.contain` (reader) | RISK | Drive 1 saw the three actions on both panes — confirm they are on the element VO lands on, and that overlay children (fit markers, scan marker) are not separate stops that bury them. | V13 |
| 15 | ImagePanes.swift:406 | Hint "Pinch to zoom, drag to pan, or double click to reset. The Zoom in, Zoom out and Reset zoom actions do the same." | Hint should be a brief phrase — **checked**. Two sentences; names gestures VO users do not perform; "do the same" is loose (actions step 2×) | RISK (wording) | Listen to it; shorten if unwieldy. | V13 |
| 16 | ZoomPan.swift:130-141 | Reset animation skipped when Reduce Motion is on | Page above — OK | OK | Reduce Motion on, double-click reset: instant; off: animated. | V13 (Reduce Motion "not tried") |
| 17 | ZoomPan.swift (drag pan) | No named pan action | HIG Accessibility/Gestures "offer alternatives to gestures" (reader, unchecked) | GAP | Zoom in with the VO action, then try to reach an off-centre region without a pointer: nothing does it. Strip already has Pan left/right; panes do not. | V13 |
| 18 | ImagePanes.swift:466-475 | Scan navigator: `DragGesture`, `.ignore` element, hint "Click or drag…" | Same HIG point (reader, unchecked) | GAP | VO cannot move the scan position from the navigator inset (the main pane has Move-scan actions at :1231-1256). | V11 |
| 19 | ReductionSections.swift:428-441 | `.accessibilityElement(.ignore)` + label + value, then `.accessibilityRepresentation { VStack { Stepper ×2 } }` | Representation "replaces" the element's accessibility elements; page does not say whether label/value set before it survive — **checked** | RISK | Highest-value check of the file: VO on "Scan · real space" must read title + caption, then offer Scan X / Scan Y as adjustable. If the title/caption vanish, move label+value onto the representation's VStack. Also check `configurator.scanCrop` still resolves for XCUITest (identifier applied after the modifier, :286). | V31 (NOT RUN) |
| 20 | ReductionSections.swift:170-176 | Value text ends "— click the scan preview to change" | VO users cannot click; the string is also the visible caption | RISK (wording) | Listen; name the steppers in the spoken value if it misleads. | V31 |
| 21 | ReductionSections.swift:59 | On-screen subtitle "Drag to crop · click to pick a pattern" hidden by `.ignore` | — | GAP (known) | Crop has no keyboard / VO route; the commit says so. Report it, do not claim it. | V31 |
| 22 | InspectorRows.swift:397-404 | `.combine` + label + `accessibilityValue` + named "Reset to default" on a Slider | `.combine` merges properties but "not all traits are merged"; page does not say the adjustable trait survives — **checked** (reader quote of `accessibilitychildbehavior/combine`) | RISK | Drive 1 passed: actions Increment, Decrement, Reset to default; increment 1 → 1.28. Re-confirm VO-Up/Down also adjusts (not only the Actions menu); try a slider with no default: no "Reset to default". | V32 PASS |
| 23 | InspectorRows.swift ~412 | Double-click reset has only a tooltip | — | RISK (minor) | The VO action covers it; nothing to do unless the hint is wanted. | V32 |

## Review finding → V-row

The verification list carries 32 rows for the 21 commits; this check touches V11, V13, V20–V23, V31, V32 (the keyboard / VoiceOver rows).

| Review finding (commit) | V-row |
|---|---|
| Periodic table keyboard/VO (d0b0d614) | V19 (look), V20 (behaviour) |
| ColorMix focus + region value (90575f90) | V21 |
| Spectrum strip keyboard, actions, focus ring (484def28) | V22; pin chip V23; right-click candidates V24 |
| Scan-preview pattern pick by VO/keyboard (f7dc436f) | V31 |
| Inspector slider Reset action (fc480f93) | V32 |
| Image-pane zoom actions (1434275c) | V13 |
| Metal view / pane redraw cost (b7876e20, 3d05ee29, ad0dbd5c, 23367162, 1516a089) | V1–V12 |
| Window-close / async entry points (a1ffd2b4, c59ef506, 2205c804) | V14–V18 |
| Spectroscopy recompute/observation (997138ce, ae0736b2, d0afcaa5, ef368fdc) | V25–V28 |
| Activity-log keys, ring-hint task (599f58d8, ff79d4fd) | V29, V30 |
| Eager Metal pipelines (37252cdc) | V6 |

No V-row exists for rows 11, 17, 18 (header divider, pane pan alternative, scan navigator) — add them if the owner wants them tracked.

## Drive checks, in order of value

1. **V31 first** (row 19): VO on the configurator's "Scan · real space" — does the representation keep the title and caption? Do the two steppers move the picked pattern?
2. **Rotor "Mapped"** (rows 1–2): VO rotor lists it; entries land on cells; lanthanide with the fold closed.
3. **VO-Up/Down on a slider** (row 22) and on the header divider (row 11), not only the Actions menu.
4. **Full Keyboard Access** (rows 4, 9, 6, 25: ⌃+/⌥+ must not zoom): Tab through the table and out of it; ←/→/+/−/Home/Esc on the spectrum; ⌘+/⌘− still zoom the window content; Backspace and ⌦ on ColorMix.
5. **Reduce Motion** on: table fold, image reset (rows 5, 16).
6. **Spectrum VO gaps** (rows 26-27): is the new span spoken after a key step; is there any VO route to the candidates menu.
7. **Focus stroke in an `open`-launched instance** (row 6): drive 1 saw it only on a directly launched build.
8. **Listen to the hints** (rows 12, 15, 20) and decide on wording; wording changes to row 20 alter visible text.
9. VO on an unavailable cell (row 4); VO zoomed-in pane — can an off-centre region be reached (row 17); navigator by VO (row 18).
