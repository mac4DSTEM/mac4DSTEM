# AI-pipeline port — the completed analysis, 2026-09-11

Six area maps, nineteen adversarial verifications and a synthesised port plan.
The session that ran this ended before reading it; the result was recovered from
the workflow journal afterwards. **Evidence and a proposed plan — not an
authorisation.** Three things below are decisions only the owner can make, and
one of them is a standing decision this port would reverse.

## The three findings that change the shape of the task

1. **A standing owner decision already covers this.** `docs/decisions.md`
   (2026-09-08, "C8: the four pure engines stay on the branch") says these files
   are **not ported unwired** — they "re-enter with their product and UI layers
   through the §1.5 design session, whose four questions may change their
   contracts." The stated reason (dead Core in a tree about to become v3.0.0)
   has lapsed now that v3.0.0 shipped, but the *condition* has not: the design
   session decides where this UI lives, and `main` still has no AI Analysis
   workspace. A port needs a new dated entry reversing it, not a silent
   override.
2. **The science is ORIGINAL work, not a py4DSTEM port.** Zero `DEVIATION`
   notes, no reference implementation under `tools/`, and the segmentation
   explicitly abandoned skimage's `regionprops` convention because it read the
   fixture needles ~1.5x too long — so the shipped length and width match
   nothing upstream. **No parity harness can be built**; the only ground truth
   is a synthetic fixture plus a hand count. Gate D applies: `lengthPx`,
   `widthPx`, `orientationDegrees`, `area` and `arealDensity` all reach an
   export.
3. **The feature's own pre-registered ship gate is unmet.** Its design doc
   requires a baseline — plain threshold plus connected components, without the
   ridge filter — and says "the ridge filter must beat it on both the synthetic
   fixture and the hand count, or it does not ship." That comparison was never
   written, and the hand count was never made.

**One correction to the committed record**, found by the same pass: `status.md`
and the C8 triage both say the branch's tests "never met a compiler". That
caveat is on the embedding tests only — the precipitate tests did compile and
run (12/0), though the log is a lost scratchpad name and must be re-run rather
than cited.

---

# Port plan: `ml/disk-detector` → `main`

Repo `/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM`, main at `5933ea5`, branch `ml/disk-detector` (27 ahead of merge base `84b2498`, 41 behind main). Nothing here is a merge. Every step is a hand-applied edit on main, and every step ends at a green `tools/run-tests.sh` invocation.

---

## 0. Disposition of every file

### Comes across unchanged (4 files)

| File | Why it is clean |
|---|---|
| `mac4DSTEM/Core/Analysis/Precipitates/PrecipitateReflections.swift` | Foundation + `FloatImage` only. `FloatImage` exists at `mac4DSTEM/Core/Data/DiffractionPattern.swift:16`. Zero references to any branch-only type. |
| `mac4DSTEM/Core/Analysis/Precipitates/PrecipitateStatistics.swift` | Foundation only; depends on `PrecipitateSegmentation.Object`, which lands with it. |
| `mac4DSTEM/Session/DiffractionGroupsProduct.swift` | 99 lines, byte-for-byte main's `Session/StrainProduct.swift:16-18,59-63` shape. Its one stale comment (`TaskProductState.staleDiskSettings`, line 51) must be repointed at main's `stale(reason:)` (`mac4DSTEM/App/ProductWorkflow.swift:292`). |
| `mac4DSTEMTests/PrecipitateTests.swift`, **first class only** (lines 1–763) | Touches no `AppState` symbol; first `AppState` construction is at :778, inside the second class. |

### Comes across with named edits (6 files)

| File | Edit required before it lands |
|---|---|
| `mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift` | (1) add an `isFinite` guard before the background blur — `gaussianBlur` at :346-387 runs raw over `image.pixels` at radius 48, and `robustThreshold` (:266-273) then calls `.sorted()`, which is undefined with NaN present because Float comparison is not a total order. Sister file `PrecipitateReflections.swift:125` already guards. (2) rewrite the citations at :57 and :81 (`fix-c/gateD-C3.md`, `fix-b/gateD-P6.md` — neither exists in either tree). |
| `mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift` | (1) repoint `:3` (`docs/ai-ml/README.md §6`, absent on main), `:20` and `:533` (`References/training_runs/.../fix-c/gateD-C1.md`, gitignored at `.gitignore:15`, tracked in neither branch). (2) leave the header at :29-31 as written — it is a requirement the port satisfies, not an error. (3) `accumulate` at :493 is scalar `O(positions × dims²)` with Accelerate already imported; leave it, record it in `docs/open-items.md`. |
| `mac4DSTEM/Session/PrecipitateProduct.swift` | Needs an `isStale` in main's `StalenessVerdict` shape (`mac4DSTEM/App/ProductWorkflow.swift:312-368`); it has none, and `DiffractionGroupsProduct` does. See step 6. |
| `mac4DSTEM/App/AppState+Precipitates.swift` | Three fixes, below. |
| `mac4DSTEM/App/AppState+DiffractionGroups.swift` | Carry the `Task.detached(priority: .userInitiated)` at :61 verbatim in substance; rewrite its comment, which cites `drive-groups` and `fix-a/gateD-A2.md` — `git ls-tree -r ml/disk-detector` matches neither. |
| `mac4DSTEMTests/DiffractionEmbeddingTests.swift` | Delete the header claim at :5-6 ("this session could not build, so nothing here was run against a compiler"). It was true at `a97e920` and false at `b61ea73`; carrying it onto main would be a false claim in a public repo. Repoint `:347`. |

