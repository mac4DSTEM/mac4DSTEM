# CLAUDE.md — fresh-eyes read (from code only)

mac4DSTEM is a sandboxed, native macOS SwiftUI/Metal app for interactive
4D-STEM (scanning transmission electron microscopy) analysis, Apple
Silicon-only (`Core/ML/LearnedDiskDetector.swift`'s `#if !arch(arm64)
#error` guard). Its algorithms port py4DSTEM, validated against a pinned
upstream checkout (`tools/lib/fetch-py4dstem.sh` clones it into gitignored
`References/`); GPL-3.0-or-later because of that lineage (`NOTICE`).
`CITATION.cff` names version `3.0.0`, released 2026-09-11. Bundle id
`com.mac4dstem.mac4DSTEM`, macOS 14+ (`project.pbxproj`, `Package.swift`).
Sandbox entitlements grant only `app-sandbox`, user-selected file
read/write, and scoped bookmarks (`mac4DSTEM.entitlements`) — dataset
access must go through security-scoped bookmarks, not raw paths.

## Hard rules the code (not prose) enforces

- **Core/ and Session/ may not reach into App/, UI/ or Support/, and Core/
  may not reach into Session/.** `Package.swift` builds them as two
  standalone SwiftPM targets (`DSTEMCore`, `DSTEMSession(deps: DSTEMCore)`)
  specifically "so that `swift build` fails the moment" that breaks
  (`Package.swift` comment; run via `tools/run-tests.sh core`). Confirmed:
  zero `import SwiftUI`/`AppKit` anywhere under `Core/` or `Session/`.
- **UI/ is SwiftUI only.** The `inventory` gate in `tools/run-tests.sh`
  greps `UI/*.swift` and fails on `import AppKit` or on `HSplitView` /
  `VSplitView` / `NSSplitView` / `NSSplitViewController`. `ContentView.swift`
  states the same rule itself: "UI reads and drives the shared `App/`,
  `Session/` and `Core/` logic, and nothing else."
- **Presentation-contract grep gates** (same `inventory` function): no
  custom `.bar` background/opacity wash in UI/ chrome outside
  `ImagePanes`/`PaneOverlays`/`LoadConfigurator`/`MetalImageView`/
  `HistogramView`; no fixed numeric `.frame(...)` outside those +
  `LayoutPolicy.swift`'s constants (panes/overlays/plots exempt). A nearby
  comment names symbols (`FormPolicy`/`WindowPolicy`/`FormControls.swift`)
  that don't exist in the tree — trust the `LayoutPolicy\.` grep, not that
  comment.
- **Metal parameter structs must stay byte-identical to their `.metal`
  twin** — stated in `MetalEngine.swift` ("PARAM STRUCT CONTRACT... 4-byte
  fields") and echoed by a `// MUST match <Struct>` comment above the struct
  in six of eight shaders (the `ACOMMatching.metal`/`ACOMMetalParams` pair
  is the unlabelled exception to the same convention).
- **Ported algorithms carry an inline `DEVIATION` comment** wherever they
  depart from py4DSTEM, usually dated, citing the upstream file/line (33
  occurrences under `Core/`, one inside a shader — `OriginMeasure.metal`).
  `Session/` has none; it holds no science.
- **Every `tools/*/run.sh` sources `tools/lib/sources.manifest`** (a
  dependency-closed, grouped `Core/` source list) or says in one comment
  line why not, or `inventory` fails; a new `Core/Data` file must be added
  to the right group there or harnesses silently miss it — the manifest's
  own header names the 2026-08-17 breakage this prevents.
- **`AppState.swift` (5,461 lines) and `Support/ResultExport.swift` (1,939
  lines) are size-tracked against the previous commit** by `inventory`.
  Several comments (`Session/SessionGates.swift`,
  `App/WorkspaceNavigation.swift`) describe moving code out of these two
  files "to pay down the AppState + ResultExport budget."
- **Every `tools/` subdirectory must be classified** into one of
  `run-tests.sh`'s arrays (`scientific`/`diagnostic`/`owner_only`/
  `retired`/`support`), or `inventory` reports it `UNCLASSIFIED` and fails.
  Redistributed dylibs must be named + SHA-256-matched in `NOTICE` with no
  absolute load-command paths, and every file inside a bundled Xcode folder
  reference (`Models/DiskDetector`, `Licenses`) must be tracked in git —
  both enforced by the same gate.
- **"May I?" questions get one gated answer, asked everywhere.**
  `Session/SessionGates.swift`'s functions return `String?` (a reason, nil
  = permitted) rather than logging an error and continuing — its header
  names the defect this fixes: one policy question, answered two different
  ways at two call sites.
- **One `AppState` per window**, created below `WindowGroup`, not on `App`
  — `mac4DSTEMApp.swift`: prevents a second window from replacing the
  first window's reader/calibration/cancellation token/results. libhdf5 is
  process-wide and not thread-safe (a plain global, per the same file), so
  only one HDF5-backed load may be in flight.
- **GPU dispatch is synchronous/blocking** (`MetalEngine` calls
  `commit()`+`waitUntilCompleted()`); callers wrap it in a background
  `Task`, never call it from the default-MainActor context directly
  (`VirtualDetector.swift` says so explicitly). `"UNVERIFIED ON SCREEN"` is
  a real comment tag for code not yet driven in the running app
  (`mac4DSTEMApp.swift:35` is one live instance) — a change is either
  observed working or marked as not.

## Build / test

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build
tools/run-tests.sh unit          # xcodebuild test -only-testing:mac4DSTEMTests (XCTest, 65 files)
tools/run-tests.sh scientific    # ~50 standalone tools/*-test harnesses; py4DSTEM parity where applicable
tools/run-tests.sh core          # swift build: DSTEMCore + DSTEMSession as standalone packages
tools/run-tests.sh inventory     # the repo's own review — the gates above
tools/run-tests.sh benchmark     # tools/performance-baseline, non-gating
tools/run-tests.sh campaign|all  # supersets; `all` also runs real-data-acceptance + package-test
tools/free-space.sh [--clear]    # exit-69 remedy: unit/scientific/benchmark need 4 GB free, all/campaign need 8
```

`.github/workflows/ci.yml` runs `unit`, `scientific`, `inventory`, and
`core` on `macos-26` for every push/PR; `real-data-acceptance`,
`package-test`, `benchmark`, and several `tools/` diagnostics are excluded
there because they need gitignored multi-GB data or a specific machine,
per that file's own comments.
