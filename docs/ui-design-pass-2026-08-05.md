# UI design pass — #16, #21, #4, #17 (2026-08-05)

Design document for the four coupled items in `docs/ui-workflow-backlog.md`
§"Design-pass items". **Nothing here is implemented.** It exists to be chosen
from. Written after a measurement pass against the real app, not from reading
the code alone — the numbers below are all measured, and two of the four items
changed shape because of them.

---

## 0. How this was measured, and what was blocked

**UI automation is blocked.** `osascript` reports *"osascript is not allowed
assistive access"* and `screencapture` reports *"could not create image from
display"*, so neither Accessibility nor Screen Recording is granted to an
agent-run shell. That blocks the XCUITest harness (the same blocker recorded in
`docs/ui-implementation-prompts.md`) **and** blocks screenshots and synthetic
mouse/trackpad events.

**What was used instead.** `mac4DSTEMTests` is a *hosted* test target
(`TEST_HOST` = the app), so a test runs in-process with the real app and can
build a real `NSWindow` around the real `ContentView` and read the AppKit view
tree directly. `mac4DSTEMTests/SidebarLayoutProbe.swift` (temporary — see §5)
does exactly that: real window, real `AppState`, real demo dataset, and it
reports window/scroll/pane geometry after each transition. That is stronger
evidence than a screenshot for a layout bug, because it is numeric.

The probe is faithful to the real app: at rest it reproduces the correct
titlebar accommodation (`contentInsets.top = 52.0` = titlebar height) on every
screen.

What it **cannot** do is generate real trackpad/scroll-wheel input. That is the
one gap, and it is where #16's remaining unknown sits.

---

## 1. #16 — reproduced as a mechanism, not yet as a trigger

### 1.1 The symptom is a sidebar scroll-offset bug, and this is exact

Healthy sidebar, every workspace:

```
contentInsets(t=52.0)  docTopInWindow=871.0  visibleOriginY=-52.0
```

The window content is 923pt tall; `contentLayoutRect` is 871pt (titlebar = 52).
`docTopInWindow=871` means the List's first row starts exactly at the bottom of
the titlebar. `visibleOriginY=-52` is the clip origin at "true top" given a
52pt top inset.

The broken state, captured:

```
contentInsets(t=52.0)  docTopInWindow=923.0  visibleOriginY=0.0
```

`docTopInWindow=923` is the top of the **window**, not the top of the content
area. The first sidebar rows are drawn across the titlebar and the traffic
lights. That is precisely the 2026-08-05 screenshot.

So #16's layout half is **not** a SwiftUI diffing or z-ordering mystery. It is
one number: the sidebar `NSScrollView`'s clip origin sitting at `0` instead of
`-52` — scrolled up past its own top by exactly the titlebar height.

### 1.2 This also explains the "controls unresponsive" half — same bug

When the clip origin is 0, the top 52pt of sidebar rows render *underneath the
titlebar/toolbar*, which is above the content view in the hit-test chain. Those
rows therefore **swallow clicks**. "Buttons are sometimes blocked/inert" and
"layout drawn over the window chrome" are not two symptoms of a vague
stale-state problem. They are **one bug with two faces**, and that resolves the
question #16 asks ("*why* did the app accumulate this kind of state bug at
all") — it didn't accumulate several; there is one.

It also explains "navigating away and back usually restores them": any action
that returns the sidebar clip origin to −52 makes the buried rows clickable
again.

### 1.3 Hypotheses tested and REFUTED — do not re-try these

Each was driven against the real view tree and the inset stayed correct at 52 /
origin −52 throughout:

| Hypothesis | Result |
|---|---|
| Workspace switch while the sidebar is legitimately scrolled (offset clamp when the document shrinks) | **Refuted.** AppKit re-clamps to the inset-aware floor (−52) every time. Tested Prepare→Results→Reconstruct→Map→Prepare, scrolled 200pt down. |
| Toolbar item-count change (Results drops 2 `ToolbarItem`s, regains them on return) | Refuted |
| Animated `showToolsPane` round trip (`withAnimation`, the `columnVisibility` binding round-trip) | Refuted |
| Log-pane and inspector-pane toggles | Refuted |
| Window resize (1470×923 → 1180×700) | Refuted |
| Key-window resign/restore | Refuted |
| Rapid non-linear navigation with no settle between steps | Refuted |