### Rewritten, not ported (2 files)

- **`mac4DSTEM/UI/PrecipitateSettings.swift`** — the Section body itself is portable (it references no `WorkspaceArea`, no `navigation`), but its only mount on the branch is `UI/AIAnalysisSettings.swift:21`, which does not exist on main. It also repeats `.disabled(appState.isBusy)` at :29/:98/:121/:161 against main's `disabledWhileRunning(_:)` convention (`mac4DSTEM/UI/LayoutPolicy.swift`). Rewrite the mount and the disable idiom; keep the rows, the `rowIdentity` keying, and the `densitySummary` readout.
- **`mac4DSTEM/UI/DiffractionGroupsSettings.swift`** — same: the panel is fine, the host is not.

### Dropped entirely (13 paths)

| Dropped | Reason |
|---|---|
| `mac4DSTEM/Session/DiskLabelStore.swift` | Superseded by decision, not duplicated. `docs/decisions.md:661-673`: "The branch's `DiskLabelStore` is superseded, not ported," because a verdict per position cannot score a detector per disk. Main ships `Session/DiskCentreLabels.swift` (285 lines, 22 tests in `mac4DSTEMTests/DiskCentreLabelTests.swift`); the branch store has zero tests. |
| `mac4DSTEM/App/AppState+DiskLabels.swift` | Will not compile: `mergeCalibration(diskLabelsJSON:)` and `loadDiskLabelsJSON` do not exist on main (main has `diskCentreLabelsJSON` at `Core/Data/BraggVectorEMDWriter.swift:675` and `loadDiskCentreLabelsJSON` at :904). Its glue lives on main in `Support/ResultExport.swift:1259-1354`. |
| `mac4DSTEM/UI/DiskLabelRows.swift` | Every symbol it reads is absent from main. |
| Branch's `Core/Data/BraggVectorEMDWriter.swift` hunks (+63) | Main has the structural twin under `mac4dstem_disk_centre_labels` (:318, :675, :692, :1323, :1349, :1671, :1751-1758, :1902-1903). Adding `diskLabelsJSON` alongside gives `writeFile` two independent preserve-across-rewrite paths over two attributes — a silent sidecar data-loss class and a Gate D trigger. **This is the one place a careless port does real damage rather than failing to compile.** |
| `mac4DSTEM/Session/LearnedDetection.swift` (branch) | Main is a strict superset: 234 lines vs 133, with six main-only members called at `AppState.swift:4505, 4628, 4678, 1034, 4784, 1881` and covered by `mac4DSTEMTests/LearnedDetectionSessionTests.swift`. The branch's `threshold = 0.9` literal against main's `LearnedDiskDetector.defaultThreshold` (0.7, `Core/ML/LearnedDiskDetector.swift:48`) would move a scientific number: main's own scan-bench recorded 4 544 peaks at 0.7 vs 3 086 at 0.9. |
| All of `tools/disk-detector/` (branch) | Uniformly pre-C7 (Core AI / 128 px / 0.9). Main's README already records "the Core AI version stays on `ml/disk-detector`". Two branch regressions to stay away from: `export.py`'s `sha256_tree` lacks main's dot-prefix exclusion (a `.DS_Store` would move `learned_model_sha256`), and `evaluate.py` lacks `label_ingredient()` / `--ingredient`, so it `KeyError`s on any app-exported labels file. |
| `Models/DiskDetector/disk-detector-heatmap-b32.aimodel` | Zero ported files reference it. Main loads `withExtension: "mlpackage"` (`Core/ML/LearnedDiskDetection.swift:317-318`). It cannot be committed as-is (`.gitignore:32` bans `*.aimodel`, negations at :39-40 name only the 256 mlpackage), and `Models/DiskDetector` is a pbxproj folder reference, so `tools/run-tests.sh:244-258` would print `UNTRACKED … .gitignore:32` and exit 1. |
| Branch's `tools/run-tests.sh`, `tools/lib/sources.manifest`, `.gitignore`, `mac4DSTEM.xcodeproj/project.pbxproj`, `Package.swift` | All are behind main. The pbxproj is the dangerous one: the branch lacks `ARCHS = arm64` (main :343/:414, landed in `5d08c7d` as the v3.0.0 archive-blocker fix), the `Info.plist` exception, `Session/DiskCentreLabels.swift`, `Session/FitOverlayPresentation.swift`, the Licenses/LICENSE/NOTICE resources, and sits at `CURRENT_PROJECT_VERSION 5` / `MARKETING_VERSION 2.5.1`. **Hand-edit main's copies. Never copy a branch build file.** |
| `docs/archive/2026-08-31-review/test-evidence/independent-acom-mutations/source-copy/**` | **63 duplicated Swift sources, 1 156 031 bytes, tracked on the branch and deliberately absent from main.** It is a verbatim second copy of `mac4DSTEM/Core/**` and `mac4DSTEM/Session/**` frozen at the 2026-08-31 review. Resurrecting it would put two copies of every Core file in the tree, poisoning every `git grep` the repo's own rules depend on and inflating the archive by 1.1 MB for evidence already summarised in `docs/archive/2026-08-31-review/independent-acom-mutations/results.json`. Do not port it. An empty directory shell remains on disk locally at that path — delete it. |

---

## 1. The AppState-rule-compliant shape

