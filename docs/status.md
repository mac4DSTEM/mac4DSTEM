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
| v2.5.1 | released 2026-09-04, version/build 2.5.1 / 5 — macOS floor down to 14 and the sidecar-reader fix. Artefact built from `a9a0437`; app notarization `fb693c50`, DMG `f3d05e79`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `30282206…31af`, 6 157 051 bytes; the app inside the image declares `LSMinimumSystemVersion 14.0`, verified by mounting it. First release able to claim `run-tests.sh all` exit 0 (458/0/0, 44 harnesses). v2.5.0's artefact cannot launch below macOS 26, so this is the build that reaches older systems | `CHANGELOG.md` |
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
| DM4 Gatan STEM-SI import | fixed 2026-09-05; awaiting owner re-drive and review 2026-09-06 | Empty positional labels resolve by physical sibling index; calibration domains distinguish detector-fastest from scan-fastest storage. `Si-SiGe.dm4` now discovers as scan 77×17, detector 448×480, uint16, with 2 nm / 0.06208537 1/nm calibration. The focused robustness and load-spec harnesses pass; Debug build succeeds. Gate B's remaining performance finding is live in `open-items.md` |
| UI rebuilt in SwiftUI, and the old one retired | done 2026-09-04 | `UI/` IS the SwiftUI rebuild: the AppKit-hosted window's 32 files are deleted, the `UI2/` folder and the `UI2` type prefix are both gone, and no flag selects a UI. Contract in `architecture.md` "The UI contract", three of its rules pinned by an `inventory` grep (`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`/`import AppKit`, mutation-tested both ways). Shape, drive calls and the retirement in `decisions.md` (2026-09-04). The launch crash is fixed (`PaneSplit`) and gated; its mechanism was refuted here and then DEMONSTRATED later the same day by the status-bar revert (`open-items.md`, the constraint-loop entry), which made the two probes named at the time moot (`open-items.md`). Cost of the retirement: 27 tests deleted, every one pinning the AppKit column shell; six repointed. Five renames were not bare strips (`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`, `PatternFitOverlay`) — reasons in `architecture.md`. The status bar's elapsed/throughput/ETA was added and REVERTED the same day: its per-second `.fixedSize()` text crashed the app on a real dataset and, in doing so, demonstrated the constraint-loop mechanism that had been refuted-but-unestablished (`open-items.md`) |
| Status bar: elapsed / throughput / ETA, rebuilt in a reserved slot | done 2026-09-04, **unverified on screen** | `LayoutPolicy.operationMetricsWidth` (190 pt, constant) is the slot; the text truncates inside it and never resizes it. `OperationMetricsFormat.line` composes the line for both surfaces. `StatusBarMetricsTests` (4 tests, each broken first) measures the widest line the formatter can produce — an hour elapsed, an hour of ETA, 999.9 units/s — against that constant in the same font. The sibling `status.footer.facts` lost its `.fixedSize()`: it was breaking the same rule already, on every progress update, before the metrics line existed (predicted, not observed). Only a real dataset exercises the one-second tick |
| The output log moved off `AppState` | done 2026-09-04, **unverified on screen** | `ActivityLog` (`App/ActivityLog.swift`) owns the strip's buffer: the filter, the no-repeat rule, the 300-line cap and the stamp, on an injected clock. `AppState` 495 → 494 stored properties. `@Observable` on it is load-bearing — with the annotation removed, five of its six tests still pass and the strip silently stops updating, which is why `ActivityLogTests` asserts the chain with `withObservationTracking` (the repo's first). Toggling the log from the status bar is the five-second check |
| Saved-session sidecar contents moved to the LEFT sidebar | done 2026-09-04, **unverified on screen** | `Section("Saved session sidecar")` is gone from `WorkspaceInspector`; the sidecar filename, Calibration, BraggVectors, the saved-result rows, Apply Saved Controls and Change…/Ignore… render in `WorkspaceSidebar`'s `Section("Session")`. Info keeps only the unreadable / does-not-fit sections — the explanation half of the split. Builds clean with no warnings and no test names the moved identifiers, which is also the limit of what any gate can say: this is placement, and only the owner's eyes close it. One judgement call to overrule or keep — Remove is now the result row's context menu, not a second visible row per result (`open-items.md`) |
| 5 The owner's full drive | owner | — |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| DM4 focused + app build | **DM4 robustness exit 0 (7 checks), load-spec exit 0, Debug build exit 0 — 2026-09-05**; real-file probe: `[77,17,448,480]`, uint16, 2 nm / 0.06208537 1/nm. Logs `/private/tmp/mac4dstem-dm4-focused-final2-20260905.log`, `/private/tmp/mac4dstem-dm4-load-spec-postfix-20260905.log`, `/private/tmp/mac4dstem-dm4-build-20260905.log`. Full unit/scientific reruns unavailable: free-space preflight reports 4 GB against the 8 GB floor. |
| `run-tests.sh unit` | **463 passed / 0 failed / 1 skipped, exit 0 — 2026-09-05**, full log retained at `/private/tmp/mac4dstem-discovery-unit-20260905.log`; this run covers the committed reader change, before the current manual-scale UI change. The closeout rerun was refused by the free-space preflight (**exit 69**, 4 GB available versus its 8 GB floor); `/private/tmp/mac4dstem-manual-scale-closeout-unit-20260905.log`. |
| `manual-scale focused tests` | **2 passed / 0 failed, exit 0 — 2026-09-05**, covering the manual setter/provenance path and ready-row editor policy; `/private/tmp/mac4dstem-manual-scale-focused-final2-20260905.log`. The pre-fix test failed to compile as expected because the policy was absent. |
| `run-tests.sh scientific` | **43 harnesses, exit 0 — 2026-09-05**, using `PYTHON=$HOME/miniconda3/envs/py4dstem/bin/python`; includes `datacube-discovery-test`. Full log retained at `/private/tmp/mac4dstem-discovery-scientific-py4dstem-20260905.log`. |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-05, dirty-tree inventory; tool classification and UI-contract checks passed. Its clean-tree documentation check was skipped by design because this work remains uncommitted. |
| `tools/package-test/run.sh` | **exit 0 — 2026-09-04.** Clean-builds a hardened Release and audits the artefact: nested signatures, sandbox/read-write/bookmark entitlements, no `get-task-allow`, no Homebrew dylib paths, embedded HDF5 2.1.1 opening a checked-in fixture, and identity/version `2.5 (4)` with the deployment floor — both DERIVED from the project. The floor assertion and its success message were both literal `26.0` and both wrong after the floor moved; the message said "macOS 26 floor" while passing against 14.0 |
| `run-tests.sh all` | **exit 0 — 2026-09-04, post-release tree** (458 passed / 0 failed / 0 skipped, 44 harnesses, `real-data-acceptance` and `package-test` included). The release-tree attempt exited 1 at `real-data-acceptance`; that sidecar instance was diagnosed and closed as a stopgap then, and the wider discovery class was subsequently closed on 2026-09-05. Two recorded traps hit again: the background task's exit code was 0 while the gate's own `GATE_EXIT` line said 1, and the unit count read one short because an xcodebuild timestamp interleaved mid-test-name — reconciled against the source file's method count, never assumed |