The clamp hypothesis was the most promising one on paper — every workspace has
a different sidebar document height (1088 / 1043.5 / 993 / 929 / 871), so a
shrink happens on *every* workspace switch — and it is cleanly dead.

### 1.4 What remains, and one property that matters

The offset can only be moved by a real scroll event, and the strongest
surviving candidate is **elastic overscroll at the top of the sidebar settling
at 0 instead of −52** (or a scroll-wheel/momentum event landing during a List
rebuild). Both need real input events, which is exactly what is unavailable
here — and it fits "intermittent", and fits that it shows up after a lot of
poking around rather than on a scripted path.

One measured property is worth carrying into the fix: **once the origin is 0 it
is sticky.** From a legitimate offset a workspace switch resets to −52; from
offset 0 it does not — the system treats 0 as "already at the top" and never
corrects it. So the bug is easy to enter and, by navigation alone, not reliably
left.

### 1.5 Why the sidebar gets scrolled at all — the link to #21

The sidebar document does not fit its column at any size measured:

| State | Sidebar document | Column available | Overflow |
|---|---|---|---|
| Prepare @1470×923 | 1088 | 871 | **+217** |
| Map · strain @1470×923 | 1043.5 | 871 | +172 |
| Reconstruct @1470×923 | 993 | 871 | +122 |
| Reconstruct @1180×700 | 909 | 648 | **+261 (40%)** |

The user *must* scroll the sidebar, constantly, on every screen. Scrolling is
the only thing that can move the offset into the bad state. **#16's entry
condition is created by #21's overcrowding.** Fix the crowding and the bug
loses its way in.

### 1.6 Proposed fix — two layers

1. **Defensive (one line, independent of the trigger):**
   `.scrollBounceBehavior(.basedOnSize)` on the sidebar `List`. Sanctioned
   SwiftUI API; disables elastic overscroll when content fits. If the entry is
   rubber-banding, this closes it.
2. **Structural:** shrink the sidebar below the column height (§2), so the
   sidebar usually has nothing to scroll at all — which is what makes layer 1
   actually engage.

**Confirmation still needs a human** (§6). I am not claiming the trigger is
found; I am claiming the mechanism is pinned, seven candidates are dead, and
the fix does not depend on which remaining one it is.

---

## 2. #21 — what the sidebar is for vs. the main pane

### 2.1 The duplication, costed

