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
| v2.5.0 | released 2026-09-04, version/build 2.5 / 4 — the first shipped build of the SwiftUI rebuild. Gated on `unit` (457/0/0) + `package-test`, both exit 0; **`run-tests.sh all` was attempted and exited 1** on a pre-existing sidecar defect (`open-items.md`), and the notes say so. Artefact: built from `3c0a3eb`, app notarization `af7cc0f4`, DMG notarization `f4aa1d12`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `d55821a1…4c75`, 6 074 038 bytes. Build 3 (`df80e8e`) is superseded, kept as `mac4DSTEM-2.5-build3-superseded.dmg` | `CHANGELOG.md` |

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
| Saved-session sidecar contents moved to the LEFT sidebar | done 2026-09-04, **unverified on screen** | `Section("Saved session sidecar")` is gone from `WorkspaceInspector`; the sidecar filename, Calibration, BraggVectors, the saved-result rows, Apply Saved Controls and Change…/Ignore… render in `WorkspaceSidebar`'s `Section("Session")`. Info keeps only the unreadable / does-not-fit sections — the explanation half of the split. Builds clean with no warnings and no test names the moved identifiers, which is also the limit of what any gate can say: this is placement, and only the owner's eyes close it. One judgement call to overrule or keep — Remove is now the result row's context menu, not a second visible row per result (`open-items.md`) |
| 5 The owner's full drive | owner | — |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | **457 passed / 0 failed / 0 skipped, exit 0 — 2026-09-04, the v2.5.0 release tree** (63 suites, counted by `Suite.method`; one line chopped mid-name by an interleaved xcodebuild timestamp, reconciled against the source file's 8 methods rather than assumed). Earlier that day, pre-release tree: **457 passed / 0 failed / 1 skipped, exit 0**, `ActivityLog` + warning-fix tree (458 tests), zero Swift warnings from any file this session touched. Full log retained; exit code read on its own line, never through a `tail` pipe; tests counted by METHOD name and reconciled against the expected delta (`open-items.md`, working methods — a chopped log line faked a missing test twice in one day). Same day: 455/0/1, 448/0/1, 451/0/1 |
| `run-tests.sh scientific` | inside `all` above, 2026-09-03. The four reader harnesses (`dm4-robustness-test`, `vendor-reader-test`, `sidecar-error-detail-test`, `load-spec-test`) each exit 0 on the path-leak tree, 2026-09-04 — that change was in `Core/`, so they were owed |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-04, clean tree (so its docs check actually ran). Cold-start set 889, down from 922 at the previous closeout; it dipped to 862 mid-session and the second docs pass put 27 back as verified file:line evidence, after every entry it touched was trimmed to the file's own ≤ 12-line rule. **Weaker than it reads:** its size numbers are `printf` with no return code, and its one docs check is skipped entirely on a dirty tree (`run-tests.sh:179`), which is how every session runs it. It gates the `tools/` classification and the UI-contract greps; it does not gate the doc numbers |
| `tools/package-test/run.sh` | **exit 0 — 2026-09-04.** Clean-builds a hardened Release and audits the artefact: nested signatures, sandbox/read-write/bookmark entitlements, no `get-task-allow`, no Homebrew dylib paths, embedded HDF5 2.1.1 opening a checked-in fixture, and identity/version `2.5 (4)` with the deployment floor — both DERIVED from the project. The floor assertion and its success message were both literal `26.0` and both wrong after the floor moved; the message said "macOS 26 floor" while passing against 14.0 |
| `run-tests.sh all` | **exit 0 — 2026-09-04, post-release tree** (458 passed / 0 failed / 0 skipped, 44 harnesses, `real-data-acceptance` and `package-test` included). It exited 1 on the release tree itself, at `real-data-acceptance`; that defect is diagnosed and closed as a stopgap, with the wider class left open (`open-items.md`). Two recorded traps hit again: the background task's exit code was 0 while the gate's own `GATE_EXIT` line said 1, and the unit count read one short because an xcodebuild timestamp interleaved mid-test-name — reconciled against the source file's method count, never assumed |

## Ship v2.5.0 — the standing plan (owner, 2026-09-04 evening)

**The parking is lifted.** The v2.5.0 release was parked 2026-09-03 until the
UI rework was right; the rework landed 2026-09-04 and the owner has now driven
it. The next session's job is to get v2.5.0 out — the GitHub download page
still offers v1.0.0, and the owner's priority is replacing it, not perfecting
it. The name is **v2.5.0** — not 2.5.1: nothing called 2.5.0 was ever
released, so there is nothing to patch. Every doc must say the same thing.

**The gate: tried full, FAILED, shipped reduced (owner, 2026-09-04 evening).**
The plan chose the cheaper middle path because disk was short. The owner freed
the disk and called for `run-tests.sh all` instead. It ran and **exited 1** at
`real-data-acceptance` on a defect that predates the release (`open-items.md`,
sidecar-read-as-data) — 457/0/0 unit and 42 harnesses green first, but
`package-test` is sequenced after the failure and never ran. The owner's call
on seeing that: ship on the reduced gate as originally planned, with the
defect recorded rather than buried. **So the release notes must say the full
gate did not pass** — not merely that it was skipped. Read every exit code on
its own line, never through a pipe: the background task said 0 while the
gate's own line said 1.

