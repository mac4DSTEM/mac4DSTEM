# Lane H2 report — app and safety (UI audit 2026-10-14)

(Written progressively; numbers are filled from dated logs named below.)

## The cancellation sibling (SpectroscopyRoomController `await task.value`): NOT REPRODUCED, no code change
- The site is `awaitNewestRefresh(from:)` (App/SpectroscopyRoomController.swift ~440). `await task.value` does not pass a cancel of the
  WAITER to the awaited Task; it must not: the awaited Task is the shared newest refresh that the Quantify verb also waits on, so
  one cancelled waiter must not cancel it.
- Who cancels what: `unbind()` and `open` cancel `autoIDOnOpen` AND `lastRefresh` explicitly (lines 164, 238-243); `refresh()` cancels the
  previous `lastRefresh` before it starts the next (750). A cancelled refresh polls `Task.isCancelled` between stages and lands nothing;
  the cancelled waiter then returns at its own `guard !Task.isCancelled` (line ~230) and runs nothing.
- Reproducing observation attempted: ten existing tests cancel `autoIDOnOpen` straight after `openSpectrumImage` (SpectroscopyRoomLiveTests:321,
  SpectroscopySpec2ETests:25, ...) and rely on Auto ID NOT running afterwards; they pass. The only residue is that a cancelled waiter lingers
  until the refresh it waits on ends (one stage, ms-s) — no work done, no stale write (the generation check drops late answers).
  No defect with a visible effect was found, so nothing was changed.

## B: sites routed through InspectorWarning (glyph tinted, sentence primary text)
Routed: LoadConfigurator (refusal), ReconstructionSettings (3 warnings; "Missing values are rejected…" is now an InspectorNote, as the audit said),
PreprocessSheet + WorkspaceSidebar (verdict / headline labels: glyph-only), MapSettings (validation issues with `tint: .red` for errors, strain
failure remedies, exploratory-scale caveat, stale-detection warning, the ACOM interpretation/result labels), PhaseMappingSettings (zone-axis
"undecided" paragraphs — were `.caption2`, now `.caption` —, the exploratory-Å⁻¹ caveat, two malformed-entry captions, the "at chance" words),
MaterialsProjectSettingsView + MaterialsProjectImportSheet (failure / mismatch / match labels, body size kept in the sheet), and the four
WorkspaceInspector sites (frozen, item G1). InspectorWarning gained `tint:` (red for failures) and `font:` (a requirement's title row).
SKIPPED, lane H1's files: ImagePanes.swift:117 (the orange "ROI sum" tag — a state badge, not a warning sentence; PrepareSettings:177 already
glyph-only). Lane FIG's: ResultsWorkspace.swift:381 (plain `Label`, no colour), UI/Spectroscopy/SpectrumStripView.swift:775 ("unvalidated" capsule badge).