Measured on Reconstruct, comparing 0 unmet prerequisites against 4 unmet (the
release owner's real Si_SiGe case had 5, so this understates it):

| | 0 unmet | 4 unmet | Cost |
|---|---|---|---|
| Main pane: chrome above the image panes | 208pt | **399pt** | **+191pt** |
| Image pane size | 646×646 | **516×516** | **−36% of image area** |
| Sidebar document | 993pt | 1040pt | +47pt (into a column already 122pt short) |

So the prerequisite list costs **191pt of the main pane and 47pt of the
sidebar — for the same information, twice.** That is the whole of the "cramped"
complaint, quantified.

### 2.2 The question to answer first

Today both surfaces carry readiness. The sidebar is *navigation + every task's
settings + a readiness summary for the selected task*; the main pane is
*identity + the primary action + full readiness detail + the images*.

Note a real oddity in the current sidebar: `taskReadiness` sits inside the
**Task** section — a list of tasks — but describes only the *selected* task. A
list of things is the one place a per-item status belongs, and it isn't used
that way.

### 2.3 Three options

**Option A — "Sidebar navigates, main pane acts."**
Drop `taskReadiness` from the sidebar entirely; replace it with a compact
status glyph (✓ / orange dot) trailing *each* task button. The main pane's
`TaskPrerequisiteChecklist` becomes the single authority, unchanged.
*Gains:* removes the duplication; gives the sidebar a genuinely better
affordance (compare all tasks at a glance, not just the selected one).
*Costs:* −47pt sidebar only. Does nothing about the main pane's 191pt.

**Option B — "Sidebar owns readiness, main pane owns the image."**
Remove the checklist from `ProductWorkspaceHeader`; grow the sidebar's Task
section into the full checklist; leave a one-line "3 prerequisites missing —
see Task panel" under the disabled button.
*Gains:* main pane recovers the full 191pt; image panes stay 646².
*Costs:* pushes ~150pt *into* the already-overflowing sidebar (→ ~1190 vs 871),
making #16's scroll pressure worse — and it hides the reason a button is
disabled behind a pane the user can close (`showToolsPane`). That last point
contradicts Prompt B's founding premise, that a disabled action explains itself
*at the action*. **Not recommended.**

**Option C — "One owner, two densities." (recommended)**
The checklist is expensive because it renders all five requirements at equal
weight — *including the satisfied ones* — plus a button per unmet row,
permanently, above the images.

- **Main pane owns readiness** (it is attached to the action it gates), but at
  a density proportional to how blocked you are: collapsed to one summary row
  — "3 of 5 requirements missing" + disclosure + one primary action — with
  today's full list behind the disclosure. Expanded on first arrival at a
  blocked task; collapsed once seen.
- **Sidebar owns navigation and settings**, with Option A's per-task glyphs.
- Satisfied rows stop consuming permanent vertical space.

*Expected:* main pane chrome ~399pt → ~250pt when blocked (vs 208 unblocked);
sidebar −47pt; the "action explains itself" contract intact.

### 2.4 Recommendation

**Option C**, which subsumes A. It is the only one that improves both surfaces,
and it is the one that reduces the sidebar — which is what #16 needs from this
item.

---

## 3. #4 — when to draw the family caption

Workspace task lists and their families:

| Workspace | Tasks | Families |
|---|---|---|
| Image | virtualDetector, dpc | 1 (phase-contrast) |
| Map | disks, strain, acom | 2 (produces / requires) |
| Reconstruct | ptychography | 1 (phase-contrast) |

**Proposed rule: render the family caption only when the workspace's task list
contains more than one family.** Map keeps its captions; Reconstruct and Image
lose theirs.

**Deviation from the item's candidate.** The backlog offers "more than one
family *or* more than one task". I recommend **family only**. The caption's job
is to distinguish families; in Image there is one family and nothing to
distinguish, so a single caption over the whole list is the same noise as in
Reconstruct — the "or more than one task" clause would keep it there for no
work done. This is a judgement call about wording, not a measurement — flag it
if you disagree.

---

## 4. #17 — the stated benefit does not survive arithmetic

### 4.1 Rotation does not recover pane area

Measured: the real-space and diffraction panes are each ~660pt wide × ~646pt
tall, and the rendered image is fitted inside preserving aspect.

A 200×50 strain map (4:1) in a 660×646 pane renders at 660×165 → **25% of the
pane**. Rotated 90° it is 50×200 (1:4) and renders at 161×646 → **also 25%**.

**A 90° rotation is area-neutral in a pane that is not itself re-proportioned.**
So #17's stated 2026-08-05 justification — "rotating it 90° would let both panes
use their space" — does not hold. Dragging the HSplitView splitter to give
real-space 1000×646 gets a 4:1 image to ~39%, still mostly empty, because the
panes are side-by-side and therefore always full height.

What actually fits a 4:1 image is a **wide, short pane**: stacking the two panes
vertically (CBED above, strain strip below, full width) lets a 200×50 map fill
its pane essentially completely.

### 4.2 What this means for the item

Split #17 in two, because it is currently one item resting on the wrong reason:

- **#17a — aspect-aware pane arrangement.** This is what recovers the empty
  space for a 200×50 scan: choose the split axis (H vs V) from the displayed
  result's aspect ratio, or let the user pick. This is the item that closes the
  2026-08-05 observation.
- **#17b — display rotate/flip.** Still worth building, but for its *real*
  reason: presenting a map in the orientation a specimen/microscope convention
  or a published figure expects. Not for reclaiming area.

**Recommendation: do not build the rotation under the area justification.** If
the release owner only wants the space back, #17b is the wrong tool and #17a is
the right one.

### 4.3 If #17b is built anyway — the design, honouring every constraint

- **Control:** lives in the real-space pane's own chrome, never the global
  Display section. 90° steps + horizontal/vertical flip only. Labelled so it
  cannot be confused with the measured R–Q rotation — e.g. **"View orientation
  (display only — does not change data)"**.
- **Never offered for the diffraction pane.** The app has a measured R–Q
  rotation calibration; a display rotation of the CBED would be
  indistinguishable from it.
- **Inspector inverts, does not follow.** The cursor→position mapping applies
  the inverse transform so `Rx`/`Ry` keep reporting true scan indices.
- **Scale bar recomputes per axis.** For a non-square scan a 90° step swaps
  which R pixel size drives the displayed horizontal, so the bar's length must
  be recomputed, not re-rendered.
- **Export — the decision.** Recommend a split, which the existing mechanism
  already supports (`provenance: [String: String]` is carried through sidecars
  and bundles, and `display_domain` is already a key of exactly this kind in
  `Support/ResultExport.swift`):
  - **Publication figure (PNG): applies the rotation and records it** as
    `display_rotation_deg` / `display_flip` in provenance. The user rotated
    because they want the figure that way; silently un-rotating would surprise
    them.
  - **Scientific bundle (EMD): always writes unrotated data**, with the same
    two provenance keys recording the orientation the user was viewing.
  - The unacceptable outcome named in #17 — an unrecorded rotation baked into
    an exported figure — is excluded by the provenance keys being mandatory on
    both paths.
  - `Support/ResultExport.swift` is not `Core/`, so this stays inside the
    UI/workflow contract.

---

## 4b. Outcome — what was chosen and what actually shipped

The release owner chose **Option C** (§2.3), the **#17a/#17b split** (§4.2), and
the **figure-applies / data-doesn't** export rule (§4.3). All were implemented
the same day. Per-item detail lives in `docs/ui-workflow-backlog.md`; the two
places reality diverged from this document are:

1. **The checklist ships collapsed by default, not "expanded on first
   arrival".** §2.3 proposed expanding on arrival at a blocked task. Measured,
   that recovered **1pt of the 191** — the summary row costs roughly what
   collapsing the satisfied rows saves, so the entire win is in the collapsed
   state. Since the collapsed row still names the task, the count, and the first
   fix, Prompt B's "a disabled action explains itself at the action" contract
   survives. Blocked Reconstruct: 399pt → **231pt**, panes 516² → **646²**.
2. **#4's rule is family-count only**, not "family or task count" — see the
   backlog entry.

`.scrollBounceBehavior(.basedOnSize)` and #21's structural shrink both landed
for #16, and `SidebarLayoutTests` pins the healthy geometry, but **§6.3's manual
check is still outstanding** — the trigger remains unconfirmed.

## 5. Working-tree state

- `mac4DSTEMTests/SidebarLayoutTests.swift` — the diagnostic probe that produced
  §1 and §2.1, promoted to three real regression tests (sidebar clip origin,
  blocked panes keep their size, sidebar fits its column). The two that pin this
  change were verified to **fail** without it.
- `mac4DSTEMTests/ResultOrientationTests.swift` — 11 cases pinning the #17b
  pixel transform exactly.
- `tools/run-tests.sh unit` **92/92**, `scientific` **28/28**, both green.
- **`Core/` untouched.** Changes are `UI/`, `App/ProductWorkflow.swift`,
  `App/AppState.swift` (display-only state) and `Support/ResultExport.swift`.

---

## 6. What is needed from the release owner

1. **A decision on §2.3** (A / B / C) — this is the one that unblocks
   everything else, because #4's rule and #16's structural fix both follow from
   it.
2. **A decision on §4.2** — whether #17 splits into #17a/#17b, and whether the
   export split in §4.3 is right.
3. **A 60-second manual check for #16's trigger**, which cannot be done
   headlessly. With any dataset open:
   - Make the window small enough that the sidebar clearly scrolls (~1180×700).
   - Go to **Reconstruct**.
   - Two-finger scroll the sidebar **upward past its top** (rubber-band it)
     several times, releasing mid-bounce.
   - Watch whether the "Prepare"/"Workspace" rows end up drawn across the
     traffic lights, and whether the top rows stop responding to clicks.
   - If yes → the trigger is confirmed as top overscroll and
     `.scrollBounceBehavior(.basedOnSize)` is the fix. If no, try the same while
     switching workspace mid-scroll.
4. **Optional but high value:** granting Accessibility (and Screen Recording)
   to the terminal that runs `tools/ui-qc-playthrough/run.sh` also unblocks the
   QC acceptance re-run that has been outstanding since 2026-08-04.
