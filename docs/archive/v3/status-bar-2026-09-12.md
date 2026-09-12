# The status bar, and what the owner's drive found — 2026-09-12

He drove phase mapping and reported two things:

> "otherwise UI is clean except for the cancel button and the other info in
> the bar below, which seem not to be simple, stupid, macos as i requested"

Three independent designs were produced — one from Apple's guidance outward,
one by deletion, one for internal consistency — and an adversarial critique
attacked all three against this repo's own layout rules. What follows is what
survived, and the several places where all three were wrong together.

## The cancel button: measured, not guessed

`Button("Cancel", role: .cancel).controlSize(.mini)`. Control metrics on this
machine (macOS 27.0, 26A5388g):

| controlSize | label font | fitted "Cancel" push button |
|---|---|---|
| `.regular` | 13.0 pt | 66.0 × 24.0 |
| `.small` | 11.0 pt | 56.0 × 20.0 |
| **`.mini`** | **9.0 pt** | **46.5 × 16.0** |

The strip's own text is `caption2` = **10.0 pt**. So the one control a user
must be able to read and hit was rendered *smaller than the smallest text
around it*.

**Why it looked circular rather than like a pill — reproduced, not theorised.**
The `StatusBar` HStack was rebuilt standalone and rendered: at 1400 pt it reads
`Cancel`; at **1080 pt it collapses to `C…`**. A ~16 × 16 pt capsule holding one
letter and an ellipsis is exactly the "tiny unreadable grey shape, roughly
circular" reported.

The mechanism: the Cancel button was **the only child of the busy group not in
a reserved slot**, and its label is a flexible `Text`. The bar, the percentage
and the metrics line are all pinned to constants, so a short row took the
deficit out of the two remaining flexible children — the status message and the
button's own label.

**This repo had already diagnosed the identical failure and fixed it elsewhere.**
`WorkspaceView.swift`, on `PrimaryActionButton.operationProgress`, says
verbatim: the old inline progress bar was removed from the toolbar because *"it
squeezed the Cancel button until its label truncated to 'C…'"*. Same disease,
same signature string, cured in the toolbar and never cured in the strip.

**The remedy is Apple's own.** `NSImage.stopProgressFreestandingTemplateName`
is documented as "a stop progress template image — **you can use this image to
implement a borderless button**". Finder's copy sheet, Safari's downloads
popover and Mail's Activity window all stop work with a borderless glyph
attached to the progress it stops; not one is a bordered button reading
"Cancel". And the repo's own Remove-from-Recents row, forty lines above in the
same file, is already `xmark.circle.fill` + `.buttonStyle(.borderless)`. Apple's
API and the in-app precedent converge on the same control.

One deliberate deviation from that precedent: `.secondary`, not `.tertiary`.
The faintest thing in the strip is the wrong weight for the control that stops
a forty-minute compute.

The HIG's answer to losing the word is the tooltip: *"the system displays a
tooltip after people hover over a button for a moment"*. The glyph carries
`.help()` and an accessibility label.

**And a real accessibility bug, found on the way.**
`.accessibilityElement(children: .combine)` on the busy group was merging the
Cancel button out of the tree *as a button* — the control was unreachable to
VoiceOver, which is the opposite of what combining was for. Removed.

## "The other info": what went, and where it lives now

| element | verdict |
|---|---|
| the `0 %` label | **deleted.** `ProgressView` has no percentage API, `NSProgressIndicator` has none, and the HIG never asks for one — the bar *is* the percentage. This app's own loading card, one screen away, already draws a determinate bar with no numeral. The number now reaches VoiceOver on the bar's `.accessibilityValue`, where it is useful and cannot wrap — which also closes the wrap defect it was reserved against |
| throughput | **deleted from the strip**, kept in Info › Performance. See `decisions.md` — this narrows a 2026-09-04 owner decision and is recorded as such |
| elapsed, ETA | **kept.** Elapsed is the certain number; ETA is the decision-relevant one. Neither is derivable from anything else on screen, and for a forty-minute detection the ETA is what turns waiting into a choice |
| app RSS, cube bytes | **deleted.** A debugger readout and a static property of the file, both already in Info › Performance. `footerFacts` also called `SystemMonitor.residentMemoryMB()` — a raw `task_info` — directly from `StatusBar.body`, which re-runs on every progress tick |
| `residency.summary` | **moved to the sidebar's Dataset row**, not to the inspector. Its own doc comment gives the reason: resident and streaming produce *identical numbers*, so nothing else on screen tells a user which path their analyses took. That makes it provenance, and provenance belongs beside the dataset rather than four interactions deep in a collapsible tab |
| the log toggle | **unchanged.** Already the app's own icon-control idiom |
| the status message | kept, plus `.help()` — the owner's screenshot shows it cut mid-filename with no way to read the rest, and the sidebar's dataset row already answers that with exactly this modifier. Its `.layoutPriority(1)` competitor, the facts text, is what was truncating it |

## Three things the critique found that no design did

1. **`.layoutPriority(1)` on the facts text outranked the status message** in
   the width contest. That is the mechanism behind the truncated filename —
   half the complaint — and it is fixed by deleting the facts, not by tuning.
