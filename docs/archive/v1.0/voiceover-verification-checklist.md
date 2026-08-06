# VoiceOver & increased-text-size verification

> ## ⏸️ DEFERRED TO v2.0 — do not run this for v1
>
> **Decision, 2026-08-05 (release owner).** Screen-reader usability was removed
> from the v1 "Mac experience" release gate in `docs/v1-scope.md`: no current or
> near-term user of this app needs it, so the verification cost bought nothing
> at v1. This document is **parked, not cancelled** — it is kept so v2.0 starts
> from a written procedure instead of from scratch.
>
> **What did NOT get deferred, and must not be removed from the code:** the
> accessibility **identifiers** and **label associations** that shipped
> 2026-08-04 and 2026-08-05. They are not there for screen readers — they are
> the surface XCUITest matches on, and
> `mac4DSTEMUITests/Support/AXDriver.swift` depends on them. Deleting them
> because "accessibility is deferred" would break the QC playthrough.
>
> **One part is worth keeping as ordinary UI review: Part 4.** Increased text
> size has nothing to do with screen readers — it is a cheap layout stress test
> that finds truncation and overlap, which is the class of bug this UI has been
> producing. Run it when the sidebar changes; it is not a gate.
>
> **Unverified when parked:** Part 2 items **2.1 and 2.2** — the redesigned
> detector/region shape pickers use `.labelsHidden()` plus a separate
> `accessibilityLabel`, which is structurally the same construct that caused the
> original defect. Nobody has ever heard them. If a v2.0 pass finds them
> announcing as bare values, that is a known-suspected regression, not a
> surprise.

**How to use it** (when v2.0 picks it up). Tick each row, and for anything that
fails write down *what you actually heard* — the announcement text is the bug
report. Hand the failures back; don't try to interpret them.

**Time:** ~25 minutes for Parts 1–3, ~10 for Part 4.

---

## Part 0 — setup

- **VoiceOver on/off:** ⌘F5 (some Macs: triple-press Touch ID).
- **The VO keys** are **Control + Option**. Useful ones:
  - `VO + →` / `VO + ←` — move to next/previous element
  - `VO + Space` — activate the focused control
  - `VO + Shift + ↓` — step *into* a group; `VO + Shift + ↑` — step out
  - `VO + U` — rotor (list of controls/headings)
  - `VO + A` — read the whole window from the top
- **Slow the speech down** first if it's unfamiliar: VoiceOver Utility ▸ Speech ▸
  Rate. It makes the difference between "that sounded fine" and actually
  catching a missing label.

> A control **passes** if you hear **what it is** *and* **what it currently
> is set to**. Hearing only a value ("Annulus, pop up button") is a **fail** —
> that is exactly the detached-label defect this gate exists for.

---

## Part 1 — the controls Prompt D flagged (highest priority)

These are the ones the QC harness could not reach by identifier and had to find
structurally, which is what raised the suspicion. Open the demo dataset or any
training cube first.

| # | Where | What to do | PASS sounds like | Watch for |
|---|---|---|---|---|
| 1.1 | **Reconstruct ▸ Ptychography**, "Voltage" row | `VO + →` onto the field | "Accelerating voltage, 200, text field" | Hearing only "200, text field" — the label is a separate `Text` in an HStack |
| 1.2 | **Map ▸ Strain**, Reference picker | Focus it, then `VO + Space` | "Reference, Whole-scan mean, pop up button" | Just "Whole-scan mean" |
| 1.3 | **Map ▸ Strain**, Basis picker | same | "Basis, Automatic, pop up button" | same |
| 1.4 | **Map ▸ Strain**, Component picker | same | "Component, ε_xx, pop up button" | Greek/subscript read as gibberish — note it verbatim |
| 1.5 | **Map ▸ Orientation**, Display picker | same | "Display mode, IPF·Z, pop up button" | "Display" colliding with the sidebar's *Display* section header |
| 1.6 | **Map ▸ Strain** diagnostics rows | `VO + →` across them | "Basis consensus, 94%, 222588 of 237233 peaks" | Label and value announced as two unrelated elements |
| 1.7 | **Map ▸ Orientation**, Work / Expected rows | same | "Expected, about 2 seconds" | Value with no label |

---

## Part 2 — controls added since Prompt D (nobody has ever heard these)

Added during the 2026-08-05 design pass and follow-ups. **2.1 and 2.2 are the
highest-risk items in this document**: they use `.labelsHidden()` with a
separate `accessibilityLabel`, which is the same shape of construct that caused
the original problem. If the label was stripped rather than replaced, they will
announce as bare values.