**The branch already satisfies the ownership half of the rule; do not redesign it.** Swift forbids stored properties in extensions, and the three `AppState+*.swift` files are methods only (no file-scope `var`/`let`, no `static var`, no `nonisolated(unsafe)`, no associated objects). State lives in two `@Observable @MainActor package final class` owner types in `Session/`, each with `package nonisolated init() {}`, `private(set)` product state, plain `var` run controls, and a `clear()` that drops the dataset-scoped half — byte-for-byte `mac4DSTEM/Session/StrainProduct.swift`.

`AppState.swift` gains exactly two type-scope `let`s:

```swift
let precipitates = PrecipitateProduct()          // branch AppState.swift:250
let diffractionGroups = DiffractionGroupsProduct()  // branch AppState.swift:252
```

the same one-line-per-feature reference main already uses at `AppState.swift:209` (`let strain = StrainProduct()`) and `:489` (`let diskCentreLabels = DiskCentreLabelStore()`). **No forwarding properties** — the UI reads `precipitates.…` directly. Pin that with a `Mirror`-based test in the shape of `mac4DSTEMTests/NavigationSeamTests.swift:14-26`, one per new product. (Known limit, stated in that test: `Mirror` sees stored properties only, so a computed forwarder is caught by review, not by the test.)

Two additions the branch also makes, both compliant: `PrecipitateProduct` needs an `isStale` in main's post-C4(b) shape (`StalenessVerdict`, `AnalysisMode.replayKind`, `ProductWorkflow.currentReplaySignature`, `TaskProductState.stale(reason:)` — `mac4DSTEM/App/ProductWorkflow.swift:312-368`), which the branch predates entirely. And take the branch's `braggPeakCount` change (`var braggPeakCount: Int?` → computed `{ braggVectors?.totalPeakCount }`, branch `AppState.swift:439-441`) on its own merit: it **removes** stored state. It is line-neutral (3 lines either way), so it pays nothing toward C5.

### The C5 budget — pay it before you spend it

`tools/run-tests.sh:132-151` sums `wc -l` of `mac4DSTEM/App/AppState.swift` + `mac4DSTEM/Support/ResultExport.swift` in the working tree against `HEAD` (if either is dirty) or `HEAD^` (if clean) and sets `rc=1` on any growth. Main today: **5467 + 2042 = 7509**.

The port needs roughly **+30 in `AppState.swift`** and **+2 to +6 in `ResultExport.swift`**. Two levers, in this order:

**Lever 1 (step 1, mandatory):** move `AnalysisMode` out of `AppState.swift:47-62` into `mac4DSTEM/App/ProductWorkflow.swift`. Sixteen lines leave `AppState.swift`, the enum has no `AppState` dependency, and `ProductWorkflow.swift` already owns `WorkspaceArea` (:10) and every presentation switch over `AnalysisMode` (`extension AnalysisMode` at :169, :182, :193, :204, :216, :228, and :392-562). **This also relocates the two new cases and `showsApertureOverlay` outside both budgeted files permanently**, leaving only ~11 lines of dispatch/clear/refresh wiring inside `AppState.swift`.

**Lever 2 (step 6, when `ResultExport.swift` must grow):** move `currentScalarResultMetadata` (`Support/ResultExport.swift:1405-1490`, ~85 lines) to a new `mac4DSTEM/Support/ResultMetadata.swift`. It stays an `extension AppState` — it reads `virtualShape`, `dpcDisplay`, `strain.component`, `acomSession`, `parallaxDepth` and more, so it cannot join the `extension AnalysisMode` tables in `ProductWorkflow.swift`. This is a file-placement move that satisfies the byte count, not the consolidation it superficially resembles. Say so in the commit message.

---

## 2. Build integration — the exact edits

### `mac4DSTEM.xcodeproj/project.pbxproj`

Six `membershipExceptions` entries. Format: relative to the `mac4DSTEM/` synchronized root group, one per line, tab-indented ×4, trailing comma, sorted **case-insensitively** on the whole path (proved by `Core/Compute/MetalEngine.swift` preceding `Core/Compute/MTLTexture+Float.swift`). None of the six needs quoting.

```
Core/Analysis/DiffractionEmbedding.swift                      after :64 DatasetPreview.swift, before :65 DiskDetection.swift
Core/Analysis/Precipitates/PrecipitateReflections.swift       ┐
Core/Analysis/Precipitates/PrecipitateSegmentation.swift      ├ after :76 ParallaxSubpixelReconstruction.swift, before :77 ProbeKernel.swift
Core/Analysis/Precipitates/PrecipitateStatistics.swift        ┘
Session/DiffractionGroupsProduct.swift                        after :122 DatasetResidency.swift, before :123 DiskCentreLabels.swift
Session/PrecipitateProduct.swift                              after :127 OperationCenter.swift, before :128 QCalibrationRun.swift
```

The list is an **exact invariant**, not a convention: main's 75 non-`Info.plist` entries are a perfect set-equality match with every `.swift` file under `mac4DSTEM/Core` and `mac4DSTEM/Session`. Verify set-equality after editing, not the individual lines. A missed entry is **not** a duplicate-symbol link error — Swift mangles by module — it is a type-identity failure (`mac4DSTEM.PrecipitateReflections.Candidate` vs `DSTEMCore.PrecipitateReflections.Candidate`) surfacing as "cannot convert value of type X to expected type X" at the 48 app files that `import DSTEMCore`/`DSTEMSession`.

