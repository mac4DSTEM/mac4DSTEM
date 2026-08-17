# Visual acceptance — Track B

**The human half of verification.** Adopted 2026-08-17
([`docs/v2-scope.md`](v2-scope.md) §6.2–6.3) when the XCUITest QC playthrough
was retired as the acceptance test.

This is not a fallback for missing automation. It catches a **disjoint class of
defect**, and it has out-performed the full automated suite twice:

- **2026-08-06**, tag day, all 30 harnesses green — ten minutes of driving the
  app by hand produced two real defects: a colormap control absent from the only
  workspace that needed it, and a readiness row contradicting its own detail
  line.
- **2026-08-14**, first clean-account run, roughly fifteen minutes — three more,
  none reachable by any harness in the repo.

It is also the only thing that can answer *"are these detected disks **right**?"*,
which is a judgement, not a measurement.

---

## When to run it

**Any change to what the app draws, or to where a control lives.** Also before
any tag, and after any macOS version bump.

Not needed for: numeric-only changes with a `tools/` fixture, doc changes, or
build/packaging work that does not alter a screen.

---

## How it works

1. The assistant writes a **short, specific** checklist for the change at hand —
   what to open, what to expect, and what would count as wrong. Specific: *"the
   Result workspace colormap picker is present and changes the map"*, not
   *"check the Results screen"*.
2. The release owner opens the real app, drives it once, and sends screenshots.
3. Anything that looks wrong becomes an item in
   [`docs/open-items.md`](open-items.md) — **not** an app-code change made to
   satisfy the checklist. The eval-only rule that governed the QC playthrough
   carries over unchanged: *if the app blocks the pipeline, that is a finding.*

Ten to fifteen minutes of human time. Budget it as part of "done", the way doc
updates are.

---

## The standing pass

Run this whole list for a tag or an OS bump. For a single change, run the rows
it plausibly touches plus §A.

### A. Open and load — every run

| Check | Expect | Known trap |
|---|---|---|
| Welcome card during a multi-GB open | Named spinner for metadata phases with **no** percentage; the determinate bar only during the whole-cube pass, reading `Scanning patterns 1,378 / 16,218 patterns · 344 MB of 3.96 GB` | The welcome card must **not** vanish while the app is still scanning — that reorder is what fixed "sits there looking stuck" (L1) |
| The same, on a **non-English system locale** | Pattern counts group with `.`-vs-`,` consistently against the MB figure | A German system once rendered `1.378 / 16.218 patterns · 3.96 GB` — two meanings of "." in one line. Pinned by a test now, but the class is visual |
| Dataset inspector | Dimensions, *Cube (f32)*, calibration provenance all populated | — |
| Open Recent, after a successful open | The file reopens | *"Recent-file access could not be remembered"* was logged in the clean-account run — but on a **hard link** staged into `/Users/Shared`. Re-test with a plain copy before calling it a defect |

### B. Prepare

| Check | Expect | Known trap |
|---|---|---|
| Readiness rows | Each row's summary agrees with its own detail line | A row read *"Missing"* for an origin that had been measured — found by eye, invisible to the suite |
| Sidebar at the default width | Nothing clipped, no row pushed off the top of the column | `SidebarLayoutTests` measured 933pt against 871pt of column on macOS 27; it also stayed green for months with a real overflow on screen |
| Sidebar dragged narrow, then reopened | Restores no narrower than the declared 250pt minimum | Observed restoring at 144pt. Test harnesses pin the width; the app does not |
| Fit overlays (origin, ellipse) | Overlay lands on the feature it claims to fit | The refuting evidence for a wrong diagnosis has twice been a residual already printed in the log |

### C. Disk detection — the judgement call

| Check | Expect | Known trap |
|---|---|---|
| Detected disks drawn over a real DP | Disks on the actual Bragg peaks, at plausible density | **A run that finds only the central beam still produces a number and a green step.** This row is the whole reason Track B exists |
| `minRelative`, `minPeakSpacing`, correlation power | Present, reachable, and moving them visibly changes the result | No automated test has ever touched one of these controls |
| Peak count in the status line | Matches what is drawn, and matches the count after the run settles | The retired harness logged 16,384 against the app's own later 213,441 |

### D. Maps and results

| Check | Expect | Known trap |
|---|---|---|
| Strain map on `downsample_Si_SiGe_exp` | Quantitative ε_xx with the expected SiGe layer periodicity | — |
| Result workspace colormap control | Present and functional | It was **absent** from the only workspace that needed it, on tag day. SwiftUI builds a `Picker`'s menu lazily for an assistive client, so in-process tests see a blank pop-up and can assert nothing here |
| Colorbar + scale bar on a **tall, narrow** scan (e.g. 200 × 50) with a display rotation | Both readable, neither overlapping | Both are bottom-anchored with no awareness of one another; observed colliding |
| Result labels | Quantitative / Relative / Exploratory / Categorical persist through navigation | — |

### E. Export

| Check | Expect | Known trap |
|---|---|---|
| Burned-in caption on an exported figure | Reads to the end | Observed truncating: `…basis_mode=consensus · reference_mode=whole-scan · displa…`. That caption **is** the provenance record and it is the part that travels into a paper |
| Reopen an exported session | Calibration, labels and provenance survive identically | — |

### F. Load pipeline — add as stages land

| Stage | Check |
|---|---|
| L2 | Resident vs streaming is visible at a glance; the preload reports patterns **and** MB determinately; "Release cube" works |
| L3/L4 | Crop and bin vocabulary never sits in the same section as `realSpaceShape` / `acomRegionRadius` — **a crop is not an ROI** |
| L5 | The sampled preview is visibly marked as sampled **with its stride stated**, and cannot be exported; the size arithmetic (file bytes / cube f32 / headroom / cost of the current specification) is on screen |
| L6 | The load specification is shown wherever provenance is shown, and survives reopen |

---

## Recording a run

Put the outcome in [`docs/open-items.md`](open-items.md) — the date, the
dataset, what was driven, and every finding. Screenshots live wherever the
release owner keeps them; the repo does not need them, but the **findings**
must not live only in a chat log.

Until an automated visual baseline exists, any claim that a UI change "looks
right" rests on someone having looked. Say who, and when.
