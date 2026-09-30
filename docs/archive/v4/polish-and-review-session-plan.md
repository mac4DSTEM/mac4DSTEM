# Full polish and code-review session — plan and brief for an external agent (registered 2026-09-30)

Owner's request (2026-09-30): after the S14 Gate D and the drive-proposal polish, the next full session is a whole-app polish
and code review run by an **external agent** (a coding agent other than the one that wrote most of this code), with this file
as its complete brief. It is written to be read cold. This file is the plan AND the log: append one line per finished item.

## 0. Why an external agent

Most of the code and every review so far came from one model family. Independent refuters paid for themselves every night
(2026-09-30: four real defects caught behind green suites). A reviewer from outside that family is the strongest refuter left.

**Part A in the cloud (owner, 2026-09-30; ADR 049 makes this review the last intake before v4.1):** part A is read-only and
may run in a cloud session on the pushed repo. Such a session cannot build, run a gate or drive the app, and has none of
`References/`: it returns the findings table in its final message (no branch, no PR), and the fixes are made locally.
**Two passes (owner, 2026-09-30 night, ADR 050's plan):** the first pass now, on the pushed repo, **excluding the four areas the
v4.1 lanes rewrite** — `Core/Analysis/Parallax*.swift` and `*Ptychography*.swift` with `UI/ReconstructionSettings.swift`
and `App/AppState+PhaseContrast.swift` (lane R); `Training/`, `App/AppState+Training.swift`, `UI/DetectorTrainingViews.swift`
(lane T); `UI/ExportSheet.swift` and the export path of `Support/ResultExport.swift` (lane X); `UI/LoadConfigurator.swift`
and the residency code in `App/AppState+Open.swift` (lane K). A second, short pass before the release candidate covers the
diff since the first, i.e. those four pieces once finished.
Kickoff (first pass): "Read docs/archive/v4/polish-and-review-session-plan.md and do part A only (read-only, no code changes,
no branch, no PR). Skip the four excluded areas named under 'Two passes'. Output one findings table: file:line, severity,
the observation that shows it, the proposed fix, whether it can move a scientific number."

## 1. Orientation (read in this order, ~30 min)

1. `CLAUDE.md` — the hard rules. They bind you: `main` only, never push (the owner pushes), Frozen Shell files change only
   against a picture the owner accepted, Gate D before any change that can move a scientific number, break every new test
   before trusting it, never widen a gate that fails silently, no claim a reader cannot reproduce.
2. `docs/status.md`, `docs/architecture.md` (layering: `Core/` computes, `Session/` holds state, `UI/` describes, `AppState` is
   the single source of truth), `docs/open-items.md`, `ROADMAP.md`, `docs/decisions.md`.
3. Build and gates: `xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build`;
   `tools/run-tests.sh unit | inventory | core | scientific`. The last reconciled unit count is in `docs/status.md` § Last gates.
   Machine: the owner's new Mac (2026-09-30). The old 8 GB Mac's rules (`-jobs 2`, one build at a time, the disk floor) are
   re-measured on it, not assumed; never full-read a file bigger than RAM; delete `Logs/Test/*.xcresult` after reading.
4. The app: 179 Swift files, ~69 k lines; largest `Core/Data/BraggVectorEMDWriter.swift` (2 935), `Core/Crystal/
   PhaseVectorMatching.swift` (1 698), `Support/ResultExport.swift` (1 614), `App/AppState.swift` (1 457), `UI/MapSettings.swift`
   (1 409). Six workspaces (ADR 046): Prepare · Imaging · Bragg Disks · Crystal Maps · Reconstruction · Results.

## 2. Scope

**A. Code review (report first, change second).** Per module (`Core/Data`, `Core/Analysis`, `Core/Crystal`, `Core/ML`, `Session/`,
`App/`, `UI/`, `Support/`, `tools/`): correctness bugs, concurrency (MainActor/nonisolated seams, HDF5 under one lock), error
paths that fail silently, dead code (the owner's lean-app directive: delete retired scope in the session that retires it),
duplicated logic, `DEVIATION` notes missing where a py4DSTEM port deviates, tests that cannot fail (mutation-test a sample).
Output: `docs/archive/v4/review-<date>-findings.md`, one row per finding: file:line, severity (defect / risk / cleanup), the
observation that shows it, the proposed fix, whether it can move a scientific number (then it is Gate D, not a cleanup).
**B. Polish (room by room, driven on screen).** Inputs, all recorded with proposals: open-items "Drive 2026-09-30 night"
(β″ twins in the Matrix picker, no way back from Show Objects, a Re-measure after the first origin fit, "Saved with the
dataset" wording, "Phase map (0 candidates)" on a fresh cube, Lineage order), the drive-2 findings (annulus centre handle
undraggable at inner radius 0, "Not carried into this view" only on the Info tab, a refused calibration listed as loaded,
restored units printing "A^-1", the promote status line dropping the pattern readout, "Valid: all 16384" ungrouped), and the
S4/S5 residuals. The owner's design bar: Xcode anatomy and Pixelmator's tools bar; SwiftUI only; one warning style
(`InspectorWarning`); label left, control right; cost every UI change in rows/pt before building it.
**C. The audit's parked refactors** (open-items "The audit's refactor list"): the ResultExport split and the BraggVector EMD
writer split (each prepared and parked; each needs Gate B support), the >1 000-line harness mains. Row 9 is a DO-NOT (the five
`median` bodies stay separate until a Gate D shows they should agree).

## 3. Rules of engagement

- Findings before fixes: the owner reads the findings file and picks. Cleanups that cannot move a number may proceed; anything
  that can is a Gate D (diagnosis → refuting observation → prediction → experiment → fix → independent refuter → fixture).
- Frozen Shell (`UI/ContentView.swift`, `UI/WorkspaceView.swift`, `UI/WorkspaceInspector.swift`, `UI/LayoutPolicy.swift`,
  `App/WorkspaceNavigation.swift`): propose with a mock picture; change only after the owner accepts it.
- Every drawing change is unverified until driven on a scratch build (pid-pinned, window-only shots; never rebuild under a
  running owner app). Two drivers on one Mac must stagger their windows (2026-09-30 lesson: clicks landed in the other window).
- Commit per finding or per room, gate numbers in the message; update `docs/status.md` and `docs/open-items.md` in the same
  commit; net-negative markdown or say why. No push, no branch.

## 4. Sequence and budget

1. Orientation + code review A (read-only) → findings file, committed. Owner picks.
2. Polish B, one room at a time (Prepare first), each driven.
3. C only with a Gate B reviewer available.
Stop and ask on: a moved scientific number, a Frozen Shell change without an accepted picture, anything outside the repo.

## 5. Kickoff prompt (paste to the external agent)

> You are reviewing and polishing mac4DSTEM, a native macOS 4D-STEM app, in /Users/paullobpreis/GitHub/mac4DSTEM_Organization/
> mac4DSTEM. Read docs/archive/v4/polish-and-review-session-plan.md in full, then CLAUDE.md, and follow them. Start with §4 step 1:
> a read-only code review producing the findings file; do not change code until the owner has picked findings. Never push,
> never branch, never touch the Frozen Shell files without an accepted picture.

## Log

- (the session appends here)