Second pbxproj change, at **project** level (main has zero `OTHER_SWIFT_FLAGS` today):

```
OTHER_SWIFT_FLAGS = "$(inherited) -Xcc -DACCELERATE_NEW_LAPACK";
```
- Debug `000000000000000011000000`: between :400 `ONLY_ACTIVE_ARCH` and :401 `PROJECT_UNIQUE_VALUE`
- Release `000000000000000012000000`: between :464 `MTL_FAST_MATH` and :465 `PROJECT_UNIQUE_VALUE`

Do not touch `ARCHS = arm64` (:343, :414) while you are in those two configs.

No test-target change: `mac4DSTEMTests` is a `PBXFileSystemSynchronizedRootGroup` (:153-157) with no exception set. No Resources change: `Models/DiskDetector` is already a folder reference (:53, :183, :304). No Metal change: no ported file imports Metal, so the byte-identical-struct rule is not engaged.

### `Package.swift`

Insert as the first entry of DSTEMCore's `swiftSettings` (currently `Package.swift:24`):

```swift
.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"]),
```

Verified empirically, not inferred: `xcrun swiftc -typecheck` on a file using `__LAPACK_int` errors `cannot find '__LAPACK_int' in scope`; with the flag it type-checks clean. `dsyevd_` alone compiles without it (deprecation warning only) — `__LAPACK_int` (`DiffractionEmbedding.swift:562-583`) is the hard error. Main's own `3c4b82c` established that project-level settings do not reach the SwiftPM targets, so **the `Package.swift` line is the operative one**; the pbxproj lines cover the app target only if an exception entry is ever missed. Nothing else in `Package.swift` changes — DSTEMCore's `path` is `mac4DSTEM/Core` with no `sources:`/`exclude:`, so `Core/Analysis/Precipitates/` is picked up recursively. `.unsafeFlags` is legal because the package is an `XCLocalSwiftPackageReference "."`; it permanently forbids consuming DSTEMCore as a versioned remote dependency. Say that in the commit.

### Harnesses — the silent break

`tools/lib/sources.manifest:299-304`'s `core` group globs `"$core"/**/*.swift(N)`. Two harnesses consume it with a bare `xcrun swiftc … -framework Accelerate` and no `-Xcc`, and both stop building the moment `DiffractionEmbedding.swift` lands:

- `tools/bragg-spacing-probe/run.sh:50-53`
- `tools/training-dataset-campaign/run.sh:19-23`

Both are `diagnostic` (`tools/run-tests.sh:94-96`), so nothing goes red. **Add `-Xcc -DACCELERATE_NEW_LAPACK` to each swiftc line directly.** Do *not* put it in `MAC4DSTEM_ISOLATION_FLAGS` (`sources.manifest:86-94`) — neither harness sources that array; only `strain-frame-test`, `ws2-crystal-test`, `reduced-export-test`, `two-spec-analysis-test` and `q-calibration-gate-test` do. This glob is a main-side invention that postdates the branch; the branch's manifest has no `core` group at all, so the hazard is structurally invisible from the branch side.

No `sources.manifest` group registration is needed (the `core` glob already covers the new Core files; groups "intentionally stop at Core/", :47-49, so the two Session products need nothing). No `tools/run-tests.sh` change: the `scientific` array is byte-identical on both sides, no `tools/` directory is added, the harness count stays 46, and the two test files ride the existing `unit` gate.

### Model placement

Nothing moves. Main ships `Models/DiskDetector/disk-detector-heatmap-256.mlpackage` (572 KB, tracked, negated at `.gitignore:39-40`). The branch's `.aimodel` is dropped (§0). If the Core AI runtime is ever wanted back, repo-root `Models/DiskDetector/` is the correct home — never under `mac4DSTEM/`, where the synchronized group hands it to MLAssetCompile against `MACOSX_DEPLOYMENT_TARGET = 14.0` (:397, :462) — and it would need a `.gitignore` negation **pair** including the load-bearing `/**` line. Out of scope.

---

## 3. The ordered steps