## The v2.5.0 / v2.5.1 release night

Both shipped 2026-09-04; the plan, its two self-corrections and the artefact
provenance are
[`docs/archive/v2/release-2026-09-04.md`](archive/v2/release-2026-09-04.md).
The live facts are the Releases table above and `CHANGELOG.md`.

## Handoff (rewritten 2026-09-05, after the v2.5.0 / v2.5.1 release night and reader gate)

v2.5.1 is published and verified from its own download link. Both repos are
pushed; the site says macOS 14+ and serves the build that can honour it. Push
state is not recorded here — it went stale twice in two commits; ask git.

**Read this first: item 1 is the owner's and `/pickup` cannot take it.** An
agent should say so and start at item 2.

1. **Your drive. (OWNER ONLY.)** Nothing beyond Prepare, Imaging and Strain &
   ACOM has been looked at since the AppKit retirement, and five sessions
   running have found defects by driving that every gate was green through.
   Bugs enter via `/diagnose`. Worth going at first: Phase's stages, the load
   configurator's crop drags, the Results comparison row, the colorbar popover,
   and every divider — the pane split is hand-built and **no gate can see a
   column's width** (falsified, `open-items.md`). Still unverified on screen:
   a cropped save → quit → reopen (S1's crop restore), and **right-clicking a
   saved result in the sidebar's Session section to find Remove** — the rows
   themselves the owner drove and approved, the context menu nobody has opened.
2. **Manual Q and R pixel scale cannot be corrected once entered**
   (`open-items.md`). The UI fix is landed in both Prepare and ExportSheet;
   owner drive remains for the ready/manual editor visibility and editability.
3. **The four open UI-review findings** and **`PaneSplit` residuals**
   (`open-items.md`).
4. **Then the rest of the science lane, one item at a time** — origin-fit guard
   (Gate B), the ACOM bundle's origin-provenance snapshot, the selected-area
   mask fixture, bullseye disk detection (Gate D), the CIF id collision,
   Q-calibration scale, ACOM coverage. A landed number change cuts v2.6.0.
   **None of these is unattended work.**

**macOS 14–25 is compile-verified and has never been executed.** The floor is
14 in the build and published as such; every machine here is 26. A VM would
close it and needs ~40 GB. Until then the first report from an older system is
the real test — both README and site ask for the macOS version.

**The rule bought the hard way** (`open-items.md`, the constraint-loop entry):
nothing inside a split column may repeatedly change its own minimum size.
`.fixedSize()` on text whose string changes is the easiest way to do it by
accident, and it only shows on a dataset big enough for an operation to tick.
All 12 bare `.fixedSize()` sites in `UI/` are audited and contained.

**Two traps that bit again on release night, both already documented.** A
BACKGROUND TASK reported exit 0 while the gate's own `GATE_EXIT` line said 1 —
read the gate's line, never the wrapper's. And the unit count read one short
twice because an xcodebuild timestamp interleaved mid-test-name; reconcile
against the suite's method count in source, never assume a test vanished.

**Driving, and its two limits.** `open -n <Debug app> --args --demo-fixture`,
`screencapture -x -o -l <window id>` (per-window needs no consent). The app's
defaults live in its sandbox container and TCC blocks writing them; synthetic
keystrokes only land while the window is frontmost. Fastest loop: the owner
drives and pastes the result.

## Owed to the owner

- **Drive the rebuilt app** (above) — two things unverified on screen.
- The §10g decisions and plan §8 (sidecar wire format).
