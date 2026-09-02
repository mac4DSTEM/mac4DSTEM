# S22 — UX redesign (design phase, drafted 2026-09-01)

**This file is the single S22 thread.** Every S22 lead previously scattered
across `open-items.md`, `v2-triage-2026-09-01.md` and `v2-ship-plan.md` is
consolidated in §2; those docs now point here and must not grow new S22
material. Status lives in §6, nowhere else. (Owner, 2026-09-01: "we are
losing the thread, we need to do better and not clutter this repo.")

**Mandate (owner, 2026-09-01):** go as deep as needed, the workflow spine
included. Look at what py4DSTEM and abTEM do — there is a known pattern users
should find in this app — but don't copy: find our own flavor. Keep the
mission: a good user experience AND a good scientific backbone. S22 and the
UI pair are committed (`975de2e`; FFT + R23 in `21f3990`); one final owner
playthrough (F1.53) remains.

**Method:** design on paper first, owner approves before SwiftUI is rewritten.
Evidence gathered by low-tier subagents (v1 tag archaeology, v2 inventory,
py4DSTEM pipeline grammar, external pattern survey); synthesis and judgement
here. Implementation in bounded slices, each light Gate A + a Track B row,
assistant-driven screenshots after every slice.

---

## 1. What is broken, in the owner's words (2026-09-01 playthrough)

Seven findings, full detail in `open-items.md` §Owner playthrough — 2026-09-01
second sitting (kept there because they are *findings*; this doc owns what to
do about them):

| # | Finding | Root cause class |
|---|---|---|
| O1 | Colormap access "looks horrible" — redundant `DP colormap ▸` submenu | Menu idiom |
| O2 | iDPC task pane "just useless" — picker + refusal text, no action | Task-pane grammar |
| O3 | Sidebar text truncates; widening it clips content off the window edge | Control idiom + layout bugs |
| O4 | View-orientation flyout covers a quarter of the window | Menu idiom |
| O5 | Sampled preview tiny; right panel not resizable; histograms fixed | Right panel is not a real column |
| O6 | "The whole workflow through the app is fucked"; v1 felt better | Spine |
| O7 | Bullseye disc detection unacceptable | **Science — NOT S22**; own Gate D session |

## 2. The consolidated S22 backlog (was scattered; now only here)

From the 2026-08-31 review triage, Group E (`v2-triage-2026-09-01.md` — IDs
stay authoritative there, one-liners here):

- `ui-04` circular scan ROI drawn offset from its visible centre (med)
- `ui-06` comparison hover ignores inverse letterbox and zoom (med)
- `support-export-07` publication strain figure omits masked-pixel legend (med)
- `core-data-05` inspector uses retired 0.5% outlier threshold, not the shared 2% (med)
- `ui-08` aperture handle can round to an out-of-bounds point (low)
- `ui-09` filename scan-step parser matches `ss` inside ordinary words (low)
- `core-data-09` log diffraction turns nonfinite pixels into valid zeros (low)

From the 2026-08-31/09-01 Track B drives (`open-items.md` playthrough
sections):

- Empty result pane gives virtual-detector instructions under every pending
  result kind (`UI/StemImageView.swift` placeholder)
- Welcome screen entry points open below the fold; ⌘N is the only route back
  to *Open with Options…*
- Sidebar divider restores at a measured 144pt against a declared 250pt min
- Readiness rows truncate mid-sentence (also owner decision 1 / Group A —
  whichever session lands first closes it)
- `ui-07` "GPU budget" vs "GPU working-set limit" — one word

Plus the owner's seven findings above (O1–O6; O7 excluded as science).

## 3. Evidence (filled by the four scout reports)

### 3.1 What v1.0.0 actually was *(scout A, from the git tag)*

**The spine is unchanged since v1.0.0.** The tag already has the same
`WorkspaceArea` five (Prepare/Image/Map/Reconstruct/Results), the same
NavigationSplitView sidebar, the same HSplitView pane pair, the same optional
220–340pt inspector. v1 additionally had the scan X/Y sliders and the Display
disclosure (both since removed/replaced by the held UI pair).

What DID change is density: `DatasetInspector.swift` grew **179 → 543 lines
(+203%)** — the 16-section stack is v2 accretion; `ProductWorkspaceViews`
+19%; refusal texts, readiness rows and provenance surfaces landed throughout.
**So "v1 worked much better" is not evidence for restoring v1 — it is
evidence that v2 poured three times the content into surfaces sized for v1's
content, without giving it new homes.** The added content itself (calibration
honesty, refusal reasons, provenance) is mission — deliberate, and kept; its
*presentation* is what S22 rebuilds.
### 3.2 What v2 currently is *(scout B, 2026-09-01)*

Spine: `WorkspaceArea` (`ProductWorkflow.swift:6-51`) — Prepare (no tasks),
Image (virtual detector, DPC), Map (disks, strain, ACOM), Reconstruct
(ptychography), Results. **Held against §3.3's grammar, the matrix splits one
family and fuses another:** DPC and ptychography (same phase-contrast family,
same voltage-only prerequisite) live in different workspaces; disk detection
(a *prerequisite step*, not an analysis) is a peer "task" of strain and ACOM
inside Map.

Surfaces: **13 conditional sidebar `Section`s** in the 1858-line
`ContentView.swift`, each guarded by workspace×task×pane-focus conditions —
what the sidebar shows changes with three hidden variables. The inspector
(`DatasetInspector.swift`) stacks **16 sections** in one fixed 220–340pt
non-draggable frame. Center: `HSplitView` of the two linked panes (the one
system-resizable seam that works), log strip below. Only 4 menus exist; two
of them are the O1/O4 offenders. Custom-drawn where it must be
(MetalImageView, ApertureControl, HistogramView, scale bar, rotation plot) —
everything else is already system SwiftUI, so the redesign is re-arrangement,
not re-rendering.
### 3.3 The py4DSTEM pipeline grammar *(scout C, 2026-09-01)*

The pattern every py4DSTEM user has typed, in order:

- **Bragg path (crystalline):** load → mean/max DP → **vacuum probe → kernel →
  `find_Bragg_disks`** → origin/ellipse fit *measured from the disks* →
  Q pixel-size *from a known crystal* → rotation → **then** ACOM or Strain.
- **Phase-contrast path:** load → DPC / Parallax / Ptycho, each just
  `preprocess → reconstruct`, needing **only accelerating voltage** — no
  disks, no crystal, no Q calibration.
- **Virtual imaging:** needs nothing; first thing everyone does.

Gating truth users already know: virtual imaging is free; disks need a probe
kernel; calibration is measured *from* disks (except our app's independent
origin measurement, a recorded deviation that is operationally better);
ACOM/strain need disks + calibration + crystal; DPC/parallax/ptycho need only
voltage. **The two analysis families are genuinely separate paths**, and our
own pipelines doc already recorded the UX findings this predicts (§7.3–§7.5):
ACOM prerequisites not signposted, voltage buried in Reconstruct though three
analyses need it, and the two families interleaved across workspaces.
Calibration vocabulary users expect: origin (qx0,qy0), ellipse (a,b,θ),
Q px size (Å⁻¹/px), R px size, R↔Q rotation.
### 3.4 What users see elsewhere — py4D-browser, abTEM, GMS/Velox *(scout D)*

One pattern across all four tools: a **real-space view and a diffraction view,
live-linked**, with a movable virtual detector drawn on the diffraction
pattern and a position selector on the real-space image (py4D-browser, GMS's
single interactive display, Velox's live mask→image). Shared vocabulary
everywhere: BF / (HA)ADF / DF, DPC/iDPC, pixelated 4D-STEM, virtual detector,
orientation and strain mapping. py4D-browser keeps detector shape/response in
menus, shows the current detector configuration in a bottom bar, and drives
both selectors from the keyboard (WASD/IJKL). abTEM is notebook-only; its
taught order (structure → potential → probe → scan → detector → measurement)
reinforces the same object grammar. **mac4DSTEM's center — two linked panes
with on-image detector handles — already IS the known pattern.** The
familiarity gap is not the panes; it is the pipeline around them.

## 4. The design

### 4.0 Diagnosis, one paragraph

The center of the app is already the pattern every 4D-STEM user knows (§3.4)
and the skeleton is the same one that felt fine in v1 (§3.1). v2 broke in
three ways: it **tripled the content** without giving it new homes (16
inspector sections in a fixed 300pt box, 13 conditional sidebar sections in
one column); it **hid the pipeline grammar** users bring from py4DSTEM (disk
detection posing as a peer analysis, DPC and ptychography — one family —
split across workspaces, voltage buried in Reconstruct though three analyses
need it); and it shipped **idiom defects** (double-wrapped menu pickers,
truncating hand-rolled rows, a giant footer text inflating a menu, a
non-column "inspector"). The design fixes exactly those three, and nothing
else.

### 4.1 What deliberately stays

The two live-linked panes with on-image detector/position handles (the known
pattern — our identity); Metal rendering and every custom scientific control
(aperture handles, histogram drag, scale bar); the honesty surfaces —
refusals, readiness, provenance badges, "not a result" labels — restyled but
never removed; the log strip; the accessibility identifiers; all of `Core/`.
S22 re-arranges, it does not re-render (§3.2 confirms everything else is
system SwiftUI).

### 4.2 The spine — five steps, re-cut along the physics (our flavor)

Single-level pipeline rail, ordered the way the science flows, named in the
vocabulary users bring (§3.3, §3.4):

1. **Prepare** — dataset, ALL calibration **including accelerating voltage**
   (moves here from Reconstruct; fixes pipelines §7.4).
2. **Imaging** — virtual detectors (BF/ADF/custom). The zero-prerequisite
   step everyone does first; stays essentially as-is.
3. **Bragg** — probe kernel → disk detection → strain / ACOM as an ordered
   sub-flow. Disk detection stops posing as a peer analysis: it is the gate
   the others visibly wait on (fixes §7.3, O6's worst confusion).
4. **Phase** — DPC & iDPC, parallax, ptychography, together: the
   voltage-only family (fixes the §7.5 interleaving; gives iDPC a home in
   its family instead of an orphan tab under Imaging — half of O2).
5. **Results** — unchanged role.

Every step shows a **prerequisite chain** — small ✓/– chips naming what is
met and what is missing, each missing chip clickable, jumping to where it is
satisfied. This replaces the orange refusal paragraphs as the *primary*
surface (the full sentences remain one click away — honesty stays, walls go).
"Workspace"/"Task" terminology disappears; there are steps and, inside Bragg
and Phase, the analyses of that family.

### 4.3 Layout — three real columns

- **Sidebar (navigation + the current step's controls).** Content becomes a
  wrapping `Form`-idiom column: `LabeledContent` rows, every text
  `fixedSize`-wrapped, no truncation anywhere (O3). The declared 250pt
  minimum is enforced on restore (kills the 144pt bug).
- **Center** — unchanged pane pair + log strip.
- **Inspector becomes a real system `.inspector` column** with
  `inspectorColumnWidth(min: 260, ideal: 320, max: 560)` — draggable,
  collapsible, animating (O5). Its 16 stacked sections regroup into four:
  **Dataset** (file, dimensions, preview, loaded view), **Live** (scan
  position, aperture, both histograms), **Diagnostics** (rotation,
  performance, provenance/sidecar notices, promote run), **Products**. The
  sampled preview and the histograms size to the column width — dragging the
  inspector wider is how you get a bigger preview (the direct ask in O5).
  Replacing the hand-rolled HStack member also removes the layout regime that
  produced the left-edge clipping (O3's second half).

### 4.4 Control idioms (the small rules, applied everywhere)

- A picker inside a menu is always `.pickerStyle(.inline)` — no
  double-wrapped submenus (O1).
- Menus contain controls only; explanatory sentences live in `.help` or a
  footnote under the control, never as a menu item (O4's width culprit).
- Every task pane leads with its **primary action** and its prerequisite
  chain; parameters follow; diagnostics last (the other half of O2 — the
  DPC & iDPC pane gets a Run/Update action and its readiness up top, like
  every family member).
- Numbers and units render in `LabeledContent` monospaced-digit rows; long
  provenance strings wrap.

### 4.5 Costs and risks, stated

The spine re-cut (4.2) is the deep move: it touches `WorkspaceArea`, task
routing, persisted selection, `SidebarLayoutTests`, and Track B wording. Per
the hard rule it extracts one `AppState` seam first (navigation/selection
state is the natural candidate). Voltage's UI home moves; its storage and
every consumer in `Core/` are untouched — UI-only by construction, verified
by the scientific gate staying green. The inspector regroup (4.3) retires
S17's numeric sidebar quarantine wording again — the layout gate gets
re-pointed at the new structure, and per the standing rule the replaced tests
are broken first to prove they can fail.

## 5. Slice plan — each slice: light Gate A, a Track B row queued, and
headless verification only (owner directive 2026-09-01: no per-slice
screenshot driving — one consolidated assistant drive after S22e, before
anything reaches the owner)

| Slice | Scope | Closes |
|---|---|---|
| **S22a** | System inspector column, resizable; 16→4 regroup; preview/histograms scale | O5, `core-data-05` rides |
| **S22b** | Menu + task-pane idioms: inline pickers, content-sized menus, action-first panes (incl. DPC & iDPC pane) | O1, O2(UI), O4, `ui-07` rides |
| **S22c** | Spine re-cut: five steps, families, prerequisite chains, voltage to Prepare; AppState seam extracted first | O6, pipelines §7.3–§7.5 |
| **S22d** | Sidebar forms on the new spine: wrapping everywhere, 250pt restore enforced | O3, readiness-truncation (shared with Group A) |
| **S22e** | Backlog polish from §2: `ui-04`, `ui-06`, `ui-08`, `ui-09`, empty-pane instruction, welcome fold, `support-export-07`, `core-data-09` | rest of §2 |

Order rationale: a and b are spine-independent and land visible relief
early; c is the big move; d writes the final sidebar on the final spine so
nothing is styled twice; e sweeps. After S22e: the held UI pair is re-based,
committed with the slices, and the owner does the one final playthrough
(his decision 7). O7 (bullseye) runs as its own Gate D science session,
scheduled independently of S22.

## 5.5 Owner feedback, round 2 — 2026-09-01 late evening (the real playthrough)

The owner drove the S22 build on real data (welcome screen; `polyAu`
`circularProbe.h5`; `sim_Au_data_all_binned.h5` with its session sidecar) and
sent 16 screenshots. Verdict: "this is really not an ok state after a UI
workover … performance got much worse … unacceptable." **The assistant's
consolidated drive missed all of this because it used the demo dataset, on
the happy path, at default widths, with no session sidecar and no full
detection run — the exact green-but-broken pattern this repo documents.**
Every item below is mapped to its screenshot, classified, and dispositioned.

| # | Owner's words (screenshot) | Diagnosis | Class | Disposition |
|---|---|---|---|---|
| R1 | Sidebar drags "far too far to the right", pushes everything out (shot 3, ~750pt sidebar) | The S22d GeometryReader wrapped the List and **detached `.navigationSplitViewColumnWidth` from the column root** — min AND max stopped applying. (Max was ALREADY unenforced pre-S22: the owner's original screenshot 5 shows ~625pt.) | **S22 regression** (made a pre-existing hole worse) | **FIXED this sitting**: modifiers moved to the column root; `SplitViewWidthClamp` now also pins AppKit `NSSplitViewItem.minimum/maximumThickness` (250/340), which AppKit enforces live during drags |
| R2 | Welcome "Prepare/Analyze/Preserve … large empty boxes … three side by side at least" (shot 1) | `ViewThatFits` fell back to stacked full-width cards with a 112pt empty floor; pre-existing, made prominent by S22e's reorder | Pre-existing, S22-amplified | **FIXED this sitting**: always three across, content-sized |
| R3 | Narrow sidebar: "text doesn't wrap but is invisible behind dots" (shot 4, ~175pt) | Reachable only because R1 broke the 250pt floor; at ≥250 the wrap recipe holds | Same root as R1 | **FIXED with R1** (floor enforced; wrap width floor raised to 216) |
| R4 | Right panel: previews scale with width — "i like that" | — | S22a **confirmed good** | — |
| R5 | Log strip "text overlaps … looks like an amateur app"; wants static performance info at the bottom, "we can discuss" (shots 7–9, 14) | The transparent bottom status inset draws over the log's last line; long errors make both illegible | Pre-existing, exposed by error volume | **Overlap FIXED this sitting** (opaque `.bar` backing, 2-line cap). The **status/performance footer redesign is DECISION D2** below |
| R6 | "why does it randomly say 'show' again under pattern … people will get what current mean and max mean" (shot 12) | Sidebar Pattern section duplicated the pane header's Current/Mean/Max toggle | Pre-existing duplication (more visible after S22c widened the section's reach) | **FIXED this sitting**: the sidebar keeps only the Compute Mean/Max affordance before the statistics exist |
| R7 | "WTF is the dropdown menu for the coloring again?? this makes no sense" (shot 11) | The flat menu (S22b) is mechanically one-click now, but the owner rejects the control itself/its placement | Design | **DECISION D3**: where should colormap choice live (recommendation: on the pane's colorbar chip) |
| R8 | "why does it say bragg twice? why not strain&ACOM this is horrible" (shot 13) | Workspace "Bragg" + subtitle + family caption + task "Bragg disks" = the word four times in one column | S22c naming, rejected | **DECISION D1**: rename the workspace by its outcomes; de-duplicate captions |
| R9 | Disk-detection UI "feels slow": stale circles linger a blink after picking a new pattern (shot: circularProbe Bragg) | Overlay redraw lags the pattern swap; unmeasured | **Performance — Gate D owed** | Part of **P1** below; do NOT tune blind |
| R10 | "Detect All Disks" → beachball, progress stuck at 0% then jumps to done, **Cancel unclickable** — "to the user the app just froze" | Main thread starved during full-scan detection; progress/cancel never painted. v1 "worked much better" per owner | **Performance — Gate D owed, TOP priority.** May be S22-caused (must A/B) or pre-existing | **P1** below — measurable A/B exists: the owner's still-running 16:04 pre-S22 instance vs the new build, same dataset |
| R11 | Binned 2× Au cube: **BF preset lands in the lower-right corner** (where the unbinned centre would be); strain errors out; suspects the sidecar (shots 15–16) | Restored sidecar calibration was recorded on the UNBINNED frame; the preset applies its centre (~126) to a 62px detector and the ui-08 clamp parks it in the corner instead of refusing; strain's reference then fails. Frame re-referencing hole | **Science-adjacent defect — Gate D owed** | **P2** below. Note: refusal-honesty says a stale-frame centre should be REFUSED, not clamped |
| R12 | Error spam covers the UI; "can't even remove [the sidecar], just change it" (shots 14–16) | No detach/ignore affordance for a loaded session sidecar; repeated modal-ish errors flood the strip | Feature gap + error-UX defect | **DECISION D4** (sidecar detach semantics — Core-adjacent, needs care); error-flood dedup joins P1's session |
| R13 | Save to Session works; A/B compare "not completely clear but I guess fine" | Labeling/help gap | Minor | Ride-along later |
| R14 | *(assistant-observed in shot 2)* Virtual detector · Annulus badged **Categorical** | A restored product's trust badge is wrong — the `app-appstate-01` provenance-leak family, reproduced again | Known Group A defect | Already scheduled (provenance leak session) |
| R15 | "why don't the small circular indicators change color once bragg disc detection landed?" (20:25 screenshot: 83,929 peaks landed, circle still empty) | Backlog #33 deliberately made the glyph READINESS-only after users misread the green check as done — which created the inverse confusion: no completion feedback at all | Recorded design gap, now closed | **FIXED this sitting**: third state added — green check when the task's product exists this session (disks/strain/orientation), matching the inspector's "Computed this session" glyphs, so #33's ambiguity does not return |
| R16 | "i can also move the images out of view, makes no sense … it should be blocked" (20:31 screenshot: CBED and ACOM panes panned to slivers) | Pan offset was unclamped in `ZoomPanModifier` | Recorded gap, now closed | **FIXED this sitting**: pan clamps to the shader's own geometry — \|offset\| ≤ size·(1 − 1/zoom)/2, edge-to-edge but never out, zero at 1×, zooming out pulls a panned image back; rule unit-pinned (`ZoomPanClampTests`, observed red under a bound mutation) |
| R17 | Round 3 (21:30 screenshots): after Preview Orientation lands, the header button should advance to the full scan | Staged primary action, same idiom as parallax | Improvement, accepted | **FIXED this round**: ACOM's primary action advances to the full run once a preview result exists |
| R18 | The output log scrolls down BEHIND the permanent footer — "it should end above" | The footer was a floating `safeAreaInset`; the log strip extended under it | **D2 regression** | **FIXED this round**: the footer is a normal stacked element at the detail column's bottom — nothing can render behind it |
| R19 | In Results the footer blocks the page's own info and saving actions (Export/Save row) | Same mechanism as R18 | **D2 regression** | **FIXED with R18** (the footer now stacks below the Results content too) |
| R20 | Imaging: with Rectangle/Circle regions, scrubbing replaces the diffraction pattern even when Mean or Max is selected; Point correctly only affects Current | The ROI-summed pattern substitution ignored the display-mode selection | Pre-existing defect | **FIXED this round**: region sums substitute the displayed pattern only in Current mode, like Point |
| R21 | Parallax/ptycho "weird flapouts for the steps — they could just be buttons with indication … telling the user in which order" | The numbered stage DisclosureGroups | Design, accepted | **FIXED this round**: stages are flat rows — number, title, ✓/current state — and only the ACTIVE stage shows its controls, automatically; no user-managed disclosures |
| R22 | "can we do something about the speed? does metal help?" | Answered in the closing report: the 250-px fallback is the whole story; options are pad-to-256 on the existing Metal FFT path, or a supported-length vDSP plan — both `Core/` + parity-fixture work, queued as the gated FFT session | Science, queued | The gated `executeDFT`/Metal session |
| R23 | "where are the colormaps? did you now include them?" — the colorbar chips render as a bare number, no gradient (21:33 screenshots); owner later: "still not in place" | **D3 regression caught by the owner**: a SwiftUI `Canvas` inside a Menu's AppKit-hosted label does not render | **D3 regression** | Rebuilt as plain button + SwiftUI `.popover` (`UI/ColormapChipMenu.swift`), gated green — and **CONFIRMED STILL BROKEN ON SCREEN by the owner after a rebuild (22:20)**. Note the severity: with the sidebar Display row retired, a broken chip means **no working colormap control exists in the app right now**. **FIXED AND VERIFIED ON SCREEN 2026-09-02** (§6 entry): the popover was never the fault — `ScalarColorbarView` carried `.allowsHitTesting(false)`, and as the button's label it made the whole chip transparent to real clicks (AXPress opened the popover; a click inside the button's own frame did not). Modifier moved to the one plain use site; both chips now open on click and both colormaps change the pane |
| R24 | *(assistant-observed in shot 4)* "Requires a calibrated origin, R–Q rotatio…" truncates in the Phase sidebar | A pre-S22d orange caption without the wrap recipe | Missed site | **FIXED this round** (`sidebarWrapped()`) |
| R26 | "for the histograms make them not log per default … log counts on startup is unusual" | `HistogramView.useLog` defaulted true | Preference, accepted | **FIXED**: linear by default, log one toggle away |
| R27 | The Phase requires-line doesn't wrap (pre-rebuild build; R24 already fixes the wrap) and stays ORANGE "which is wrong as all are fulfilled" | The real story: "Core calibrated" is true while ptychography ADDITIONALLY needs the R scale and voltage — the generic orange sentence read as a false alarm and hid the actual gap | Wording/semantics, accepted | **FIXED**: the line is stateful and specific — orange "Still needed: R pixel scale · accelerating voltage…" when something is missing, quiet gray "All reconstruction requirements are met." when nothing is |
| — | **Harness note (2026-09-01 ~22:00):** the layout gate's 810.5pt bimodal failure tracked whether the OWNER'S live app was open — its width autosave re-restored the harness window past the one-time pin, and at the legitimate 250pt minimum Strain & ACOM genuinely needs ~25pt of scroll (recorded as a density observation, not gated). The gate now re-pins the width before every measurement | | | Green with the re-pin while the owner's app was open |
| — | **The completed run's numbers, for the P1 record:** "Detecting Bragg disks…" 20:04:47 → "Disks ✓ 83929 peaks" 20:18:56 — **14 m 09 s for 8,400 patterns (~101 ms per 250×250 pattern on the CPU-FFT path)**, with zero intermediate progress painted | | | Baseline for the post-fix re-drive |

**Priorities set by this feedback:**
- **P1 — Gate D: the frozen Detect All Disks** (R9/R10/R12-flood).
  **Pre-registration, written 2026-09-01 before the experiment** (prior
  knowledge consulted: the 2026-08-25 open freeze was a DIFFERENT mechanism —
  a 30 s unmounted-share bookmark resolve, fixed — but left the instruction
  "run `sample` while it hangs"; #37 recorded that detection cancellation
  granularity is fine and the read dominates; `TiledDiskDetection.detectAll`
  staging a fresh `MTLBuffer` per tile is a recorded open item; the compute
  entry `DiskDetection.detectAll` is `nonisolated` — off the main actor — and
  progress arrives as per-tick `@MainActor` tasks writing `progress` +
  `statusText`).
  **Candidates:** **D-A** — the main thread blocks INSIDE drawing, waiting on
  the GPU: the UI's Metal panes share the device/queue with detection's long
  command buffers, so the event loop stalls behind them (fits beachball,
  unpaintable progress, unclickable Cancel, and the everything-at-once finish).
  **D-B** — main-actor flooding: per-tick invalidations of the large view
  bodies swamp the run loop. **D-C** — system-wide memory/allocation stall
  (per-tile MTLBuffer staging on a 2 GB streamed cube). Plus the
  **S22-differential question**: same, better, or worse than the pre-S22
  build.
  **Refuting observations, per candidate:** D-A dies if the mid-hang `sample`
  shows the main thread NOT parked in Metal/CoreAnimation waits. D-B dies if
  main-thread samples are not dominated by SwiftUI/AttributeGraph work (or if
  callbacks are too few to flood). D-C dies if memory footprint stays modest
  and the rest of the system stays responsive. The S22-regression claim dies
  if the pre-S22 control freezes the same way for the same wall-clock.
  **Predicted outcome (before running):** D-A — the top main-thread stack
  shows `waitUntilCompleted`/`nextDrawable` under a Metal pane's draw, on
  BOTH builds, with S22 at most marginally worse; the freeze is pre-existing
  and v1 memory reflects smaller detectors.
  **Experiment E1:** S22 build, `References/training_dataset/
  calibrationData_circularProbe.h5`, Bragg → Generate Probe Kernel → Detect
  All Disks; two `sample <pid> 5` captures (early, mid), screenshots of the
  progress bar at fixed times, an osascript responsiveness ping, wall-clock
  to completion. **E2:** identical drive on a pre-S22 control built from
  `HEAD` (274d104) in a separate worktree. Verdict from the samples, not the
  feel.
  **E1 attempt 1 ABORTED (2026-09-01 ~20:00):** mid-drive, a screen capture
  showed the frontmost app was the owner's Claude session — the owner was
  actively using the machine, so synthetic clicks were landing blind (the
  frontmost assertion was skipped between steps, violating DRIVING.md's
  every-click rule; recorded here so the next agent doesn't repeat it). Both
  `sample` captures profiled the wrong operation and are DISCARDED. The
  experiment needs either an idle-machine window or, better, the owner
  reproducing the freeze themselves in both builds while the agent runs
  `sample` — zero synthetic input, and the owner's still-running 16:04
  pre-S22 instance is the ready-made E2 control.
  **E1 attempt 2 — VERDICT (2026-09-01 ~20:05, owner-driven, agent-sampled).**
  The owner clicked Detect All Disks on `circularProbe.h5` (their fresh Xcode
  build of the S22 tree, pid 28399); two 5 s `sample` captures during the
  freeze. **Main thread: 2518/2519 and ~2219/… samples INSIDE the detection
  compute itself** — `runPrimaryAction → runDiskDetection →
  DiskDetection.detectAll (TiledDiskDetection.swift:119 →
  DiskDetection.swift:856) → dispatch_apply(concurrentPerform) →
  DiskDetector.detectWithDiagnostics → FFT2D.transform`, dominated by
  `__sincosf_stret`. An AX responsiveness ping took **7 s**. **Diagnosis
  D-D (new, displacing all three pre-registered candidates):
  `concurrentPerform` is entered ON the main actor, so `dispatch_apply`
  conscripts the main thread as a worker for each tile's whole CPU-FFT
  workload — the runloop starves except between tiles, which is exactly
  "progress stuck at 0 % then jumps" and the unclickable Cancel.**
  Pre-registered candidates dispositioned: **D-A refuted** (zero
  Metal/CoreAnimation waits on main), **D-B refuted** (zero
  SwiftUI/AttributeGraph frames — the stacks are FFT compute), **D-C
  refuted** (pure CPU, no allocator/memory stalls). **The S22-regression
  claim is refuted too:** `git diff HEAD` shows `DiskDetection.swift`,
  `TiledDiskDetection.swift` and `FFT2D.swift` untouched by the entire
  then-uncommitted tree — the mechanism predates S22; a 250×250 detector just
  makes it ~4× heavier than the small cubes where it passed unnoticed.
  **Second finding, recorded for its own gated session:** the CPU-FFT hot
  path is dominated by per-element `sin`/`cos` — a large speedup is
  available, but it is `Core/` science code and takes the full gate. The
  threading fix (hop off the main actor before `detectAll`) is App-side.
  **Refuter verdict (independent subagent, 2026-09-01, from the primary
  samples — all four claims CONFIRMED, with corrections adopted):**
  (1) the main thread's s1 split is **~50 % conscripted FFT compute / ~44 %
  `__ulock_wait` inside `dispatch_apply` / ~6 % `newBufferWithBytes` tile
  staging** — not "~100 % FFT"; the runloop got exactly 1 of 2519 samples
  either way. s2 is 2219/2219 in compute, its thread identified by tid match
  (1403563 in both), not by a "Main Thread" label. (2) Zero Metal *waits*;
  the 153 staging samples are inflated by Metal validation + GPU capture
  (Debug run under Xcode). (3) **Strengthened: the identical un-detached
  call exists at HEAD and in v1.0.0** (v1 `AppState.swift:3436`), and both
  concurrency build settings (`SWIFT_APPROACHABLE_CONCURRENCY`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `project.pbxproj:455-456`)
  predate the v1 tag — the pre-registration's "nonisolated — off the main
  actor" model was WRONG (under these settings nonisolated async runs on the
  caller's executor), and **"v1 worked much better" cannot be a threading
  regression**. The sampled run was a Debug build with Metal validation —
  **no wall-clock comparison is valid until re-measured on Release**.
  (4) The implemented detach is sound off-main (progress `@Sendable`, token
  `@unchecked Sendable` NSLock-guarded, `FourDArray` an actor; the
  `TilePrefetcher` resumes move off main too). **The refuter also corrected
  the second finding's mechanism: `FFT2D.swift:425` `executeDFT` — the
  O(n²) per-element `sin`/`cos` FALLBACK, reached because 250 is not a
  supported `vDSP_DFT` length.** A 250×250 detector never touches the fast
  path — which is also the honest candidate for why smaller-detector
  datasets (v1 use) "felt much better". Owed next: Release-build A/B before
  any speed claim; a Track B row for Cancel-mid-run and continuously
  painting progress; the `executeDFT` speedup as its own gated `Core/`
  session.
- **P2 — Gate D: stale-frame calibration application** (R11).
  **Pre-registration (2026-09-01, before the experiment).** Source evidence:
  `applySessionCalibration` (`App/AppState.swift:2886-2949`) writes the
  sidecar's qSize, rotation, ellipse, probe radius, origin maps and aperture
  centre RAW into the live calibration — no `CalibrationReReference.apply`,
  no comparison of `snapshot.loadSpecification` (the session's frame) against
  `loadedView.specification` (the loaded frame) — while the FILE-calibration
  path (`:2540`) routes through the engine correctly. The owner's numbers
  fit exactly: centre 62.9 (the 125-frame value) on the 62px binned
  detector = the corner BF; a raw qSize is ×2 wrong under the 2× bin →
  strain's lattice fit fails. **Diagnosis P2-A: the session-restore path was
  never given the re-reference treatment.** Refuting observation: a
  headless open of a binned view over a full-extent-recorded sidecar
  yields a CORRECTLY halved centre / doubled qSize (then the leak is
  elsewhere, e.g. only the preset). Predicted outcome: raw values pass
  through. **Fix design (only if the repro confirms):** session spec ==
  loaded spec → identity (today's common case untouched); session spec ==
  fullExtent → route through `CalibrationReReference.apply` with the loaded
  spec (the owner's case); session on a DIFFERENT reduced view → REFUSE to
  adopt, with a named "Not carried into this view" reason — never guess a
  composite mapping. Independent refuter before landing, per decision 6
  (the owner's "keep going with the fixes" is read as covering the
  established spawn-refuter-and-land rhythm; flagged for objection).
- **D1–D4 — owner decisions**, listed with recommendations in the closing
  report of 2026-09-01.

## 6. Status

- 2026-09-01 — design phase opened; scouts dispatched; backlog consolidated.
- 2026-09-01 — all four scout reports in; §3 evidence, §4 design and §5 slice
  plan drafted the same evening.
- 2026-09-01 — **§4/§5 APPROVED by the owner** ("go as deep as needed"), with
  two amendments folded in: no per-slice screenshot driving (one consolidated
  drive after S22e), and subagents/low-tier models wherever safe.
- 2026-09-01 — **S22a DONE.** The inspector is a system `.inspector` column,
  260–560pt (`UI/ContentView.swift:977-979`); DatasetInspector regrouped
  16 sections → Dataset/Live/Diagnostics/Products with caps sub-labels;
  preview thumbnails fill the column width (fixed 120pt cap removed); rows
  wrap instead of truncating; `core-data-05` fixed —
  `CalibrationDetailsView.disclosesExcludedFraction` now uses the shared 2%
  floor, pinned by `CalibrationDisclosureTests` (observed RED against the
  retired 0.5%, then green). Gate: `run-tests.sh unit` exit 0, **402 passed /
  2 skipped / 0 failed** counted from the retained log (401 clean `Test case`
  lines plus one line garbled by parallel-output interleaving, log line 486,
  itself reading `passed`; the two skips are the standing unmounted-volume
  and S17-quarantine pair). The real-window layout harnesses
  (SidebarLayoutTests, SidebarDensityMeasurementTests) all passed against the
  new inspector path. No `Core/` or `AppState` change — scientific gate and
  seam not owed. **Not verified on screen:** drag-resizing, preview scaling
  and group readability are deferred to the consolidated post-S22e drive;
  Track B row **F1.52** queued. **Next: S22b (menu + task-pane idioms).**
- 2026-09-01 — **S22b DONE.** Colormap pickers and Q-units are inline in
  their menus (no `DP colormap ▸` double-wrap; `UI/ContentView.swift`
  `colormapMenu`); the orientation flyout lost its width-setting footer
  sentence, whose claim moved into the picker title + `.help`
  (`UI/StemImageView.swift`); the DPC & iDPC pane leads with its
  physical/qualitative status and an **Open Prepare to Calibrate** jump, with
  the requirements enumeration left to its single owner (the readiness panel);
  `ui-07` fixed ("GPU working-set limit", `UI/InspectorPanels.swift`).
  Gate: exit 0, **402 passed / 2 skipped / 0 failed** (one log line
  interleave-garbled; exit code authoritative).
- 2026-09-01 — **S22c DONE — the spine re-cut, in three gated stages.**
  (c1) The `WorkspaceNavigation` seam extracted per the hard rule — workspace,
  task and pane visibility off `AppState`, no forwarding stored properties,
  pinned by `NavigationSeamTests` (both tests observed red under planted
  mutations); gate **404 / 0 / 2, exit 0, no garbling**. (c2) The five steps
  are now **Prepare / Imaging / Bragg / Phase / Results** — case identities
  kept so recovery records survive; DPC joined Phase with ptychography (its
  voltage-only family), disk detection leads Bragg's ordered task list, the
  workspace-level ADV badge became a ptychography-task badge, and the
  parallax stage-gating no longer captures DPC's Run button. The gate caught
  the one test whose blocked/ready axis assumed ptychography was Phase's
  default — updated to select it explicitly. (c3) The **accelerating voltage
  moved to Prepare's Calibration section** (identifier unchanged); the
  ptychography voltage prerequisite resolves `.prepare` so the checklist
  navigates instead of describing a panel; the placement pinned from both
  sides by a rewritten `SidebarLayoutTests` test observed red pre-move.
  Final gate: **404 passed / 2 skipped / 0 failed, exit 0**.
- 2026-09-01 — **S22d DONE.** Readiness-row detail and ACOM quality detail
  wrap instead of truncating (`CalibrationReadinessView.swift`,
  `ACOMControlsView.swift`); the **144pt-restore clamp** landed
  (`UI/SplitViewWidthClamp.swift`, hooked in `ContentView.onAppear`) — the
  harness forced a real window's sidebar to 144pt and the clamp restored
  ≥250pt, observed red under a no-op mutation. Gate: **405 passed /
  2 skipped / 0 failed, exit 0**.
- 2026-09-01 — **S22e code DONE, six of eight.** `ui-06` (comparison hover
  now inverts letterbox+zoom via the pure `ComparisonHoverMapping`, quiet
  over letterbox), `ui-08` (aperture centre clamped after rounding, agreeing
  with the accessibility sliders), `ui-09` (`ss` token must not start
  mid-word — red observed on `thickness30nm` pre-fix), the per-task
  empty-pane instruction, welcome entry points above the fold, **Open with
  Options…** in the dataset menu (⌘N no longer the only route), and
  `support-export-07` (the burned figure carries a "no data" legend in the
  exact masked gray, pinned by a with/without byte comparison observed red
  under a no-op). **Deferred with reasons, NOT ridden:** `ui-04` — the
  drawn-ROI-vs-mask geometry feeds the strain reference, so it is a
  mask-convention decision needing a fixture and Gate B, not polish;
  `core-data-09` — lives under `Core/`, which takes the heavy gate by hard
  rule. Both stay in §2 as open.
- 2026-09-01 — **S22e gate: 409 passed / 2 skipped / 0 failed, exit 0**
  (counted from the retained log; one interleave-garbled line as in every
  parallel run, exit code authoritative).
- 2026-09-01 — **Consolidated assistant drive, on the demo dataset** (the
  owner's pre-S22 Xcode instance was left untouched; the drive ran its own
  build, targeted by pid). **Verified on screen:** welcome entry points above
  the fold; the new spine names and Bragg's produces/requires task grouping;
  voltage editing in Prepare; the flat one-click colormap menu; the DPC pane
  leading with "Physical iDPC ready — projected phase in rad" and **Run DPC**
  in the Phase header; ADV demoted to the ptychography task; the inspector as
  a real draggable column whose Real-space preview grew with a live
  edge-drag at correct aspect; the corrected demo status wording.
  **Found and fixed by the drive (each after a green gate):** the demo
  greeting still said "Prepare → Image → Map"; and **sidebar wrapping did not
  work at all** — neither `fixedSize` nor an explicit width frame wraps in
  the `.sidebar` List, because the list style inherits a one-line limit; the
  working recipe (`lineLimit(nil)` + width from a GeometryReader-published
  environment value) is now `sidebarWrapped()` in `UI/SidebarTextWidth.swift`
  and applied at the readiness detail, filename-conflict label, ACOM detail,
  next-step hint and DPC texts — verified wrapping on screen at the 250pt
  minimum. This also explains why every earlier fixedSize site "worked":
  none of those strings had been read at a width that forced the second line.
  **Not driven:** the orientation flyout's new size (structurally certain —
  the width-setting sentence is gone — but unobserved), the 144pt clamp
  (harness-pinned only), the aperture edge clamp, hover mapping (unit-pinned).
  **Track B: F1.53 queued as the owner's single final-playthrough row; F1.52
  scored PARTLY by the drive.**
- 2026-09-01 — **Final post-drive gate: 409 passed / 2 skipped / 0 failed,
  exit 0** (retained log; the standing two skips; one interleave-garbled
  passed line). The S22 tree is code-complete and green.
- 2026-09-01 late — **the owner's real playthrough (round 2) rejected the
  state**: see §5.5 for all 14 items, classified. Four fixed the same
  sitting (R1/R3 width bounds — an S22d regression plus a pre-existing hole,
  R2 welcome cards, R5 status-bar overprint, R6 duplicate Show row). The
  standing lesson, recorded: **the assistant's verification drive must use
  real data, drag every divider to both extremes, run a full compute, and
  include a session-sidecar dataset — the demo happy path verifies almost
  nothing the owner will hit.**
- 2026-09-01 late — **P1 CLOSED through the full Gate D discipline**: owner
  reproduced, agent sampled, diagnosis pre-registered, independent refuter
  confirmed all four claims with corrections (adopted above — including that
  the mechanism predates v1 and the 250-length `executeDFT` fallback is the
  real speed story). Fix landed: detection runs detached; progress and
  Cancel live on a free main thread. Same sitting: **D1 renamed the
  workspace to Strain & ACOM**, **R15** added the produced-state glyph,
  **R16** clamped panning (rule unit-pinned, red-observed). Final gate:
  **412 passed / 2 skipped / 0 failed, exit 0** (409 + the three clamp
  tests; counted from the retained log).
- 2026-09-01 ~20:45 — **P1 fix VERIFIED ON SCREEN BY THE OWNER**: progress
  painted continuously to 51 % and Cancel cancelled mid-run — both dead
  before the fix. Wall clock stays slow until the gated `executeDFT` session.
- 2026-09-01 late — **P2 CLOSED through the full Gate D discipline.**
  Diagnosis (raw session-frame adoption) CONFIRMED by the independent
  refuter from source + the owner's numbers, including the missing link
  (`applyDetectorPreset` sets only radii — the polluted aperture centre is
  the BF corner). The refuter **corrected the fix twice over my own
  review**: (1) it verified my double-application catch held (file-carried
  fields survive untouched); (2) it found a REAL regression — identity
  restores of scan-cropped sessions sized origin maps against the source
  extent while the writer records them in the live view's frame, silently
  downgrading fitted maps to the mean. That case was pinned RED-first in
  `SessionCalibrationTranslationTests`, then fixed (policy-dependent map
  extent). The wiring is now pure (`SessionCalibrationTranslation`) with
  the owner's exact numbers as a test (62.9 → 31.2, qSize ×2, probe ÷2);
  the un-run headless repro is recorded as superseded by code-level proof.
  Refuter's residuals, recorded: the engine's recordedOriginX/Y crop/bin
  mapping has no direct unit test (pre-existing, now load-bearing —
  follow-up); restored session PRODUCTS stay session-frame by declared
  scope and their use as inputs belongs to the scheduled provenance-leak
  session (the owner's strain failure on the binned cube is that session's
  reproduction). Gates: fresh-run preflight refused exit-69 at the ~6 GB
  disk floor (recorded remedy applied; scratch cleared), full suite via the
  warm MCP fallback: **418 passed / 0 failed / 2 skipped, SUCCEEDED** —
  412 + the six new P2 pins, the two standing skips.
- 2026-09-01 late — **D2, D3, D4 all LANDED, full suite green (417 / 0 / 2,
  warm run).** **D2**: `UI/StatusFooterView.swift` — permanent footer with
  the status line, a live progress bar + Cancel during any operation, and
  the standing facts (app memory · cube size · residency); the inspector's
  Performance block keeps the full detail. **D3**: colormap choice moved
  ONTO each pane's colorbar chip (`UI/ColormapChipMenu.swift`, real LUT
  swatches; the diffraction chip also carries Log display and Q-units); the
  sidebar Display row, `SidebarDisplaySection`, and its scoping test are
  RETIRED — the reachability invariant now holds structurally (the chip and
  the image are one surface). **D4**: "Reopen Without This Session" in the
  inspector's provenance block and "Ignore…" beside Change… — an
  identity-stamped one-shot skip through a clean reopen (the Change… shape;
  the sidecar file is untouched). Known limitation, stated in the help: a
  later save still targets the same sidecar file. **Harness finding:** S22d
  made sidebar height depend on the published wrap width, which settles
  asynchronously — the layout gate now waits for a stable height instead of
  a fixed pump (flaked at 810.5pt under full-suite load, passed in
  isolation; also: the voltage-placement probe now counts only EDITABLE
  fields, since AppKit renders menu-label text as non-editable
  NSTextFields).
- 2026-09-01 ~22:00 — **Round 3 landed, full suite green (417 / 0 / 2).**
  R17 (ACOM preview auto-advances to the full run), R18/R19 (footer is a
  stacked element — nothing renders behind it, log tail and Results actions
  included), R20 (region sums substitute the pattern only in Current mode,
  badge matched), R21 (parallax/ptycho stages are flat auto-advancing rows,
  disclosures gone), R23 (**colorbar chip rebuilt as button + SwiftUI
  popover** — the Menu-label build lost its Canvas gradient, the regression
  the owner caught), R24 (Phase requires-line wrapped), R25 (virtual/DPC
  task circles read the recipe record, which survives the shared result
  slot). F1.53 now carries checks 1–20.
- 2026-09-01 ~22:10 — **Round 4 landed, full suite green (417 / 0 / 2 with
  the owner's app OPEN — the re-pinned layout gate held).** R26 (histograms
  default to linear counts), R27 (the Phase requirements line names its
  actual gaps and goes gray when met). Rounds 1–4 total: **27 owner findings
  R1–R27, all dispositioned; 24 fixed and gated, 3 routed** (R7→D3 done,
  R22→the FFT session, R11→P2 done + the provenance-leak share).
- 2026-09-01 late — **FFT speedup session, IMPLEMENTED AND SELF-GATED** (Gate B
  and the suites landed the next sitting — see the 2026-09-02 entry below).
  Tree was still uncommitted at the time (owner decision). What landed, each with its evidence:
  - **`Core/Compute/FFT2D.swift`: the O(N²) scalar `executeDFT` fallback is
    GONE; an exact Bluestein (chirp-z) plan takes every axis length vDSP
    cannot serve** (no radix-2 setup, no radix-3/5 plan, no `vDSP_DFT`
    setup — 250 = 2·5³ is the case). Exact N-point DFT through radix-2 FFTs
    of M ≥ 2N−1; chirp built in Double from n² mod 2N; per-call scratch so
    one shared plan serves concurrent workers; NO data padding, so **no
    py4DSTEM DEVIATION** (numpy's pocketfft is exact too).
  - **Parity fixture: `tools/disk-correlation-parity` now runs a second
    fixed case, 250×250 / 32 patterns, pinned in `baseline-250.json`**
    (`--detector` flag added; `run.sh` runs both). Pinned FIRST on the
    scalar path, then compared: peak counts identical (288), positions
    within 3.9e-7, intensity/corr-max moved 7.3e-6 / 4.7e-6 — the OLD
    reference's Float-angle error (measured vs a Double direct DFT: scalar
    2.1e-5, Bluestein 8.5e-8, vDSP native 128² 4.6e-8). Re-pinned on
    Bluestein; the scalar checksums are recorded in the harness README.
    **Both baselines green, serial and `cpu-parallel`.**
    `tools/disk-detection-test` green.
  - **Release (`-O`) timing, correlation harness, 250×250: 255.8 → 3.2
    ms/pattern serial (80×); 0.68 ms/pattern parallel → 5.7 s projected for
    the 8,400-position scan** (was a 2,149 s projection; the owner saw
    14 min on Debug). **The on-cube app timing is NOT done** — see queue.
  - **`mac4DSTEMTests/FFT2DArbitraryLengthTests.swift` (7 tests)**: 250×250,
    250×128 mixed, small unsupported lengths incl. 65×129 (where a
    convolution length one short would alias), round-trip, unnormalized
    inverse, 8-thread shared-plan determinism, and the scalar-vs-Bluestein
    evidence test. **Broken by mutation:** flipped chirp sign → 4 tests red
    (errors 1e-2). Not sensitive to the sign flip by design: round-trip and
    concurrency tests.
  - **Ride-along 1 — per-pattern progress**: `DiskDetection.detectAll`
    counts patterns, not rows; callbacks rate-limited to one per 0.1 % of
    the tile, and `TiledDiskDetection` coalesces again on the GLOBAL
    permille (`ProgressCoalescer`) so a run makes ≤ ~1,000 main-actor hops
    however it is tiled. Pinned by
    `TiledDiskDetectionErrorTests.testProgressTicksPerPatternNotPerRow`
    (32-pattern scan: ≥ 32 distinct values, first tick 1/32). **Broken by
    mutation:** per-row ticks → red (8 distinct, first 0.125).
  - **Ride-along 2 — `CalibrationReReference` recordedOriginX/Y** (the P2
    refuter residual): 4 tests in `CalibrationReReferenceTests` — crop
    offset, crop-then-bin half-pixel (5.5 → 1.5, 6 → 1.25), outside-crop →
    nil + named reason (not clamped), full-extent identity. **Broken by
    mutation:** naive `x / bin` → red.
  - Targeted unit runs green (warm MCP `test_macos`): 44/44 across the four
    touched classes; **the FULL unit suite and `run-tests.sh scientific`
    have NOT been re-run on this tree.**
- 2026-09-02 ~01:00 — **FFT SESSION CLOSED: Gate B passed, both suites
  green, on-cube Release timing 14 m 09 s → under 15 s.**
  - **Gate B (independent refuter, 20 mutations actually applied and run,
    tree restored from `cp` copies and `cmp`-verified identical, no git
    restore commands).** The chirp-z math SURVIVED against numpy
    `fft.fft2` on identical bytes: 250×250 forward 2.6e-7, unnormalized
    inverse vs `N·ifft2` 2.7e-7, 65×129 / 250×1 / 1000×3 / 7×7 all ≤2.2e-7;
    the conjugate and inverse alternatives are O(1) off, so the sign match
    is not a symmetry accident. The re-pin of `baseline-250.json` is
    CONFIRMED: the refuter's own reconstruction of the retired scalar loop
    (from `git show HEAD:`) measured 2.15e-5 / 2.39e-5 / 2.27e-5 over three
    seeds vs Bluestein 7.3e-8 / 6.7e-8 / 7.2e-8, numpy agreeing to three
    digits. Thread safety SURVIVED (all-`let` plan, per-call scratch, one
    detector per worker anyway; 8-thread run bit-identical under
    `-sanitize=thread`). Coalescer SURVIVED (bucket decided under the lock;
    100 % always ticks; one pre-existing note: a 0.999 tick can be
    *delivered* after 1.0 because the callback fires outside the lock —
    harmless, completion tears the bar down). Mutation table: 16 of 20
    went red in both the unit tests and the parity harness (wrong-operand
    conj, either-direction filter sign, 1/N scale, unreduced Float chirp
    at 3.3e-6, wrap off-by-one, dropped chirp multiplies, re-only scale).
    **Three survived and none is wrong science:** M = 2N−2 (the only
    aliased filter offsets are ±(N−1), equal because the chirp is even —
    the test comment claiming 65/129 pins this was FALSE; the first wrong
    length is 2N−3); a Float chirp with the same mod-2N reduction (equal
    accuracy — the reduction, not the Double, is what matters); writing
    the never-read b[M−N] slot.
  - **The one finding that mattered: `relativeMaxError` scored an all-NaN
    transform as "error 0.0"** (Swift's `max(0.0, .nan)` is 0.0), so the
    no-zero-pad mutation passed four of seven tests. **Corrected**: the
    error function returns `.infinity` on any non-finite output and the two
    round-trip tests assert finiteness; re-broken by the same mutation →
    6 of 7 red (was 2). The 65/129 comment was corrected and **66×130
    added** — re-broken with `nextPow2(2N−4)` → 66×130 red at 6.9e-3 while
    65×129 stays green, exactly as the refuter predicted. Parity README
    gained a "what this baseline does and does not prove" paragraph: a
    per-axis re/im swap (a ky flip) leaves every parity checksum
    bit-identical because it commutes with `FFT⁻¹(P·conj(K))` — the
    baseline is a correlation regression pin, transform correctness rests
    on the unit tests. FFT2D's doc comment no longer credits the Double.
  - **Suites on the corrected tree:** unit (warm MCP `test_macos`) **429
    passed / 0 failed / 2 skipped**; `run-tests.sh scientific` **42
    started / 42 completed, zero FAIL and zero SKIP lines, exit 0**
    (log retained in the session scratchpad).
  - **On-cube Release timing, this agent driving per DRIVING.md** (owner
    idle ≥ 90 s at every click, frontmost asserted each time; the
    2026-09-01 blind-click mistake not repeated): Release build of this
    tree, `calibrationData_circularProbe.h5` (84×100 × 250×250, 2.1 GB,
    streaming), Generate Probe Kernel (r = 10.3 px) → Detect All Disks.
    Footer crops every ~1 s: **0 % at 0.4 s, 16 % at 2.7 s, 32 % at 4.8 s,
    49 % at 6.7 s, 62 % at 8.8 s, 84 % at 11.9 s, "Disks ✓ 83929 peaks" by
    15.0 s** — the SAME peak count as the owner's 14 m 09 s Debug run, so
    the science did not move. Progress painted continuously with Cancel
    visible; accessibility pings answered in 0.2–2.1 s during the run
    (7 s under the old freeze). **≈57× on the whole operation, and the
    remaining ~13 s is the 2 GB streamed read** (#37's prediction — the
    correlation itself projects to 5.7 s in the harness).
    *Build note:* a scratch `-configuration Release` build has the hardened
    runtime on with an ad-hoc signature, and dyld then refuses the ad-hoc
    `libhdf5.dylib` ("different Team IDs") — the app opens to a wall of
    error text. Timing was taken with `ENABLE_HARDENED_RUNTIME=NO` on the
    scratch build only; the shipped DMG signs both with the real identity
    (`tools/package-test` covers it). Not an app defect.
- **HANDOFF — the exact open queue, for the next agent:**
  (0) ~~FFT session Gate B~~ **DONE 2026-09-02** (entry above).
  (1) ~~The gated `executeDFT`/Metal FFT session~~ **DONE** — the answer
  was neither pad-to-256 nor a vDSP plan but an exact Bluestein transform,
  so no correlation input changed and no DEVIATION was needed.
  (2) ~~Release-build timing pass~~ **DONE** (above).
- 2026-09-02 ~01:30 — **R23 CLOSED: colormap chips fixed and verified on
  screen by this agent** (Gate A + live diagnosis, the §6.1 brief).
  Live first, on the same scratch Release build: both chips RENDER (gradient,
  min/max, units) — the owner's "bare number" was build 1, gone. A real
  CGEvent click inside the diffraction chip only focused the pane; an
  accessibility `AXPress` on the same `AXButton` (frame 711,746 146×51 pt —
  the click was inside it) opened the popover with the four swatches and the
  Log toggle. So the popover rebuild was right and the mechanism is
  hit-testing: `ScalarColorbarView.body` ends in `.allowsHitTesting(false)`
  (from the pre-D3 era, when it was decoration over a pane), and
  `ColormapChipMenu` uses that view as its `Button` label — a label that
  refuses hits leaves a plain-style button with no clickable area. **Fix:**
  the modifier moved off the colorbar view onto its one non-button use, the
  quality-field chip in `StemImageView`; `ColormapChipMenu.swift` unchanged.
  **Verified:** rebuilt, relaunched (sim_Au this time — the Recents order had
  shifted), real clicks open both popovers; Inferno recolored the diffraction
  pane and Gray the result pane, chips re-drawn with the new gradients; both
  reset to Viridis afterwards so the owner's defaults are untouched. The
  Q-units picker did not appear because that dataset has no mrad scale
  (`patternScaleMradAvailable` guard) — correct, not a gap. Unit suite on the
  fixed tree: 429 / 0 / 2. **F1.53 checks (3) and (15) are now driveable.**
  Two DRIVING.md lessons recorded: a synthetic click resets `HIDIdleTime`, so
  an idle guard placed after your own click trips on you; and Recents
  re-order on open, so a row index from a previous screenshot is stale.
  (3) **The scheduled provenance-leak session** (`app-appstate-01` +
  `support-export-01`) — restored session PRODUCTS still land raw
  (session-frame Bragg vectors feeding strain on a different view is its
  reproduction, from the owner's binned-cube drive; R14's wrong badge too).
  (4) **The bullseye disk-detection Gate D session** (O7, from round 1).
  (5) **The owner's F1.53 sweep** — now checks 1–22 — then the commit
  decision on the whole held tree. (6) Density observation, ungated:
  at the 250pt sidebar minimum, Strain & ACOM needs ~25pt of scroll.
  (7) ~~R23 colormap chips~~ **DONE 2026-09-02** — hit-testing, not the
  popover; verified on screen (entry above).
  Everything was uncommitted on the held UI-pair tree at the time, by owner decision.