2. **During a dataset OPEN the strip drew a bar into nothing.** `isBusy` is
   true, `activeOperationMetrics` is nil outright, `canCancel` is false — so
   190 pt of guaranteed blank sat beside a loading column that has its own
   spinner and its own Cancel. `showsOperationProgress` is the gate.
3. **Deleting the strip's Cancel does not survive.** Two of three designs
   proposed it, handing the job to the toolbar button — which `open-items.md`
   already records as *rendering wrong*, with its symptom still owed. Worse,
   the two predicates are not the same: `PrimaryActionButton` requires
   `hasDataset && !isLoadingDataset`, and inside the load bracket
   `AppState.runCurrentAnalysis` runs a whole-cube pass with the toolbar
   hidden. **The strip's Cancel is the only visible control that stops it.**
   Answering "your cancel button looks wrong" by deleting it and pointing at a
   different one already on the defect list is not an answer.

## Where all three designs were wrong together

- **All three cited the wrong `status.md` row.** They cited the wrap defect and
  the 2026-09-04 metrics row; none cited the row that actually records the
  percent slot as a delivered remediation from 2026-09-07, nine days old. Both
  rows are corrected here.
- **All three misread the test situation in the brief's favour and checked
  anyway** — there are zero `accessibilityIdentifier` references in
  `mac4DSTEMTests/` and no UI-test target, so no identifier rename breaks a
  test. Credit for verifying rather than accepting.
- **Two of three misread `decisions.md`'s "busy means one plain Cancel"** as an
  app-wide census of Cancel controls. It is a sentence about what the *toolbar
  item* becomes when busy. The status bar's Cancel existed on that date and the
  entry did not remove it.

## The constant, re-measured

`operationMetricsWidth` (190) → **`operationReadoutWidth` (116)**. The widest
string `OperationMetricsFormat.line` can now produce is `5999:59 · ETA 5999:59`
at **113.59 pt** in the strip's own font — a hundred hours in both fields. The
test's sweep was *widened* to match, not narrowed: with the rate gone the two
durations are what grows the string, and narrowing the bound to fit a smaller
constant would be fitting the gate to the answer. One candidate value, 100 pt,
was proposed and rejected on that measurement — it truncates past about two
hours, and the mutation confirms the test catches it.

## A readout is not an event

Not in the bar, but in the log above it and the same complaint. Every click on
the scan image wrote `Pattern x 154, y 152 from <filename>` through
`statusText.didSet`; the consecutive-repeat rule never fired because the
coordinates differ every time; a 330 × 330 scan offers **108 900** of them
against a **300-line** capacity. Cursor movement was evicting the run's real
events from the record kept to explain them. `ActivityLog` gained a one-shot
suppression and the rule that says why, and the filename went with it.

## The progress percentage was in the status string all along

The owner drove the new bar and asked whether it should look like this. It
read `Detecting Bragg disks… 11 %` — so the percentage was still on screen,
one layer down, and the progress bar beside it was drawing the same fact.

**Why every operation was appending a percentage to its own status line:** to
be filtered out of the log. `ActivityLog.record` dropped any message ending in
`%`, so "… 42 %" was how progress stayed out of the event record. Filtering
progress by what a string happens to end with is a rule the next status message
can break without anyone noticing — **and it was already broken**.
`SystemMonitor.scanProgressStatus` returns "Computing virtual detector…
100,980 / 108,900 patterns · 1.54 GB of 1.66 GB", which ends in "GB". The
owner's first screenshot shows a whole-cube pass writing one of those per tick,
burying the run's real events.

Both are one fix. `AppState.updateCancellableOperation` is the single funnel
every operation's progress passes through, and it now calls `showReadout` — so
progress is kept out of the log **by construction**, not by string shape. Ten
status strings then dropped their percentage, because the bar draws it. The
suffix rule stays as a backstop and is no longer load-bearing.

## A trap paid twice: a stale test bundle fakes a pass AND a surviving mutation

While pinning the above, a new test method was **not discovered by XCTest** —
eight of nine cases ran, the ninth never appeared, and the suite reported
success. An `XCTFail` in its first line never fired. In the same state the
mutation it was written for "survived", which reads exactly like a blind spot
in the test.

It was a stale bundle: `Failed to create a bundle instance representing …`.
After clearing DerivedData the method was discovered and the mutation turned
the suite red on the first try. Recorded in `open-items.md`, because the
signature — `cases: 8 declared: 9` — is only visible if you reconcile the count
**per file**, and because a mutation that survives on an incremental build is
not evidence until it survives on a clean one.

## Gate

Neither Gate D trigger applies: no scientific number moves, and both mechanisms
are proven by reproducing observation — the 9 pt label measured against 10 pt
text, and the `C…` collapse reproduced at 1080 pt.

**UNVERIFIED ON SCREEN**, and one caveat with it: `status.md` records that the
ETA has *never* been seen in this strip, because the demo run is sub-second.
A run long enough for an ETA to appear is what would actually exercise the
reserved slot.