## Drive plan (per item: what to open, click, see) — nothing here was driven
- A undo (Bragg Disks, Crystal Maps). (1) Bragg Disks, labels on: click a few centres, Export Labels…, click more, Import Labels… that file.
  Edit shows "Undo Import Labels"; choose it: the labels clicked since the export are back; Edit > Redo re-imports. A wrong file (another
  dataset): the orange line appears and Edit shows no new Undo. Open another dataset in the window, then Edit > Undo: nothing returns.
  (2) Crystal Maps: add Cu and Fe by Add Phase; Presets > Al–Mg–Si… pick a β″ CIF; list becomes Al + β″ ×2; Edit > Undo Al–Mg–Si Preset: Cu, Fe and the
  old classifier are back; Redo repeats. (3) Minus on the middle phase; Undo Remove Phase puts it back in place; remove the matrix (another becomes
  the matrix), Undo: the original is the only matrix. Check Cmd-Z with the focus in the inspector, and with a number field being edited
  (the field's own undo goes first, as on a Mac).
- B/C: Phase map with a ranking that is at chance, the exploratory-scale line, a malformed zone axis ("1 x"), Strain failure, Detect-All stale
  line: only the triangle/octagon is coloured, sentences are black/white; in Light and Dark and with a non-blue accent. System Settings >
  Accessibility > Display > Reduce Motion on: inspector sections open/close without the slide.
- E: object table (Precipitates > Object Table): numbers and their headers right-aligned; select rows, Cmd-C, paste into TextEdit/Numbers: header + tab
  separated rows, same digits as the CSV; no selection: Edit > Copy dimmed. Export CSV… proposes "<dataset>-precipitate-objects.csv"; save into
  a folder you cannot write: the alert "Could Not Export the Table" with the system's reason; cancel the panel: no alert. Filter/sort and
  selecting rows stay instant on a table of thousands of objects.
- G: toolbar: a gap between the text verb ("Run …") and the icon buttons (check at a narrow window that Save/Reveal still overflow in order);
  Tab (Full Keyboard Access) to the pane divider: focus ring, Left/Right move it, VoiceOver: "Resize the diffraction and real-space panes,
  Diffraction pane 50 percent", adjustable; Tab to the status strip: Up opens/grows the bottom pane, Down shrinks, closes at the snap
  height; VoiceOver actions "Make the bottom pane taller/shorter" while the strip's toggle buttons stay reachable. Welcome: the mark and the doors only.
  Requirement titles, "Halted", rotation refusal and replay refusal read as glyph + black text; the caption notes are legible (.secondary, caption).

## AppKit
None added. Undo is Foundation's `UndoManager` from SwiftUI's `@Environment(\.undoManager)`; Copy is `.copyable` (a context-menu Copy would have
needed NSPasteboard, so the object table offers Edit > Copy / Cmd-C only); drop-to-open is `dropDestination`; menus are `Commands`.
The existing `NSWorkspace.activateFileViewerSelecting` (DatasetLocationActions.reveal) is reused by File > Show in Finder.

## AppState
AppState.swift is untouched. D1: the cost was at the window's construction site, so a `LazyAppState` box (App/LazyAppState.swift) now decides
WHEN the state graph is made; nothing moved out of AppState because nothing in it was the problem. A: the minus button's list surgery moved out
of the view into `PhaseMappingProduct.removePhase/reinsert` (Session), undo registration lives in `Session/ReplaceUndo.swift`, the two AppState
extension methods that remain (`importDiskCentreLabels`, `applyAlMgSiPreset`, `removePhaseMappingSlot`) are thin and hold no new stored state.

## Commits (main, unpushed; each by explicit paths; hunk-split where two items shared a file)
033cb07f D tests (tier 3) · 50407ab6 B+C warnings, Reduce Motion (B tier 3, C tier 2) · 8a2c0478 A undo (tier 2) · 1fb18188 E+D object table (tier 2) ·
09326945 G frozen-shell fixes G1,3,4,5,6 (owner acceptance recorded as the brief words it, ADR 035/050) · 6ed00b05 F menus + G2 shortcut + D1 lazy AppState ·
8dca8387 H1's ZoomCommands() wired into `.commands` (done from the "one line" note in UI/ZoomCommands.swift's header; the coordinator's message with the line had not arrived — revert if it differs).

## Gate (dated runs; logs in lanes/H2/logs)
- One copy = HEAD b15a9d5d + every H2 file (d-unit.log, 2026-10-14 18:21): unit 2349 passed / 0 failed / 4 skipped = 2353 = `func test` count
  (2348 result lines + testWritingTheBundledWeightsBackChangesNoByte, read passed by name from an interleaved line); core exit 0 (d-core.log).
  The first copy (c-unit.log) found 3 reds, all fixed before the commits: two of my tests assumed an empty undo group reads canUndo == false (it reads true),
  and FinalPolishS2Tests' source check looked for `Label(headline` in WorkspaceSidebar.
- Inventory (repo, repo-inventory.log): exit 1 on one pre-existing line only, `DEAD PATH docs/archive/pane-keys-gate-d-2026-10-14/ cited by docs/open-items.md` (not this lane's).
- Mutations: 23, all red on the intended test (c-mut.log 15, d-mut.log 8): C1 reduce-motion, B1 whole-label orange, A1 no import undo, A2 reinsert appends, A3 no dataset guard,
  A4 no redo, A5 classifier not restored, A6 two matrices, A7 silent stale undo, A9/A10 preset/minus register nothing, E1 counted-only, E2 fixed CSV name, E4 silent save failure,
  G1 nudge sign, G2 unclamped pane, G3 no close at floor, D1 eager state, D2/D3 the two replaced sleeps' gates, F1-F3 Options/Recent/drop.
- Two probes outside the test host caught errors before the gate: the pixel test's orange columns are span-based (the Label is centred in its frame), and UndoManager semantics.
- Not run: no app launch, no drive. 

## Left / for the owner or coordinator
- Esc no longer cancels an analysis (Cmd-. does): overrule on sight. The toolbar button still says "Reveal in Finder" (frozen WorkspaceView), the menu says "Show in Finder".
- The status strip got VoiceOver actions + Up/Down on focus, not an adjustable value (it holds buttons); both dividers take focus by keyboard navigation only (.focusable(interactions: .activate))
  so a click cannot pull focus off the panes: check on the drive that arrow keys still step the scan after dragging the divider (the coordinator's pane-keys question).
- Skipped by rule: ImagePanes.swift:117 "ROI sum" tag (H1's file); Settings "remember the last pane" and the periodic-table items (not in the brief).
- Rows to add (I did not edit docs): status.md Last gates: the gate line above + "Unverified on screen: H2's drive plan (A undo, B/C warnings, E object table, G dividers/toolbar gap/Welcome, F menus/drop/Cmd-./Opt-Cmd-I)".
  open-items: the Esc change; the "Reveal"/"Show" naming; the cancellation sibling NOT REPRODUCED (above). CLAUDE.md/docs mention ⌃⌘I and ⌥⌘0 nowhere in prose (checked), only in the two code comments updated.
- Stray files: the `mac4DSTEMTests` folder in the suite directory held H1's ApertureEntryTests/ZoomAnchorTests, none of mine; every H2 write used absolute paths or the repo as cwd.
