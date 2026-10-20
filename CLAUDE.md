# CLAUDE.md — start here

mac4DSTEM: native macOS (Swift / SwiftUI / Metal) 4D-STEM analysis on Apple Silicon, validated against py4DSTEM at one pinned upstream commit (`tools/lib/fetch-py4dstem.sh` fetches it into the gitignored `References/`).
**v4.5.0 was released 2026-10-05**, version/build 4.5.0 / 8 (macOS 27+; v3.0.0 stays for older systems). The consolidation plan **exited 2026-09-11** (`../_archive/mac4DSTEM/docs/archive/consolidation-plan.md`, §7 checked line by line) and the feature freeze it carried lapsed with it. Rules only here; status and history elsewhere.

## Read, in this order

1. `docs/status.md` — what is live now, one table. Every session starts here.
2. `ROADMAP.md` — the feature plan: themes, priorities, and how a v3 feature is pre-registered and built (§6).
3. `docs/open-items.md` — live defects and debts only, ≤ 12 lines each.
4. `docs/architecture.md` — layering, ownership, where files go.
5. `docs/decisions.md` — the ADR index; one row per decision, the record itself in `docs/decisions/`.

Skills: `/pickup` takes the next step from `docs/status.md`'s handoff;
`/diagnose` is Gate D; `/adversarial-review` is Gate B; `/closeout`.

## Hard rules