| # | Where | What to do | PASS sounds like | Watch for |
|---|---|---|---|---|
| 2.1 | **Image ▸ Virtual imaging**, click the *diffraction* pane, then "Detector → real space" ▸ shape control | Focus it | "Detector shape, Annulus" | Bare "Annulus" with no "Detector shape" — **report this one specifically** |
| 2.2 | Same section, click the *real-space* pane ▸ "Region → diffraction" shape control | Focus it | "Region shape, Point" | as above |
| 2.3 | Same section, the **BF / ADF / HAADF** preset buttons | Focus each | "Apply Bright Field preset, button" | Hearing the abbreviation "B F" instead of the full name |
| 2.4 | **Sidebar ▸ Task**, each task row | `VO + →` down the list | "Bragg disks, ready" / "Strain, 2 requirements missing" | The readiness half missing — the ✓/! glyph is *only* conveyed through this label |
| 2.5 | **Reconstruct** with unmet prerequisites, the summary row | Focus the chevron | "Show requirement detail, button" | No indication of collapsed/expanded state |
| 2.6 | Same, expand it, then walk the rows | `VO + →` | "Set the R pixel scale, Missing" then "Open Prepare, button" | The satisfied line reading as one run-on string |
| 2.7 | A workspace that is ready but limited | Focus the guidance block | "Ready, limited interpretation" then the reason, then "Improve in Prepare, button" | |
| 2.8 | Any real-space result ▸ **View orientation** menu (the rotate icon) | Focus it | "View orientation, display only, currently 0°" | Missing "display only" — that phrase is what stops it being confused with the R–Q rotation |
| 2.9 | Set a **rectangle** ROI in Image, then go to **Map ▸ Bragg disks** | Focus the orange ROI SUM badge | "Showing a region-summed pattern, not a single scan position" | Badge skipped entirely (it is decorative-looking but carries real meaning) |
| 2.10 | Force a strain failure (e.g. run Strain on a cube with too few peaks) | Focus the remedy block | The cause, then "Go to Bragg Disks, button" *or* "Use the current ROI as the reference, button" | |

---

## Part 3 — the primary workflow, end to end, VoiceOver only

This is the actual wording of the release gate, so it is the part that decides
it. **Keyboard and VoiceOver only — do not touch the mouse or trackpad.**

- [ ] **3.1** Open a dataset (⌘O, or Reopen from the Welcome screen).
- [ ] **3.2** Reach **Prepare** and hear which calibrations are Missing.
- [ ] **3.3** Run **Calibrate Origin** from the primary action, and hear when it
      finishes — progress and completion must be announced, not silent.
- [ ] **3.4** Move to **Map ▸ Bragg disks** and run **Detect All Disks**.
- [ ] **3.5** Hear the result: peaks found, and the per-pattern median.
- [ ] **3.6** Move to **Strain**, run it, and hear either the diagnostics or the
      failure *with its remedy*.
- [ ] **3.7** Go to **Results**, and hear the result title **and its
      interpretation status** (Quantitative / Relative / Exploratory /
      Categorical). P2.3 says that status is how a result is interpreted, so
      it must be spoken, not only coloured.
- [ ] **3.8** Export a PNG and hear the save panel and the confirmation.

**Note anywhere you had to guess** what a control did, or where focus jumped
somewhere unexpected. "It worked but I had no idea where I was" is a fail for
this gate.

---

## Part 4 — increased text size

**System Settings ▸ Accessibility ▸ Display ▸ Text size** (path moves between
macOS releases; if it isn't there, use **Displays ▸ scaled resolution** at the
largest "Larger Text" setting as a proxy). Set it to a large value with
mac4DSTEM open, then walk the primary workflow again.

The sidebar is the expected casualty — it packs many `.caption2` rows, and the
design pass added more captions to it (the Reference/Basis explanations and the
task family labels).

- [ ] **4.1** Sidebar: no row **truncates** its text to the point of losing
      meaning (a "…" mid-sentence on a calibration explanation is a fail).
- [ ] **4.2** Sidebar: nothing **overlaps** or spills outside the column.
- [ ] **4.3** The prerequisite checklist in the main pane stays readable and
      does not push the image panes to nothing.
- [ ] **4.4** The **BF / ADF / HAADF** preset row still fits on one line, or
      wraps cleanly rather than clipping.
- [ ] **4.5** Buttons still show their whole label (check "Use the current ROI
      as the reference" and "Improve in Prepare" — the longest ones).
- [ ] **4.6** Numeric read-outs (peaks found, κ, RMS, throughput) are not
      truncated — a clipped number is worse than no number.

---

## Recording the result

Fill this in and hand it back:

```
Date:
macOS version:
VoiceOver:  Part 1 __/7 pass   Part 2 __/10 pass   Part 3 __/8 pass
Increased text size: Part 4 __/6 pass

Failures (control → what you actually heard / saw):
  -
```

**No longer gates v1.** The screen-reader clause was removed from the
`docs/v1-scope.md` "Mac experience" gate on 2026-08-05, so filling this in is
v2.0 work. Partial is still fine to report — a documented failure is worth more
than an untested pass.
