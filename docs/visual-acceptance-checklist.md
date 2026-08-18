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
| **Inspector → Preview** (new 2026-08-18, **never seen on screen**) | Three thumbnails — real space, mean pattern, max pattern — under a summary line reading e.g. *"Sampled preview · every 3rd position · 1,024 of 28,458"*, plus *"Not a result — cannot be exported or saved."* | The label is the whole safeguard (I4). If the summary is clipped, wraps badly, or sits *below* the images, the preview can be read as a virtual image — and a strided preview genuinely differs from one. Also check the real-space thumbnail is not stretched: it is the sample's grid, not the scan's |
| Loading card during open | A determinate *"Sampling a preview · row N of M"* phase appears before the whole-cube pass | New phase; it should read as progress, not as a stall, and must not linger on a small dataset where the preview is instant |
| Open Recent, after a successful open | The file reopens | *"Recent-file access could not be remembered"* was logged in the clean-account run — but on a **hard link** staged into `/Users/Shared`. Re-test with a plain copy before calling it a defect |
| **Switching datasets** inside a multi-dataset file (the dataset list, not Open) | The loading card and a moving bar appear for the switch, then clear — the same treatment as opening the file | **Unverified on screen, changed 2026-08-17.** `selectDataset` now brackets the switch with `beginDatasetLoading`/`finishDatasetLoading` so the resident preload can report progress; before, it read a multi-gigabyte cube in silence behind "Loaded …" with the bar at 1.0. The bracket is right semantically but nobody has *looked* at what the card does over an already-populated workspace |

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

#### F1. The queued backlog — nothing below has been seen on screen by anyone

**Written 2026-08-18, drafted ahead of the UI it describes.** Rows marked
**PENDING UI** describe surfaces that exist in the model but that no view reads
yet; they become runnable when L5's configurator lands. Rows marked **RUNNABLE
NOW** can be driven today and have been waiting through three stages.

Run this whole sub-section in **one** pass once L5's configurator is in — that
is the point of holding it, rather than accumulating four separate half-passes.

| # | Status | Check | Expect | Known trap |
|---|---|---|---|---|
| F1.1 | RUNNABLE NOW | Open a multi-GB cube and watch the **preload** phase (L2, landed 2026-08-17) | Progress is bracketed as a load: patterns and MB both advancing, welcome card still up | `selectDataset` used to preload with progress reporting **disabled** — #36's stall one layer down. Fixed but never seen |
| F1.2 | RUNNABLE NOW | The **Preview** section of the dataset inspector (L5 preview half, landed 2026-08-18) | A real-space image and mean/max DP, with a summary line naming the stride: *"Sampled preview · every 3rd position · 1,024 of 28,458"* | The preview grid is the **sample's** dimensions, not the scan's. It will not line up pixel-for-pixel with a virtual image, and that is correct — the label is what stops it being filed as a bug |
| F1.3 | RUNNABLE NOW | Try to export or promote the preview | There is **no** control that does it | Invariant I4 is enforced by type, so the absence of a control is the check |
| F1.4 | PENDING UI | `Loaded view · …` summary line when a crop or bin is set | Names the extent in **source** pixels — *"scan rows 128–255"*, not *"128 rows"* | A user deciding whether to re-run at full extent needs to know *where* they were looking, not how much |
| F1.5 | PENDING UI | Binning notice | States that intensities are **summed**, so they are `bin²` larger, and that the reciprocal pixel size is `bin` × coarser | py4DSTEM sums too, but silently. An absolute-intensity threshold carried over from an unbinned run does not mean the same thing, and only this line says so |
| F1.6 | PENDING UI | Bin a detector whose size does not divide (e.g. 130 px by 8) | An explicit line: *N* detector rows and *M* columns trimmed from the far edge | Silent trimming is the trap — the user asked for one extent and got a smaller one |
| F1.7 | PENDING UI | Crop so the direct beam falls **outside** the diffraction crop | The origin is **invalidated with a named reason** and the aperture falls back to the geometric default | It must never be clamped into the crop. A clamped origin puts the beam at a pixel it is not at and every downstream number looks fine |
| F1.8 | PENDING UI | Set a real-space crop with existing strain / ACOM / Bragg results on screen | Those results are cleared, with a message saying the same index now names a different position | *Ambiguous*, not stale — and the reason has to be visible, or it reads as the app losing work |
| F1.9 | PENDING UI | Drag a crop rectangle **bottom-right to top-left**, and past the edge of the image | Same rectangle either way; dragging past the edge clamps to the edge | Unit-tested (`LoadConfigurationTests`), but the gesture wiring is not |
| F1.10 | PENDING UI | Drag a crop on the **real-space** preview at a stride > 1, then check the loaded extent | The loaded region is the one that was circled | The preview is on the sampled grid: a missing stride multiplication puts the crop at a fraction of the intended position. Looks like a UI glitch, is a data defect |
| F1.11 | PENDING UI | Select the entire image as a crop | The app reports full extent — no crop — rather than a crop that happens to cover everything | `isFullExtent` is what makes "remove the specification to promote to the full dataset" work |
| F1.12 | PENDING UI | Read the copy on the open screen | Loading into memory does **not** claim to make the load faster | #30 established the cost is the link, not the algorithm. It makes the waiting happen once, at a moment the user chose. Copy implying otherwise will make the feature read as broken |
| F1.13 | PENDING UI | The local-storage notice | One quiet line of guidance, not a warning, blocking nothing | ≈3.3 MB/s over a NAS, latency-dominated — real advice, but it must not look like an error |

---

## Recording a run

Put the outcome in [`docs/open-items.md`](open-items.md) — the date, the
dataset, what was driven, and every finding. Screenshots live wherever the
release owner keeps them; the repo does not need them, but the **findings**
must not live only in a chat log.

Until an automated visual baseline exists, any claim that a UI change "looks
right" rests on someone having looked. Say who, and when.
