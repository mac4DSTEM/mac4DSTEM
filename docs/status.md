# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from retained, dated runs. The per-increment log of
2026-09-02/03 is `docs/archive/v2/v2.5-log-2026-09-03.md`.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | tagged 2026-09-02, never built; superseded, the tag stays as the pre-consolidation anchor | `CHANGELOG.md` |
| v2.5.0 | parked (owner, 2026-09-03 late): no release or tag thinking until the UI rework is complete and right. The `df80e8e` build (notarized, `build/release/mac4DSTEM-2.5.dmg`) is superseded, not released | `CHANGELOG.md` |

## Where the UI stands

The v2.5 consolidation train and the presentation pass over the AppKit
window are finished and archived, with the window itself:
[`docs/archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md).
What that train left behind is the shape the app has now — `DSTEMCore` and
`DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`,
`ProductWorkflow.readiness`, `ACOMSession`, five workspace sidebars.

| Step | State | What it left behind |
|---|---|---|
| UI rebuilt in SwiftUI, and the old one retired | done 2026-09-04 | `UI/` IS the SwiftUI rebuild: the AppKit-hosted window's 32 files are deleted, the `UI2/` folder and the `UI2` type prefix are both gone, and no flag selects a UI. Contract in `architecture.md` "The UI contract", three of its rules pinned by an `inventory` grep (`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`/`import AppKit`, mutation-tested both ways). Shape, drive calls and the retirement in `decisions.md` (2026-09-04). The launch crash is fixed (`PaneSplit`) and gated; its mechanism was refuted here and then DEMONSTRATED later the same day by the status-bar revert (`open-items.md`, the constraint-loop entry), which made the two probes named at the time moot (`open-items.md`). Cost of the retirement: 27 tests deleted, every one pinning the AppKit column shell; six repointed. Five renames were not bare strips (`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`, `PatternFitOverlay`) — reasons in `architecture.md`. The status bar's elapsed/throughput/ETA was added and REVERTED the same day: its per-second `.fixedSize()` text crashed the app on a real dataset and, in doing so, demonstrated the constraint-loop mechanism that had been refuted-but-unestablished (`open-items.md`) |
| Status bar: elapsed / throughput / ETA, rebuilt in a reserved slot | done 2026-09-04, **unverified on screen** | `LayoutPolicy.operationMetricsWidth` (190 pt, constant) is the slot; the text truncates inside it and never resizes it. `OperationMetricsFormat.line` composes the line for both surfaces. `StatusBarMetricsTests` (4 tests, each broken first) measures the widest line the formatter can produce — an hour elapsed, an hour of ETA, 999.9 units/s — against that constant in the same font. The sibling `status.footer.facts` lost its `.fixedSize()`: it was breaking the same rule already, on every progress update, before the metrics line existed (predicted, not observed). Only a real dataset exercises the one-second tick |
| The output log moved off `AppState` | done 2026-09-04, **unverified on screen** | `ActivityLog` (`App/ActivityLog.swift`) owns the strip's buffer: the filter, the no-repeat rule, the 300-line cap and the stamp, on an injected clock. `AppState` 495 → 494 stored properties. `@Observable` on it is load-bearing — with the annotation removed, five of its six tests still pass and the strip silently stops updating, which is why `ActivityLogTests` asserts the chain with `withObservationTracking` (the repo's first). Toggling the log from the status bar is the five-second check |
| 5 The owner's full drive | owner | — |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | **457 passed / 0 failed / 1 skipped, exit 0 — 2026-09-04**, `ActivityLog` + warning-fix tree (458 tests), zero Swift warnings from any file this session touched. Full log retained; exit code read on its own line, never through a `tail` pipe; tests counted by METHOD name and reconciled against the expected delta (`open-items.md`, working methods — a chopped log line faked a missing test twice in one day). Same day: 455/0/1, 448/0/1, 451/0/1 |
| `run-tests.sh scientific` | inside `all` above, 2026-09-03. The four reader harnesses (`dm4-robustness-test`, `vendor-reader-test`, `sidecar-error-detail-test`, `load-spec-test`) each exit 0 on the path-leak tree, 2026-09-04 — that change was in `Core/`, so they were owed |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-04, clean tree (so its docs check actually ran). Cold-start set 889, down from 922 at the previous closeout; it dipped to 862 mid-session and the second docs pass put 27 back as verified file:line evidence, after every entry it touched was trimmed to the file's own ≤ 12-line rule. **Weaker than it reads:** its size numbers are `printf` with no return code, and its one docs check is skipped entirely on a dirty tree (`run-tests.sh:179`), which is how every session runs it. It gates the `tools/` classification and the UI-contract greps; it does not gate the doc numbers |
| `run-tests.sh all` | 2026-09-03, e2284f1 tree: unit 467/0/3 and 43 harnesses green including `real-data-acceptance`; exit 1 at `package-test`, whose literal `2.0` / `1` version assertion the 2.5 / 3 bump turned red — the audit now derives both from the project and passed on the same tree (log retained). Trap: the background task's exit code was 0; the gate's own EXIT line said 1 |

## Handoff (rewritten 2026-09-04, end of the unattended docs/hygiene run)

The UI is rebuilt in SwiftUI, the AppKit window is deleted, and the app runs a
full disk detection on the 1 GB WS2 cube. Push state is not recorded here — it
went stale twice in two commits; ask git.

**Read this first: the top item is the owner's, and `/pickup` cannot take it.**
Item 1 needs a person at the keyboard. An agent picking up should say so and
start at item 2, not invent a way to do item 1.

1. **Your drive. (OWNER ONLY.)** Nothing beyond Prepare, Imaging and Strain &
   ACOM has been looked at since the retirement, and four sessions running have
   found defects by driving that every gate was green through. Bugs enter via
   `/diagnose`. Worth going at first: Phase's stages, the load configurator's
   crop drags, the Results comparison row, the colorbar popover, and every
   divider — the pane split is hand-built and **no gate can see a column's
   width** (a unit-level one was tried and falsified, `open-items.md`).
   Three things are **unverified on screen** and only a drive closes them: the
   status bar's elapsed / throughput / ETA (only a real dataset ticks it), the
   output log after `ActivityLog` took it off `AppState`, and a cropped save →
   quit → reopen (S1's crop restore).
2. **Manual Q and R pixel scale cannot be corrected once entered**
   (`open-items.md`). Small, owner-hit; a wrong R scale silently rescales every
   real-space axis, scale bar and export. Its recorded mechanism is imprecise
   for `.qScale` — the code names `.rScale` as the one with no measurement
   path — so check that before fixing.
3. **The four open UI-review findings** (`open-items.md`, "UI review"): the
   pattern min/max rows are not the current position's pattern in Mean/Max/ROI
   mode; the A/B/A−B comparison has no scale; the cursor prints a raw Float;
   staleness has two verdicts across three surfaces.
4. **`PaneSplit` residuals**: the pane header is ~420 pt of `.fixedSize()`
   controls and a pane can be narrower — it clips rather than overprints, but
   the header still needs to compress; and the image floor lapses below 2×
   itself. The zoom badge (the one armed `.fixedSize()` site) belongs with it.
5. **Then the science lane, one item at a time** — the **origin-fit guard
   leads** (Gate B; `open-items.md` "Origin-fit gate" (a)), then the ACOM
   bundle's origin-provenance snapshot, the selected-area mask fixture,
   bullseye disk detection (Gate D), the CIF id collision, Q-calibration scale,
   ACOM coverage. A landed number change cuts v2.6.0. **None of these is
   unattended work**: each needs Gate D or Gate B with an independent refuter
   and the owner's judgement on what the number should be.

**Two gates are owed and one is blocked.** `run-tests.sh all` has not run since
2026-09-03 (`e2284f1`, exit 1 at `package-test`, since fixed on that tree). The
run itself is ~12 minutes and needs nothing the machine lacks except disk — the
preflight wants 8 GB on both `$ROOT` and `$TMPDIR`, and freeing it means
deleting outside the two roots `free-space.sh` guards, which is the owner's
call. `run-tests.sh scientific` has not run as a whole since 2026-09-03 either;
the four reader harnesses ran green on 2026-09-04.

**The rule bought the hard way** (`open-items.md`, the constraint-loop entry):
nothing inside a split column may repeatedly change its own minimum size.
`.fixedSize()` on text whose string changes is the easiest way to do it by
accident, and it only shows on a dataset big enough for an operation to tick.
All 12 bare `.fixedSize()` sites in `UI/` are now **audited**: one armed (the
zoom badge), three that change once per product, eight literals — and
`PaneSplit` terminates each pane's minimum, so none of them reaches a split.

**Driving, and its two limits.** `open -n <Debug app> --args --demo-fixture`,
`screencapture -x -o -l <window id>` (per-window needs no consent). The app's
defaults live in its sandbox container and TCC blocks writing them, so a
remembered tab cannot be preset; and synthetic keystrokes only land while the
window is frontmost. Fastest loop found: the owner drives and pastes the crash
report — that is how the constraint-loop mechanism was established.

## Owed to the owner

- **Drive the rebuilt app** (above) — three things are unverified on screen and
  a fourth, the front-page screenshot, still shows v1.0.0's window.
- **The disk decision** that unblocks `run-tests.sh all`.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format).
