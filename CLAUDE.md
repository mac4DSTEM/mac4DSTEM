# CLAUDE.md — start here

mac4DSTEM: native macOS (Swift / SwiftUI / Metal) 4D-STEM analysis on Apple Silicon, validated against py4DSTEM at one pinned upstream commit (`tools/lib/fetch-py4dstem.sh` fetches it into the gitignored `References/`).
The latest release is **v4.5.0** (2026-10-05; macOS 27+; v3.0.0 stays for older systems); `main` is v5.0 development and the science kits are imported at exact tags (see below). The suite's rules are in `../CLAUDE.md` ("How we work"); this file adds the repo's own and wins on a conflict, except on the board. Rules only here; status and history elsewhere.

## Read, in this order

1. `docs/status.md` — what is live now. Every session starts here.
2. `ROADMAP.md` — the feature plan.
3. `docs/open-items.md` — live defects and debts only, ≤ 4 lines each.
4. `docs/architecture.md` — layering, ownership, where files go.
5. `docs/decisions.md` — the ADR index; one row per decision (a file in `docs/decisions/` plus a row, only where the design is not obvious).

Skills (procedures to read as documents): `/pickup`, `/diagnose`, `/adversarial-review` (the second-lane review), `/closeout`.

## How a change lands

The suite process (`../CLAUDE.md`): a focused commit on `main`, with tests that fail before and pass after, and one review by a second lane before the commit. Gate B, Gate D, tiers, registrations, stamps and break-every-test-once are retired (2026-10-15); their records are in git history and `../_archive/mac4DSTEM/`. Pushing and tagging are the owner's. `main` only: no feature or worktree branches.