Each step ends at a build or a gate. Run gates as `tools/run-tests.sh <target> > log 2>&1; echo $?` on its own line, then grep the log — **never through a pipe** (`| tail` reports `tail`'s status; this has swallowed a failing gate three times).

### Step 0 — three owner decisions, no code

Nothing can be sequenced until these are answered. Put them to the owner as a list; record the answers as one dated `docs/decisions.md` entry (append-only — this port *reverses* a standing decision and needs a new entry saying so, not a silent override).

1. **Reverse `docs/decisions.md:723-729`** (2026-09-08, owner in chat: "leave" — the pure engines stay on the branch and re-enter only through the §1.5 design session). The stated reason was dead Core sitting in a tree about to become v3.0.0; v3.0.0 has shipped, so the reason has lapsed. The decision has not.
2. **Where the UI lives.** Main has no sixth workspace: `WorkspaceArea` (`mac4DSTEM/App/ProductWorkflow.swift:10-16`) is prepare/image/map/reconstruct/results, `aiAnalysis` returns zero hits tree-wide, and v3.0.0 deliberately put the re-landed learned detector into the existing Disks room (`mac4DSTEM/UI/MapSettings.swift:58`). Two exits:
   - **(a) Rebuild `WorkspaceArea.aiAnalysis`** — touches `ProductWorkflow.swift` (the case plus ~10 exhaustive arms), `UI/WorkspaceInspector.swift:76`, `UI/WorkspaceView.swift:264,300`, `UI/WorkspaceSidebar.swift:186`, `UI/ImagePanes.swift:201-205,1166`, `App/mac4DSTEMApp.swift:117` (Cmd-5, re-keying Results to Cmd-6), and changes `mac4DSTEMTests/ProductWorkflowTests.swift:93`, which pins `WorkspaceArea.allCases.map(\.title)` to the five-title literal.
   - **(b) Mount both Sections in existing rooms** — precipitates in Imaging, diffraction groups in Imaging or Map. This is what `docs/ai-ml/precipitates.md` §3 originally specified ("deliberately a Form section, not a new workspace… the owner wants slow, conservative UI integration"), and it is what `PrecipitateSettings.swift`'s own surviving header at :7-12 still says.
   - **Recommend (b).** It is strictly smaller, it leaves `ProductWorkflowTests.swift:93` untouched, and the 2026-09-07 room decision (`0a38efc`) is superseded by the later 2026-09-08 entry anyway. `docs/archive/v3/c8-triage-2026-09-08.md:84` already rules `AIAnalysisSettings` a **rewrite** because C7 retired its learned-disks case into `MapSettings`. Either way, `mac4DSTEMTests/ProductWorkflowTests.swift:83` (`testEveryAnalysisHasOneProductWorkspace`) requires every new `AnalysisMode` to be routed to exactly one area's `analysisModes`.
3. **Does precipitates ship without its own pre-registered gate?** `docs/ai-ml/precipitates.md` §6 (branch, :125-127) requires a baseline — plain threshold + connected components, no ridge filter — and states: the ridge filter must beat it on both the synthetic fixture and the hand count, **or it does not ship**. No such comparison exists anywhere on the branch, and the Al-Si-Mg hand count was never made. Either the baseline is written as part of the port (step 5), or the owner explicitly waives his own pre-registration in `decisions.md`. Do not land a measured number under an unmet ship gate without one or the other.

Also decide two conventions the code itself flags as unresolved, not blessed: `area` is the thresholded mask footprint and reads ~2× the drawn bar (`PrecipitateSegmentation.swift:52-59`), and `widthPx` reads ~4 for a drawn 3 because the extents are centre-to-centre spans plus 1, exact only for an axis-aligned object. Both appear in the objects table; `area` reaches the export.

### Step 1 — C5 down payment (**this is the first commit**)

Move `AnalysisMode` from `mac4DSTEM/App/AppState.swift:47-62` to `mac4DSTEM/App/ProductWorkflow.swift`, beside `WorkspaceArea` and its existing `extension AnalysisMode` tables. Nothing else. Update `docs/status.md` and `docs/open-items.md` in the same commit; run `tools/sync-agents-md.sh` if `CLAUDE.md` changed.

- Gate D: **neither trigger applies.** Pure placement, no scientific number moves, no defect with an unestablished cause. State that in the commit message.
- Gate: `xcodebuild … build`, then `tools/run-tests.sh unit` and `tools/run-tests.sh inventory`. The inventory line must read `AppState + ResultExport lines  7493  (7509 at HEAD^)`.
- Why first: it is small, reversible, science-free, and it creates the headroom every later step spends. Landing it before any decision in step 0 is settled is safe and useful on its own terms.

### Step 2 — build flag, ahead of the file that needs it

`Package.swift` + two pbxproj `OTHER_SWIFT_FLAGS` + the two harness swiftc lines (§2). At this point the macro is defined and nothing uses it — a no-op that makes the tree correct in advance.

- Gate: `tools/run-tests.sh core` (exit 0, `swift build` of DSTEMCore), `tools/run-tests.sh all`, and run `tools/bragg-spacing-probe/run.sh` and `tools/training-dataset-campaign/run.sh` by hand once each — they are `diagnostic`, so no gate will ever tell you they broke.

### Step 3 — the three precipitate Core engines, unwired

Copy `PrecipitateReflections.swift`, `PrecipitateSegmentation.swift`, `PrecipitateStatistics.swift` into `mac4DSTEM/Core/Analysis/Precipitates/`. Add the three pbxproj entries. Apply the `isFinite` guard and the citation rewrites (§0). Bring `mac4DSTEMTests/PrecipitateTests.swift` lines 1–763 across as its own file (leave `PrecipitatePolishTests` behind until step 7).

Two things to fix in the test file while you are in it:

- The mutation list in the doc comment at :194-211 is **partly stale**: `drop the 4 * factor in the length formula` (:199-200) and `use lambda2 … for length instead of lambda1` (:201-203) describe the abandoned skimage `regionprops` convention, replaced at `PrecipitateSegmentation.swift:183-194`. The other three bullets (centroid transpose, `atan2(vy, vx)` sign, `(-90,90]` fold) still match `:305-306` and stay.
- `testInspectorRowIDsCollideExactlyWhereTheDriveShowedThem` (:854-863, in the second class) **cannot fail** — its body is `Set(0..<24)`, `Set(1...44)` and literal set arithmetic, calling no production symbol. Delete it when you port the second class; `testReflectionAndObjectRowIdentitiesNeverCollide` (:867) is the real one.

- Gate D: **first trigger applies** to the `isFinite` guard (it can move `area`, `lengthPx`, `widthPx`, `orientationDegrees`). Diagnosis, refuting observation, predicted outcome, experiment, independent refuter, fixture — before the fix. The refuting observation you owe is the one that could not be established by reading: **do main's virtual-detector images actually carry NaN?** `DisplayedProduct.swift:111` derives `validityMask` from `pixels.map(\.isFinite)`, so any `false` in a caller's mask means a non-finite pixel is present in exactly the array `segment()` blurs. Run it.
- Gate: `unit`, `core`, `inventory`. `inventory` will *list* the three files under the orphan check (`run-tests.sh:165-174`) — that block echoes candidates and never sets `rc=1`, so it is a note, not a failure.
- Break every new test before trusting it, including the ported ones: the branch's green run is unreproducible (below).

### Step 4 — the pre-registered baseline (**may end the feature**)

Write the comparison `docs/ai-ml/precipitates.md` §6 demands: plain threshold + 8-connected components with the ridge filter disabled, scored against the same synthetic fixture. Add the Al-Si-Mg hand count (the doc proposes a 100×100 sub-region) as a committed fixture under `docs/archive/v3/`.

If the ridge filter does not beat the baseline on both, the feature does not ship and steps 5–7 do not happen. That is the pre-registration, and it is the whole point of having written it before the code.

- Gate: `unit`. Commit the comparison numbers under `docs/archive/v3/` — evidence a reader must open goes there, not into a scratchpad log.

### Step 5 — `PrecipitateProduct` + the per-object data model

Land `mac4DSTEM/Session/PrecipitateProduct.swift` with its pbxproj entry and an `isStale` in main's `StalenessVerdict` shape. **Settle the §1.5 question here or ship the engines unwired.**

`PrecipitateProduct.objects` (:66) is a genuine per-object list — id, centroid, length, width, orientation, edge flag. Main's whole result model (`mac4DSTEM/Core/Data/DisplayedProduct.swift:77-127`) is per-scan-position. The branch's only export path saves the rasterised label image, and `clear()` (:191-201) drops objects, density and reflections on dataset activation with nothing written first. **Save and reopen loses every measured number.** Either add a per-object export/sidecar path (which is what step 6's ResultExport budget is for), or ship without one and write it into `docs/open-items.md` as a named debt, in the owner's words.

- Gate: `unit`, `core`, `inventory`. No `AppState.swift` change yet, so C5 is still at 7493.

### Step 6 — wire precipitates into `AppState`, with three fixes

Add `let precipitates = PrecipitateProduct()`, `case precipitates` (now in `ProductWorkflow.swift`, free of C5), `showsApertureOverlay` (also in `ProductWorkflow.swift`), the `.scan` arm of `activeResultDomain` (`AppState.swift:732-737`), the re-run dispatch arm, `precipitates.clear()` at dataset reset, the `refreshForCurrentPosition` break, and the `ResultExport` kind/name/units triple. Switch the two aperture-rerun guards (`AppState.swift:3236,3247`) from `== .virtualDetector` to the predicate. Spend Lever 2 (§1) in the same commit.

Three fixes that must land with the wiring, not after:

1. **The denominator.** `AppState+Precipitates.swift:190` reads `product.validityMask.filter { $0 }.count` from the **currently displayed** product, while `PrecipitateProduct.sourceValidity` (`:101`) holds the mask the objects were actually segmented from. Traced end to end: `segmentPrecipitates` calls `publishProduct` with no `validityMask` → `AppState.swift:290` defaults nil → `DisplayedProduct.swift:108` → `:110-111` takes the `.scalar` path → `PrecipitateSegmentation.swift:223` builds the label image as `[Float](repeating: 0, …)` so every pixel including background is finite → mask all-true → `analysedPixels` = width × height. With 20 % invalid scan positions the density is reported 20 % **low**, and `:210` writes `analysed_pixels` into export provenance as if it were the analysed extent. **The file's own doc comment at :180-183 states the wrong behaviour as if it were the design** — treat the comment as part of the defect, or a reviewer will read it and think the denominator was considered.
   Worse sibling, same root cause: `computePrecipitateDensity` guards only `product.domain == .scan, case .scalar`, and the Compute Density button (`PrecipitateSettings.swift:117`) is gated only on `!objects.isEmpty` and `!isBusy`. Display an unrelated scan image, press it, and you get a density against that image's pixel count — and because the `product.kind == objectsProductKind` guard at `:206` skips the provenance merge, `analysed_pixels`, `areal_density` and `r_pixel_size` are recorded **nowhere**. Strictly worse than the first bug: a wrong number on screen with no audit trail. One fix covers both — read `precipitates.sourceValidity`/`sourceImage`, and refuse when the objects did not come from the displayed product.
2. **The silent refusal.** `:188` returns `.failed("Show a virtual image first")` with no `statusText`, and the call site discards the outcome. (`:109`'s twin is unreachable — `canSegment` at `PrecipitateSettings.swift:16-21` is the identical predicate, the button is `.disabled` at :98, and :100-101 already prints the caption. Dead code, not a silent failure.) Note the functions are `@discardableResult` deliberately, matching main's convention at `AppState.swift:3357,4270,4650` — the discard is not an accident, but the refusal must still reach the activity log.
3. **Detach.** `proposePrecipitateReflections` (:28) and `computePrecipitateDensity` (:185) run synchronously on the main actor with no cancellation; only `segmentPrecipitates` detaches. `placeVirtualDetector` (:96) fires `Task { await runVirtualDetector() }` unstructured and discards the outcome.

- Gate D: **first trigger applies** to fix 1 (it moves `arealDensity` and `analysed_pixels`). Fixes 2 and 3 are presentation/concurrency — say so and proceed. The `AnalysisMode` case, the dispatch and the `clear()` are pure placement.
- Gate: `unit`, `inventory`. The inventory line must not exceed 7493.
- Adding `case precipitates` breaks every exhaustive `switch` with no `default` — expect edits in `ProductWorkflow.swift`, `ReplayPlan.swift`, `FitOverlayPresentation.swift`, `ResultExport.swift`, `ImagePanes.swift`, `MapSettings.swift`, `WorkspaceSidebar.swift`, `WorkspaceView.swift`. Route it to the **right** `activeResultDomain` arm: get it wrong and segmentation still succeeds while `computePrecipitateDensity` rejects its own output with "Show a virtual image first" — a compiling, quiet failure of exactly the shape this repo keeps shipping.

### Step 7 — precipitates UI + the ten portable polish tests

Rewrite `PrecipitateSettingsSection`'s mount per the step-0 decision. Port the ten pure `PrecipitatePolishTests`; leave behind the two that construct a live `AppState` and assign `.aiAnalysis`/`.precipitates` unless exit (a) was chosen; delete the vacuous row-id test. Adopt `disabledWhileRunning(_:)`. Reintroduce no `disk.labels.*` accessibility name — that prefix is now main's (`disk.labels.{toggle,thisPosition,total,clearPosition,save,export}`).

- Gate: `unit`, `inventory`. Then **on-screen verification is the owner driving the app** (Track B retired 2026-09-03). State the drawing as unverified on screen until he has seen it. Any bug he finds enters through `/diagnose`, never as an app change made to satisfy a checklist.

### Step 8 — `DiffractionEmbedding` Core + its tests, unwired

Copy the file and its pbxproj entry, apply the citation rewrites, delete the false header claim in the test file. Record, do not fix, the k-means empty-cluster reseed at `:690-702`: the mechanism is real and reproducible (with coordinates `[0,1,100]`, k=3, centroids `[0.5,200,300]`, index 2 is selected twice because `oldCentroids` is never refreshed inside the loop), but 12 000 randomised trials of the verbatim `kMeans` produced **zero** clusters lost below what the data can attain — it self-heals on the next iteration. It is a robustness nit, not an output defect. Two real side effects to note in `docs/open-items.md`: `changed = true` on every reseed prevents early convergence, and `counts` is never refreshed inside the reseed loop.

Also add a clamp or a note for negative `explainedVariance` (`:287`) — `dsyevd_` on a near-singular covariance can return slightly negative eigenvalues.

- Gate D: **first trigger applies** (explained variance, group assignment, similarity are scientific numbers, and this code has never run against main's Core). See §4 for what the tests do and do not establish.
- Gate: `unit`, `core`, `all`, `inventory`. The two harnesses from step 2 must still build.

### Step 9 — `DiffractionGroupsProduct` + `AppState` wiring + UI

Same shape as steps 5–7. `AppState+DiffractionGroups.swift` needs `fourD` widened from `private` (`AppState.swift:107`) to `private(set)` (branch `:140`) — net-0 lines but a real widening of the datacube to every file in the app target. That is a decision, not a mechanical edit; the alternatives are a narrow internal accessor or keeping `runDiffractionGroups` inside `AppState.swift` (which costs budget).

Carry `Task.detached(priority: .userInitiated)` at `:61` verbatim in substance. Main sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` **and** `SWIFT_APPROACHABLE_CONCURRENCY = YES` in all four configs, `DiffractionEmbedding` is `package nonisolated enum` with an `async` `compute`, and under SE-0461 a nonisolated async callee runs on its **caller's** executor — awaiting it directly from the `@MainActor` method ran the whole embedding on the main thread (698/698 samples, ~5 minutes frozen with Cancel inert). Main already records the identical finding for a different callee at `AppState.swift:4699-4703` and fixes it the same way. The trap is live on main.

**Do not carry the branch's `.learnedDisks` fold in `ResultExport.swift`.** Branch `:1464` folds `.learnedDisks` into the `.disks` arm of the kind/name/units switch but leaves its sibling at branch `:1609` as `== .disks` only — so a learned Bragg vector map falls through and exports with **real-space** `rPixelSize`/`rPixelUnits` instead of reciprocal, and the three `detector_class`/`learned_threshold`/`learned_model_sha256` provenance keys are silently dropped. Main has no split brain (it handles the learned detector inside `.disks`) and is better off keeping it that way.

- Gate: `unit`, `inventory`, then owner drive.

---

## 4. What must be gated, and what the gating proves

**Gate D applies to this port. State it, do not assume it.**

- **Trigger 1 (a change can move a scientific number):** the `isFinite` guard (step 3), the density denominator (step 6), and the whole of `DiffractionEmbedding` landing on main's Core for the first time (step 8). `lengthPx`, `widthPx`, `orientationDegrees`, `area`, `arealDensity`, explained variance, group assignment and cosine similarity all reach an export via `AppState+Precipitates.swift:158-171,206-229` and `AppState+DiffractionGroups.swift`.
- **Trigger 2 (cause not yet established):** the NaN question in step 3 — whether main's virtual-detector images carry non-finite pixels could not be settled by reading.
- **Neither trigger:** the `AnalysisMode` move (step 1), the build flag (step 2), the pbxproj entries, the UI mounts, the silent-refusal and detach fixes, and dropping `DiskLabelStore`/`AppState+DiskLabels`/`DiskLabelRows` (three files with no call sites outside themselves). Say "neither applies" explicitly and proceed.

**No, ported gating does not travel.** Three independent reasons:

1. **The branch's unit gate never ran.** Branch `docs/status.md:50-51`: `run-tests.sh unit` exited 69 against the 8 GB disk floor; the 486/1/1-of-488 figure came from a fallback bare `xcodebuild test`, and the row ends "Not the gate: `run-tests.sh unit` with 8 GB free is still owed." Four commits landed unmeasured.
2. **The evidence is gone.** Every cited log is a gitignored scratchpad name, and CLAUDE.md records those are not retained (2026-09-09: all 24 cited `scratchpad/` paths were already gone). Re-run; do not re-cite.
3. **The code changed.** The `isFinite` guard and the denominator fix are new science-affecting edits made *during* the port. Nothing gated on the branch covers them.

**And the precipitate science is unverified regardless of the port.** Say this in `docs/status.md` in the same commit, because it is the honest reading and it will not become true by testing harder:

- This is **original work, not a py4DSTEM port**. Zero `DEVIATION` notes across all five precipitate files; the sole py4DSTEM mention is a coordinate-convention note at `PrecipitateReflections.swift:10`; there is no reference implementation under `tools/`. `PrecipitateSegmentation.swift:172-182` explicitly abandons the skimage `regionprops` 4·√λ convention because it read the fixture needles ~1.5× too long — so the shipped length/width match **nothing upstream**.
- **A py4DSTEM parity harness cannot be built** for it, because py4DSTEM has no counterpart. The only available ground truth is the synthetic fixture plus the owner's hand count, and the hand count does not exist.
- **All twelve `PrecipitateTests` are Swift-against-Swift** on a fixture built for the code. They prove self-consistency and catch mutations; they establish nothing about correctness against physical reality.
- **The lattice classifier has never run on real data.** `AppState+Precipitates.swift:49` hardcodes `matrixBasis: nil`, so `onMatrixLattice` is always false, the default confirmation set is degenerate, and the "Matrix" badge (`PrecipitateSettings.swift:143-149`) can never appear.

The embedding side is better but narrowly so. **Two of its tests are genuine independent ground truth** and are the ones worth the port: `DiffractionEmbeddingTests.swift:367` plants a known spectrum `[100,64,41,26,17,11,7,4.5]` on a Gram-Schmidt basis built from constants in the test file and demands it back (residual ≤ 1e-6, eigenvalues to 1e-8) — a converged solver passes, one power step cannot; `:452` rebuilds the mean-centred covariance through `referenceBinnedVector` (:537), an independent re-implementation, and checks eigenvector residual, ordering, and `explainedVariance = eigenvalue ÷ trace`. Four others (`:150, :182, :218, :261`) are Swift-against-itself. `:296` is the anti-transpose fixture written because the M1 x/y-swap mutation survived the entire suite on symmetric fixtures. There is **no py4DSTEM comparison and cannot be one for the binning stage** — the `DEVIATION` at `:39-44` says py4DSTEM featurises user-supplied maps, never raw binned patterns. One gap worth naming: `referenceBinnedVector` only ever runs at `binnedSize` 16 on a 32-px detector, where the centring `offset` is 0, so the non-divisible binning path's offset is never independently checked — the same class of blindness as the M1 transpose.

**Correct the committed record** in the same commit as step 3: `docs/status.md:52` and `docs/archive/v3/c8-triage-2026-09-08.md:86` both claim the branch's tests "never met a compiler" / that all test files carry that caveat. The caveat exists only at `DiffractionEmbeddingTests.swift:5`. `PrecipitateTests.swift` carries none, branch `docs/status.md:87` records it 12/0 and 12/0, and `References/training_runs/disk-detector-2026-09-06-polish/fix-c/tests.log` is a `** TEST SUCCEEDED **` run of `DiffractionEmbeddingTests` at `b61ea73`. The claim is wrong; the run is still unreproducible (that log is gitignored). Fix the sentence, re-run the suite, cite the new dated log by name.

Two gates beyond `run-tests.sh`:

- **Gate B (`/adversarial-review`)** on steps 3, 6 and 8 — every one touches `Core/` or moves a number, and the model that wrote the change never approves it alone. Review the diagnosis, not the diff.
- **The owner drives** steps 7 and 9. No drawing change is verified until he has seen it.

---

## 5. Effort and the first commit

**Six to eight sessions**, assuming step 4 passes. Sessions 1–2 are cheap and low-risk (steps 1–3); session 3 is step 4 and may terminate the precipitate half; sessions 4–5 are steps 5–7 and carry the two Gate D items and the C5 lever; sessions 6–7 are steps 8–9. Add one if exit (a) is chosen in step 0 — the sixth workspace is roughly a session on its own, spread across eight files and two pinned tests.

**First commit: step 1 alone.** Move `AnalysisMode` from `mac4DSTEM/App/AppState.swift:47-62` to `mac4DSTEM/App/ProductWorkflow.swift`; update `docs/status.md` and `docs/open-items.md`; nothing else. It is ~16 lines out of the most contested file in the repo, it is pure placement with neither Gate D trigger, it is gated by `xcodebuild build` + `unit` + `inventory`, and it takes the C5 sum from 7509 to 7493 — buying the headroom every later step needs, *before* any of them needs it. It is also useful and correct standing alone if the owner answers step 0 differently than recommended, or not at all.

Commit only when asked; never push.