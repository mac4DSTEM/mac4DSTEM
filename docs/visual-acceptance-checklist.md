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

**Written 2026-08-18, drafted ahead of the UI it describes.** **Correction,
same day, evening:** L5's configurator landed (a06c624, 2b45fa0) and the
release owner drove part of this section the same evening — see the rows
below now marked PASSED. Remaining **PENDING UI** labels are stale in the
literal sense (the surface exists now); read them as *not yet driven*, same as
UNVERIFIED.

| # | Status | Check | Expect | Known trap |
|---|---|---|---|---|
| ~~F1.1~~ | **WITHDRAWN 2026-08-18** | ~~Watch the **preload** phase~~ | — | **This row could not pass on any dataset and should never have been written.** `preload` calls `makeResident`, which asks `ResidencyAdmission.shouldAdmit(.automatic, …)`; `measuredWorkingSetFraction` is deliberately `nil`, so it returns false immediately and there is no preload phase to watch. Residency is dormant *by decision* (L2). Driven on a 4.25 GB cube on 2026-08-18 and the release owner reasonably asked whether the dataset was too small — it was not. **Reinstate this row only when `measuredWorkingSetFraction` becomes non-nil.** |
| F1.1b | **PASSED 2026-08-18** | Open a multi-GB cube and watch the **preview sampling** phase | A determinate line naming the row: *"Sampling a preview · row 9 of 20"*, welcome card still up | Replaces F1.1. This is the phase that actually runs during an open today |
| F1.1c | **PASSED 2026-08-18** | Two datasets with the same file name in the recents list | Each row carries a location line that tells them apart — e.g. `eXtendedGROUPS` against `PL_SSD_2TB` | The duplicate was real but the de-duplication was innocent: two genuinely different paths, shown as one name. Confirmed in the same screenshots as F1.3b: `036_STEM_SI_preprocessed_filtered_bin_2_20240723.h5` appears twice in Recents, one row labelled `eXtendedGROUPS`, the other `PL_SSD_2TB`, both readable and not truncated |
| F1.1d | **PARTLY PASSED 2026-08-18** | Start opening a large dataset — ideally from the NAS — then press **Cancel** on the loading card | The load stops, the app returns to the welcome screen with no dataset, and the cancelled file is **not** added to Recents | The failure to look for is a half-loaded dataset that looks loaded: an inspector showing dimensions or a calibration for a cube whose pixels were never read. Also check the app is usable straight afterwards — opening a different file must just work. **Observed on a 17.19 GB `055_STEM SI.dm4`:** *Cancelling…* appeared, the app returned to the welcome screen with no dataset, and a different file opened straight afterwards. **Not yet checked: whether the cancelled file stayed out of Recents** — that half of the row is still open |
| F1.2 | **PASSED 2026-08-18** | The **Preview** section of the dataset inspector (L5 preview half, landed 2026-08-18) | A real-space image and mean/max DP, with a summary line naming the stride: *"Sampled preview · every 3rd position · 1,024 of 28,458"* | The preview grid is the **sample's** dimensions, not the scan's. It will not line up pixel-for-pixel with a virtual image, and that is correct — the label is what stops it being filed as a bug |
| F1.3 | **PASSED 2026-08-18** | Try to export or promote the preview | There is **no** control that does it | Invariant I4 is enforced by type, so the absence of a control is the check |
| F1.3b | **FAILED 2026-08-18 · fix landed same day, UNVERIFIED — re-drive this row first** | Press **Open with Options…**, pick a large dataset | The configurator appears with both previews, a stride line, a bin picker and the size table. **"Open Dataset…" must behave exactly as before** — no configurator, no extra step | The opt-in entry, stride line, bin picker and size table were all correct and plain open was untouched, but **neither preview image drew** — raw pixels passed to a view whose contract requires normalized ones, so both panes rendered one flat colour. Fixed in `LoadConfiguratorView.swift:74,92`; **nobody has seen the result.** Look for actual structure: the real-space pane should show scan contrast, the diffraction pane a log-scaled max pattern with visible Bragg disks — not a uniform field, and not just a central blob. The row was first scored PASSED on the dialog *appearing*, which is the mistake Track B exists to prevent: the labels were read and the image area was not |
| F1.3c | **PASSED 2026-08-18, with a caveat** | In the configurator, drag a box on the **real-space** preview, press Load, then read the inspector's *Loaded view* | The loaded scan extent is the region that was circled | The preview is on the sampled grid. A missing stride multiplication puts the crop at a fraction of the intended position — looks like a UI glitch, is a data defect. Unit-tested, gesture wiring is not. Confirmed: *Loaded view · scan rows 20–35, columns 28–79 · binned 2x*, and it persisted correctly into Prepare, Map and Strain. **Caveat: the drag was made against an empty pane** (F1.3b), so this proves the gesture→crop→load→display chain, **not** that the crop matches what the user meant to circle. Re-run once the previews draw |
| F1.3d | **UNVERIFIED** | Configure a bin of 8 on a detector that does not divide by 8 | The configurator states the trim (rows and columns from the far edge) **before** loading, and the inspector repeats it after | Silent trimming is the trap — you asked for one extent and got a smaller one |
| F1.3e | **UNVERIFIED** | Press Load with nothing configured | Identical to a plain open — full extent, no *Loaded view* section in the inspector | Full extent must stay the identity, or "remove the specification to promote to the full dataset" quietly stops working |
| F1.3f | **PARTLY OBSERVED 2026-08-19 — the restore failure reproduced and diagnosed; the crop half still unverified** | Load with a crop, save the session, quit, reopen the same file | It reopens **with the same crop**, and the inspector's *Loaded view* matches what was saved | The specification is re-applied to the SOURCE file, never re-derived from reduced data. If a sidecar sits next to a file it does not fit, the app must load the whole file and say so rather than clamp. **Watch for the session-restore error seen 2026-08-18.** Its wording CHANGED in S1: a current build says `HDF5 failed while opening the session sidecar — HDF5 reported: <reason>`, not the old `HDF5 export failed while …`. **If it appears, copy the whole line** — the reason after `HDF5 reported:` is the diagnosis. **A sandbox denial reads `errno = 1 … 'Operation not permitted'`, NOT `Permission denied`** — measured 2026-08-19; `errno = 13 … 'Permission denied'` is a POSIX mode/ownership problem and means the sandbox is *not* the cause. `file signature not found` ⇒ the file itself; `unable to lock file` ⇒ the volume. (An earlier version of this row named `Permission denied` as the sandbox signature. That was wrong and would have made the observer rule the sandbox out on the one run that decides it.) **Also note:** the two sidecars in `References/training_dataset/` pre-date the load-specification attribute (added 2026-08-18), so their specification is *unknown* rather than full-extent — this row needs a session saved from a *cropped* view first; reopening those two proves nothing about a crop. **2026-08-19: the failure was reproduced and the reason string captured** — `errno = 1, error message = 'Operation not permitted'` on `sim_Au_data_all_binned.mac4dstem.h5`, i.e. the sandbox, exactly as this row's warning anticipated. The fix landed the same day; the crop-survives-reopen half of this row is now **F1.3h** |
| F1.3g | **UNVERIFIED — queued by S1, 2026-08-19** | Open `downsample_Si_SiGe_exp.h5` from `References/training_dataset/` **without ever having saved a session for it in this build**, then read the dataset inspector | A **Session sidecar** section saying *"A saved session sits beside this dataset and could not be read"*, the reason beneath it, and the line *"The whole file is loaded…"* | This is S1's user-visible half and it exists because the status line does **not** survive: the message `recordedLoadSpecification` writes is overwritten by the loading stage three lines later, then twice more — measured, not assumed. So the check is that the **inspector** carries it after the load settles, not that a status line flashed. Use `downsample_Si_SiGe_exp.h5` specifically: `sim_Au_data_all_binned.mac4dstem.h5` was rewritten at 09:35:21 on 2026-08-19 and probably has a bookmark now, which makes it the *wrong* dataset for this row. **If no section appears, check whether the sidecar opened fine** — that is a pass for F1.3h, not a failure here |
| F1.3h | **UNVERIFIED — queued by S1, 2026-08-19** | With a **cropped** view loaded, save the session (File ▸ Save Calibration to Session Sidecar), accept the panel, quit, relaunch, reopen the same cube | It reopens **with the same crop**, and no *Session sidecar* warning appears | The positive half of F1.3g and the first end-to-end test of S1's fix. Before S1 the crop would have been dropped even with a grant, because `recordedLoadSpecification` never consulted the bookmark. **The trap to watch for:** the inspector's file tree should name the sidecar you actually chose in the panel — if you renamed it, the name shown must be the new one. That label derived its own path until S1 and would have named a file the app was not reading |
| F1.4 | **PASSED 2026-08-18** | `Loaded view · …` summary line when a crop or bin is set | Names the extent in **source** pixels — *"scan rows 128–255"*, not *"128 rows"* | A user deciding whether to re-run at full extent needs to know *where* they were looking, not how much. Confirmed: *"scan rows 20–35, columns 28–79 · binned 2x"* |
| F1.5 | **PASSED 2026-08-18** | Binning notice | States that intensities are **summed**, so they are `bin²` larger, and that the reciprocal pixel size is `bin` × coarser | py4DSTEM sums too, but silently. An absolute-intensity threshold carried over from an unbinned run does not mean the same thing, and only this line says so. Confirmed at bin 2x: "intensities become 4x larger and the reciprocal pixel size 2x coarser" |
| F1.6 | **UNVERIFIED** | Bin a detector whose size does not divide (e.g. 130 px by 8) | An explicit line: *N* detector rows and *M* columns trimmed from the far edge | Silent trimming is the trap — the user asked for one extent and got a smaller one |
| F1.7 | **UNVERIFIED** | On the **diffraction** preview, drag a crop into one *corner* — e.g. detector rows 0–63 of 250 — so the beam near the centre is not in the loaded region | The origin is **invalidated with a named reason** and the aperture falls back to the geometric default | It must never be clamped into the crop. A clamped origin puts the beam at a pixel it is not at and every downstream number looks fine. **Row reworded 2026-08-18** — "crop so the direct beam falls outside" read as impossible, and the objection was fair: a detector crop is a *selection of detector pixels* (offset + extent), nothing like a real-space ROI, and any **centred** crop keeps the beam by construction. An **off-centre** one does not. This is a guard against a mis-drag, not a workflow anyone wants — but the refusal has to be visible when it happens |
| F1.8 | **UNVERIFIED** | Set a real-space crop with existing strain / ACOM / Bragg results on screen | Those results are cleared, with a message saying the same index now names a different position | *Ambiguous*, not stale — and the reason has to be visible, or it reads as the app losing work |
| F1.9 | **UNVERIFIED** | Drag a crop rectangle **bottom-right to top-left**, and past the edge of the image | Same rectangle either way; dragging past the edge clamps to the edge | Unit-tested (`LoadConfigurationTests`), but the gesture wiring is not |
| F1.10 | **UNVERIFIED** | Drag a crop on the **real-space** preview at a stride > 1, then check the loaded extent | The loaded region is the one that was circled | The preview is on the sampled grid: a missing stride multiplication puts the crop at a fraction of the intended position. Looks like a UI glitch, is a data defect |
| F1.11 | **UNVERIFIED** | Select the entire image as a crop | The app reports full extent — no crop — rather than a crop that happens to cover everything | `isFullExtent` is what makes "remove the specification to promote to the full dataset" work |
| F1.12 | **PASSED 2026-08-18** | Read the copy on the open screen | Loading into memory does **not** claim to make the load faster | #30 established the cost is the link, not the algorithm. It makes the waiting happen once, at a moment the user chose. Confirmed: "Loading into memory does not make the load faster — it makes the waiting happen once, when you choose" |
| F1.13 | **PASSED 2026-08-18** | The local-storage notice | One quiet line of guidance, not a warning, blocking nothing | Confirmed present as plain guidance text ("Work from a local disk. Datasets opened over a network share stream far more slowly…"), not styled as an error |

---

## Recording a run

Put the outcome in [`docs/open-items.md`](open-items.md) — the date, the
dataset, what was driven, and every finding. Screenshots live wherever the
release owner keeps them; the repo does not need them, but the **findings**
must not live only in a chat log.

Until an automated visual baseline exists, any claim that a UI change "looks
right" rests on someone having looked. Say who, and when.