- **Numbers** (D12, Paul 2026-10-19): a number a scientist reads is covered by a regression test with a pinned fixture. Readers, I/O, indices and metadata are tested exact; numerics against the pinned py4DSTEM within a tolerance written per function (`assert_allclose` style: about 1e-7 relative for float64, 1e-5 for float32), never widened to hide a bug. During an app-to-kit switch, bit for bit is a quick check only; if it fails, verify against the Python reference within tolerance and do not block. A moved pinned number gets its own commit with the reason, and a changelog line. Some tests and harnesses still assert exactly; converting them to a written tolerance is a later code change.
- **Diagnose before fixing** a wrong number or a defect whose cause is not established: state the diagnosis and the observation that would refute it, then run the cheap experiment (`/diagnose`).
- Docs are part of done: update `docs/status.md` and `docs/open-items.md` with the code, net negative markdown lines or say why. Write docs and the board row once, at closeout; commit at every green checkpoint, by explicit paths (another session's edits stay theirs).
- **Repos stay light**: the repo holds what builds, tests and explains the app; the rest goes to `../_archive/mac4DSTEM/` (untracked, outside the repo). A path written `../_archive/mac4DSTEM/<repo path>` is an archive citation; `inventory` checks each when the folder is there. `tools/` holds only what the gates, hooks, CI or release run.
- **Suite board**: at closeout update only this repo's row, `lanes/mac4dstem` (`../CLAUDE.md`).

## Hard rules

- **What the app is** (owner, 2026-09-30): pure macOS, simple, reliable, an intuitive UI/UX, scientifically correct. No filler: every control, number and sentence earns its place or goes.
- **Rules serve the app** (owner, 2026-09-29): a rule that would make the app worse is not followed; the commit names the rule and says why, and the rule is changed here.
- Views describe UI only; loading, parsing and compute live in `Core/` (package `DSTEMCore`, no upward imports). `AppState` is the composition root: new stored state names its owner first; `inventory` reports growth of `AppState.swift` + `Support/ResultExport.swift`, and a commit that grows them says why no other home would do.
- **Frozen shell** (owner, 2026-09-22): `UI/ContentView.swift`, `UI/WorkspaceView.swift`, `UI/WorkspaceInspector.swift`, `UI/LayoutPolicy.swift` and `App/WorkspaceNavigation.swift` change only against a picture the owner has accepted (ADR 035); wording that corrects a false claim may change, structure and width may not.
- **Unvalidated stays labelled** (owner, 2026-09-18): phase mapping, and any product that self-reports `validation:"none"`, ships badged unvalidated and is not called validated until it passes on one dataset with truth; `inventory` greps the badge and the key.
- Never widen a gate that fails silently. Open the app periodically: a drive finds defects a green suite cannot. On-screen verification may be claimed only when it drove the app: name the build, what was clicked, what was seen; otherwise say unverified on screen. A drive never writes or clears the owner's clipboard (check a Copy step by `NSPasteboard.changeCount`; the hook refuses `pbcopy`).
- Quote test numbers only from a dated run named by its log, not a path (session logs are gitignored); evidence a reader must open is a committed fixture under `mac4DSTEMTests/Fixtures/`. No claim a reader cannot reproduce: the repo is public.
- A threshold is a property of the dataset and settings it was measured under until measured on every dataset it will touch; never infer a mechanism from a null result.
- Never read a gate's exit code through a pipe: redirect to a log, `echo $?` on its own line; count tests by method name and reconcile against the expected delta. A lost session resumes from its own scratchpad, not from memory.
- Parallel sessions share `/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks/`: while a file `drive` exists a session is driving the app, so start no test run; `mkdir heavy.1` / `heavy.2` is a build slot, removed after.
- Do NOT set `ResidencyAdmission.measuredWorkingSetFraction`: nil by decision (ADR 013).
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the matching `.metal` structs (all 4-byte fields). Port deviations from py4DSTEM get an inline `DEVIATION` note. Don't add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch; use `tools/run-tests.sh unit` for unsigned XCTest work.

## The kits

Science that has a kit equivalent is the kit's, imported at exact tags (`Package.swift` is the truth for versions; the Xcode project and both `Package.resolved` follow). A fix lands in the kit and arrives by a tag bump, gated here; an interim is marked "delete at <kit> <version>". Kit asks go to the coordinator and are listed in `docs/open-items.md`.

- **SpectroKit + FormatoKit** (ADR 064, 067): standalone EDX (fit, quantification) and the file readers with the one HDF5 lock (`HDF5Serial`) and libhdf5 as FormatoKit's frameworks. Bump the two together, never one alone. 4D × spectroscopy stays here (`Core/Spectroscopy/Registration/`, `Session/Spectroscopy*`). The Run configuration is `Develop` so the kits build optimised; keep its name.
- **DiffractoKit**: crystallography, ring and ellipse fit, vector-matched phase mapping, and the ACOM and orientation types and matcher (`ACOMMatcher`, `ACOMScanSelection`, `OrientationResult`). `sources.manifest` links DiffractoOrientation into every group that compiles `OrientationResult.swift` or the ACOM files. What stays here: `ACOMCrystalSymmetry` and `OrientationMap` (`Core/Analysis/OrientationResult.swift`), `OrientationPlan`, the Metal backend `MetalACOMMatcher` and the chunked CPU dispatch `OrientationMatching` (`Core/Crystal/`).
- **CuboKit**: the 4D core (virtual imaging, mean/max, centre of mass, origins, strain, DPC/iDPC, parallax, ptychography and their shared pieces); the app keeps its Float façades and settings (`ParallaxAlignment`, `MatrixDFTCorrelation` carry "delete at CuboKit <version>" notes).
- **ImagoKit**: `ImagoCore.FFT2D` and `ImagoFFT.FFT1D` (ADR 070). `FFT2DArbitraryLengthTests` stay as consumer tests.

## Build / test

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build   # the scheme's Run config, Develop
tools/run-tests.sh unit | scientific | all | inventory | core | campaign   # inventory = the repo's own review; core holds the layering
tools/gate.sh unit|core|scientific|inventory|last        # the same under the machine-wide test-host lock; exits 75 when blocked
git config core.hooksPath tools/hooks                   # once per clone: pre-push runs inventory + an app build
```