**Five places disagree today and all must read "v2.5.0, released".** Do these
in one commit with the version bump:
1. `CHANGELOG.md:3` — "v2.5.0 — unreleased" → dated; and its body still
   describes the pre-rebuild app, so fold in the 2026-09-04 SwiftUI rebuild.
2. `docs/status.md`, the Releases table above — the v2.5.0 row still says
   "parked", and its cited `df80e8e` DMG is superseded.
3. `docs/releasing.md:12` — the release contract still says parked "until the
   UI rework is complete".
4. `mac4DSTEM.xcodeproj/project.pbxproj` — `MARKETING_VERSION` is already 2.5;
   bump `CURRENT_PROJECT_VERSION` 3 → 4, because build 3 is the superseded
   2026-09-03 artefact in `build/release/`.
5. `docs/open-items.md`, the macOS-floor entry — it said `LSMinimumSystemVersion`
   is 14.0. Rewritten 2026-09-04. **The plan's own correction here was itself
   half wrong** and is left standing as the warning: it said "there is no such
   key anywhere". The key DOES exist — `GENERATE_INFOPLIST_FILE` derives it from
   `MACOSX_DEPLOYMENT_TARGET = 26.0` and `tools/package-test/run.sh:46` asserts
   it reads `26.0`. Stale was the VALUE, not the key.

**Build order, and it is the part that bites** (`docs/releasing.md`):
Developer ID archive → notarize the app → staple → `make-dmg.sh` from the
*stapled* app → **notarize the DMG too**. `make-dmg.sh` signs the image and
does not notarize it; Gatekeeper assesses the thing the user opened. Two
notary submissions, each usually 5–15 min. Credentials verified present
2026-09-04: cert `Developer ID Application: Paul Lobpreis (3B8SMSSAX4)` and
the working `mac4dstem-notary` keychain profile. The owner tests the DMG on a
second account on this Mac.

**Disk: cleared by the owner 2026-09-04.** 11 GB free on both roots, above
`run-tests.sh`'s 8 GB preflight floor — which is what let the owner upgrade
the gate below. Do not delete outside `free-space.sh`'s two guarded roots on
an agent's own judgement.

**Deferred by the owner, explicitly not v2.5.0 blockers:** the macOS floor
(below) and the toolbar Cancel button's appearance, both in `open-items.md`.
The third, moving the sidecar contents into the left sidebar, the owner
un-deferred on release night and it is DONE in code — unverified on screen,
and no gate can see it (`open-items.md`).

**The macOS floor — DECIDED: it comes down (owner, 2026-09-04).** Not "if".
The app is capped at macOS 26 by `MACOSX_DEPLOYMENT_TARGET = 26.0` *and*
`Package.swift: platforms: [.macOS(.v26)]`. This is an **enforced floor, not
an untested claim**: macOS refuses to launch below it, so softening the
wording changes nothing — only lowering the number does. Cheap to find out:
there are **zero `@available(macOS …)` annotations in the entire codebase**,
so nothing is version-gated and lowering the target either compiles or names
the offending API at build time. Expect the Liquid Glass / within-window
material work (`decisions.md`, `architecture.md`) to be where it bites.
**Sequencing, and it is the owner's call, not an agent's:** every green gate
on record was gated at 26, so lowering the floor re-opens the whole gate
surface. Do NOT do it on release night. Ship v2.5.0 at 26, then lower the
floor as its own session with its own gate — that lands as v2.6.0 (or 2.5.1
if nothing else rides along), and it needs a real older machine or VM, which
`open-items.md` records the project does not have.

**Not forgotten, owner will handle: the public face still shows v1.0.0.** The
README, the project website and the GitHub release page all describe and link
v1.0.0. The front-page screenshot shows the retired AppKit window, which no
longer exists in the codebase. None of this blocks cutting the release, but
v2.5.0 is not *delivered* until the thing a stranger lands on says so. Owner
said they will take care of it; this line exists so it cannot be dropped.

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
   Of the three things that were **unverified on screen**, the owner closed two
   by driving a full-scan Bragg detection on `sim_Au_data_all_binned.h5` on
   2026-09-04: the status bar's elapsed / throughput / ETA ticked live
   (`7 s · 88.0 positions/s · ETA 1:29 · 287 MB app · 525 MB cube ·
   streaming`) and the output log kept updating after `ActivityLog` took it
   off `AppState`. **Two remain**: a cropped save → quit → reopen (S1's crop
   restore), and the sidecar contents in their new home in the left sidebar —
   load a dataset that has a sidecar, check the rows read correctly at the
   sidebar's width, and right-click a saved result to find Remove. The
   dividers stay unverifiable by any gate.
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

**The aggregate gate is owed, and now has a named blocker.** `run-tests.sh all`
ran on the release tree 2026-09-04 and exited 1 at `real-data-acceptance`; the
defect behind it is real, pre-existing and undiagnosed (`open-items.md`). Disk
is no longer the obstacle — the owner freed it and the preflight passes. Until
that defect is diagnosed under Gate D, no aggregate exit 0 can be quoted.

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
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format).