- **What the app is** (owner, 2026-09-30): pure macOS, simple, reliable, an intuitive UI/UX — and scientifically correct. No filler: every control, number and sentence earns its place or goes. v4.1 is the plateau (ADR 049): the feature list is frozen, sessions finish or remove, they do not add — until v4.5 ships; then v5.0 is the EDX suite, the one reopened theme (ADR 052).
- **Rules serve the app** (owner, 2026-09-29): a rule that would make the app worse — less simple, robust, correct or intuitive — is not followed; the commit names the rule and says why. Rules are changed here, not worked around quietly.
- Views describe UI only; loading, parsing and compute live in `Core/`. `AppState` is the single source of truth until the plan's stores replace it.
- New stored state in `AppState` names its owner first; `inventory` now reports (not blocks) growth of `AppState.swift` + `Support/ResultExport.swift`, and a commit that grows them says why no other home would do.
- **Gate D** applies when a change can move a scientific number, or the cause of a defect is not yet established — not every change in `Core/`. Diagnosis, refuting observation, predicted outcome, experiment, then the fix; an independent refuter after; a fixture; the model that wrote the change never approves it alone — review the diagnosis, not the diff.
- **What does NOT need Gate D**: placement/presentation changes, renames, docs, tooling, and defects whose mechanism a reproducing observation already proves. State which trigger applies, or that neither does.
- Tests by tier (owner 2026-10-14; full rule in the suite `../CLAUDE.md` "Rigour follows risk"): tier 1 = a number a scientist reads can move, and any doubt means tier 1; tier 2 = behaviour without numbers; tier 3 = wording, docs, test-only changes, byte-identical refactors. Break every new tier-1 test before trusting it — confirm it goes red on the mutation it claims to catch; tier 2 samples two or three; do not drive the app during the unit gate. Without `../CLAUDE.md` every change is tier 1.
- **Numerical testing policy** (D12, Paul 2026-10-19): readers, I/O, indices and metadata are tested exact. Numerics are compared against the pinned Python reference within a tolerance written per function (`assert_allclose` style: about 1e-7 relative for float64, 1e-5 for float32), never widened to hide a bug. During an app-to-kit switch, bit for bit is only a quick check that nothing moved by accident; if it fails, verify against the Python reference within tolerance and do not block. A moved pinned number gets its own commit with the reason. Some tests and harnesses still assert numerics exactly; converting them to a written tolerance is a later code change.
- Never widen a gate that fails silently. Cost a UI change (rows/pt) before designing it, and open the app periodically — minutes of driving have found defects a green suite could not, which can be green about the wrong thing.
- Quote test numbers only from a dated run named by its log, not a path (session logs are gitignored, not retained); evidence a reader must open is committed as a fixture under `mac4DSTEMTests/Fixtures/`; registrations are retired (suite rule, 2026-10-15) and the old ones are cited at `../_archive/mac4DSTEM/docs/registrations/`; everything else is in git history.
- Parallel sessions on this Mac share `/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks/`: while a file `drive` exists a session is driving the app — start no test run (a test host steals focus); `mkdir heavy.1` / `heavy.2` is a build slot, removed after. Commit by explicit paths; another session's uncommitted edits stay theirs.
- Never read a gate's exit code through a pipe or backgrounded wrapper — redirect to a log, `echo $?` on its own line, grep the log's own exit line; count tests by method name and reconcile against the expected delta.
- A lost session resumes from its own scratchpad, never from memory.
- A threshold (a fraction, a bar, a cliff) is a property of the dataset and settings it was measured under, not of the method, until measured on every dataset it will touch — measure the distribution first, or ship the quantity and let the reader judge. Never infer a mechanism from a null result.
- No claim a reader cannot reproduce. The repo is public.
- Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` — nil by decision; `.automatic` residency was dropped, not tuned.
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the matching `.metal` structs (all 4-byte fields).
- Port deviations from py4DSTEM get an inline `DEVIATION` note.
- Don't add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch; use `tools/run-tests.sh unit` for unsigned XCTest work.
- On-screen verification may be claimed only when it actually drove the app and is sure — name the build, say what was clicked, what was seen; otherwise it is stated as unverified on screen. A drive never writes or clears the owner's clipboard: a Copy step is checked by `NSPasteboard.changeCount` (the hook refuses `pbcopy`).
- Docs are part of done: update `docs/status.md` and `docs/open-items.md` in the same commit as the code, net negative markdown lines or say why.
- Commit freely: land work as coherent commits with the gate numbers in the message. Pushing stays the owner's — ask before any push.
- **`main` only** (owner directive 2026-09-17): no feature or worktree branches, local or remote; every change lands as a commit on `main`. The one-time cleanup back to a single branch is `../_archive/mac4DSTEM/docs/archive/git-cleanup-2026-09-17.md`.
- **Repos stay light** (owner, suite `../CLAUDE.md`, 2026-10-15): the repo holds what builds, tests and explains the app. The old docs archive, drive records, reports and diagnostic probes moved to `../_archive/mac4DSTEM/` (outside the repo, untracked; git history keeps them too). A path written `../_archive/mac4DSTEM/<repo path>` is an archive citation, relative to this repo's root; `inventory` checks each one when the archive folder is there. Closed items and old status rows go to that folder, not into the tree. `tools/` holds only what the gates, the hooks, CI or the release procedure run.
- **Frozen shell** (owner, 2026-09-22): `UI/ContentView.swift`, `UI/WorkspaceView.swift`, `UI/WorkspaceInspector.swift`, `UI/LayoutPolicy.swift` and `App/WorkspaceNavigation.swift` change only against a picture the owner has accepted (ADR 035); every other UI session is a room, Prepare first. Wording that corrects a false claim may change in a frozen file; structure and width may not (owner, ADR 050).
- **A failed reproduction gate closes an item** (owner, ADR 050): a new registration is a new item — never amend-and-continue.
- **Decisions are put to the owner as a sheet** (owner, ADR 050): each problem in plain words, the options with effort and risk, a recommendation and an independent second opinion; he answers by option. The Board's cards are that sheet's source.
- **Unvalidated stays labelled** (owner, 2026-09-18): phase mapping, and any product that self-reports `validation:"none"`, ships badged unvalidated and is never called validated in a release note or doc until it passes on one dataset with truth; `inventory` greps the badge and the key.
- **SpectroKit and FormatoKit** (ADR 064, 067): standalone EDX (fit, quantification) is SpectroKit's and the file readers with the one HDF5 lock (`DM4Experiment`/`DM4Error`, `VeloxEMDReader`, `HDF5Serial`) are FormatoKit's, imported at exact tags (`Package.swift`, SpectroKit 0.6.1 + FormatoKit 0.4.0: bumped together, never one without the other); a fix to either lands there and arrives by a tag bump, gated here. 4D × spectroscopy stays here. The Run configuration is `Develop` so the kits build optimised; keep its name.
- **DiffractoKit** (0.3.1): the crystallography, ring and ellipse fit, and vector-matched phase mapping (`PhaseVectorMatcher`, `PhaseReferenceLibrary`, `DiffractoOrientation`), imported at the exact tag 0.3.1 (`Package.swift`, the Xcode project, both `Package.resolved`; `sources.manifest` links DiffractoOrientation to the `phasevectors` harness group). The app's `EulerAngles`, `ACOMOrientation` and `OrientationResult` (`Core/Analysis/OrientationResult.swift`) serve ACOM and stay here; a fix to the matcher lands in the kit and arrives by a tag bump.
- **ImagoKit** (ADR 070): the exact-length 2D FFT, `FFT2D` (the app's former Core/Compute FFT2D was its origin), is `ImagoCore.FFT2D`, imported at the exact tag 0.1.1 (`Package.swift`, the Xcode project, both `Package.resolved`; `sources.manifest` links ImagoCore to every harness group that compiles an FFT2D user). A fix to the FFT lands in ImagoKit and arrives by a tag bump, gated here. `FFT1D` (ACOM's azimuthal transform) is `ImagoFFT.FFT1D` since 0.1.1; `ParallaxAlignment`'s levels stay here (see `docs/open-items.md`, "Parallax on CuboParallax 0.4.0"). The tests of `FFT2D` (`FFT2DArbitraryLengthTests`) stay as consumer tests of the kit.
- **Suite board**: at closeout update only this repo's row, `lanes/mac4dstem`, as the suite `../CLAUDE.md` says (URL, fields, pinning, the routine).
- Decisions are a file in `docs/decisions/` plus a row in `docs/decisions.md`; the pre-2026-09-16 log is verbatim in `../_archive/mac4DSTEM/docs/archive/decisions-log-2026-08-17-to-2026-09-16.md`.
- What code already enforces: `run-tests.sh core` holds the layering; `run-tests.sh inventory` holds the UI contract greps, harness manifest, tools classification, NOTICE hashes and the size report.

## Build / test

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build   # the scheme's Run config, Develop
tools/run-tests.sh unit | scientific | all | inventory | core | campaign   # inventory = the repo's own review
git config core.hooksPath tools/hooks                   # once per clone: pre-push runs inventory + an app build
```
