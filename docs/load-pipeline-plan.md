# The load pipeline — executable plan

**Opened 2026-08-06.** One feature, built in six stages: the app should tell you
what it is doing while a dataset opens, let you decide *what* to load (whole,
cropped, or binned) from a preview of the actual data, hold that in memory when
it safely fits, and keep every result traceable to the source file.

Hand any prompt in §6 to a **fresh agent on an empty context**. Each names the
files to read first, the constraints, the review gate, how to verify, and the
definition of done — same convention as the finished
[`docs/archive/v1.0/ui-implementation-prompts.md`](archive/v1.0/ui-implementation-prompts.md).

**This file is the single source of truth for this feature's status.** Update
the checklist in §5 when a stage lands.

---

## Relationship to the v1.0 tag

This work is **not** gated on the tag, and the tag is **not** gated on this
work. They are independent and can proceed in either order.

Measured 2026-08-06: `tools/run-tests.sh unit` → **exit 0, 126 tests, 0
failures**; `run-tests.sh all` green on 30 harnesses; `git tag -l` empty; tree
dirty. What blocks the tag is **#46** plus signing/notarization — see
[`docs/open-items.md`](open-items.md). Nothing below should be used as a reason
to delay it, and #46 must not be folded into a stage here: it is a small
correctness fix with its own recorded *do not retry* note.

**L1 in particular is shippable on its own** and closes a first-impression
defect (#36) without touching `Core/`.

---

## 1. Does this fit the app? — review

**Yes, and more tightly than a feature list would suggest.** Three reasons,
each from the code rather than from taste:

**It closes a gap the architecture already anticipated.**
`VirtualDetector.tiled` constructs a *synthetic* `DatasetDescriptor` per tile —
`shape: [range.count, d.rx, d.qy, d.qx]` — and hands it to the same compute
functions. So `DatasetDescriptor` is already treated as *"the shape of what is
being processed"*, not *"the shape of the file"*. A crop or a bin is the same
idea with different numbers. The abstraction to extend already exists; it is
not being bent.

**The reader already has the mechanism.** `H5Reader.readScanTile` builds an
HDF5 hyperslab with explicit `start`/`count` per axis and currently passes
`0` and full extent on the detector axes. A diffraction crop is
`start = [ry₀, 0, qy₀, qx₀]`, `count = [rows, rx, qyCount, qxCount]`. A real
crop moves `start[1]`. This is a genuinely small change in the one place that
matters, and unlike py4DSTEM it saves the memory *and* the I/O, because the
bytes are never read.

**The labelling problem is already solved once.** The app has
`CalibrationValueProvenance` (`.importedFile` / `.sessionSidecar` /
`.measuredInApp` / `.manual` / `.mixed`), `OriginProvenance`, and the
exploratory-vs-physical scale contract for ACOM. "This result came from a
binned cube" is the same shape of problem, and must reuse that pattern rather
than invent a second one.

**Where it does *not* fit, and must be handled deliberately:**

- **A crop is not an ROI, and the app already has ROIs** (`realSpaceShape`,
  `acomRegionRadius`, strain's "Current real-space ROI"). One changes what data
  exists; the other selects among data that exists. If the UI blurs them the
  feature will actively mislead. **Different vocabulary, different controls,
  and never both in the same section.**
- **`ROADMAP.md`'s scope rule** says a new feature must close a gap in
  `docs/v1-scope.md` or it is post-v1. This is post-v1 by that rule. Building it
  now is a deliberate scope decision, and `docs/v1-scope.md` should record that
  the frozen contract was extended rather than quietly widened.
- **The mission is parity with py4DSTEM.** Here parity is a trap — see §2.

---

## 2. How py4DSTEM does it, and where we deviate

Read from the vendored `References/py4DSTEM-dev`. **Its array math is the
reference; its state handling is not.**

### What py4DSTEM actually does

**It mutates the datacube in place.** `DataCube.crop_Q(ROI)` calls
`preprocess.crop_data_diffraction(self, …)`, which does
`datacube.data = datacube.data[:, :, qx0:qx1, qy0:qy1]` and returns **the same
object** (`datacube/datacube.py:350`, `preprocess/preprocess.py:123`). Same node
in the EMD tree, same `Calibration` instance, no new dataset, no record that a
crop happened. `crop_R` and `bin_Q` are identical in structure.

So the answer to "view or new dataset?" in py4DSTEM is **neither — it is a
destructive edit of the live object.**

**And as a memory strategy it does not work.** `datacube.data[:, :, a:b, c:d]`
is NumPy basic slicing, which returns a **view**: the full array stays alive as
`.base`. You lose access to the full extent while still paying for it. Binning
*is* a real copy (`.reshape(...).sum(axis=(3,5)).astype(dtype)`,
`preprocess.py:196`) so it does free memory — but only after the whole cube was
already in RAM. That is exactly why `bin_data_mmap` (`:222`) and the read-time
`binfactor` argument exist.

**Its actual two-mode design is at read time,** and it is the same one proposed
here: `import_file(filepath, mem="RAM" | "MEMMAP", binfactor=…)`, with an
explicit guard that *binning is unsupported for memory mapping*
(`io/importfile.py:62`). K2 is memmap-only (`read_K2.py:41`). **py4DSTEM is not
an "always load the cube" library** — it is a library where the *user* chose,
in a notebook, before calling `read`.

### The three specific defects we must not port

1. **Neither crop nor bin rescales the origin.** `crop_data_diffraction` resets
   the `Qx`/`Qy` dim vectors and stops. `bin_data_diffraction` scales
   `Q_pixel_size` up by `bin_factor` and writes it back — and still leaves
   `qx0`/`qy0` pointing at the old detector frame. In this app the exposure is
   worse than in py4DSTEM, because the origin is a **per-scan-position fitted
   map** (`Calibration.origin`), the ellipse fit is in detector coordinates, and
   the probe radius is in detector pixels.
2. **Binning sums, it does not average** — so intensities scale by
   `bin_factor²` and every absolute-intensity threshold moves with them — and it
   **silently crops the edge remainder** when the detector size is not divisible
   by the bin factor.
3. **Calibration propagation swallows its own failures.** `set_Q_pixel_size` is
   decorated `@call_calibrate`, which calls `calibrate()` on registered targets
   inside a `try/except` that **prints the exception and continues**
   (`data/propagating_calibration.py:82`). That is precisely the silently-failing
   gate this repo has a standing rule against.

### The deviation, stated once so it can be pasted at the call site

```
// DEVIATION from py4DSTEM (preprocess.crop_data_diffraction /
// bin_data_diffraction, References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:139,155):
// py4DSTEM mutates the datacube in place and leaves the fitted origin
// (qx0/qy0) referring to the old detector frame; bin additionally rescales
// Q_pixel_size but not the origin. Here the origin is a per-position fitted
// map and feeds disk detection, strain and ACOM, so a silently stale origin
// would fabricate results rather than merely mislabel them. This app applies
// the load specification at READ time and re-references every detector-frame
// calibration value against the new frame, or invalidates it explicitly with
// a named reason. The source file is never modified and the full extent stays
// reachable.
```

---

## 3. The model — a load specification, applied at read time

**Decision (recommended, see §7): a load is a *view* of the source file.** Not a
new dataset, not a destructive edit.

```swift
struct LoadSpecification: Equatable, Sendable, Codable {
    var scanCrop: (y: Range<Int>, x: Range<Int>)?     // nil = full scan
    var detectorCrop: (y: Range<Int>, x: Range<Int>)? // nil = full detector
    var detectorBin: Int                              // 1 = none
    var residency: Residency                          // .streamed | .resident | .automatic
}
```

Three properties follow, and they are the point of the design:

- **Applied at read time.** `readScanTile` selects the hyperslab and (for bin)
  reduces before returning. Cropped bytes are never read, so the saving is real
  in both memory *and* I/O — the thing py4DSTEM's in-place crop does not give
  you.
- **The source is untouched and the full extent is always reachable.** Changing
  the specification reopens; it does not re-derive from reduced data.
- **It is the provenance record.** Serialized into the session sidecar and into
  every export, so a product can be traced to *file + specification*. This is
  what makes the release owner's "stored as the analysis along the original
  cube" literally true.

`DatasetDescriptor` continues to describe *what is being processed* — its
`shape` reflects the specification. `LoadSpecification` is carried beside it as
the record of how that shape was reached.

---

## 4. Invariants — non-negotiable

**I1. Detector pixel inclusion never changes.** Circle, annulus, rectangle and
point keep py4DSTEM's exact predicates (`circle r² < rOut²`;
`annulus rIn² < r² < rOut²`). No performance change may touch
`VirtualDetector.makeMask`, `Shaders/VirtualMask.metal`, or
`Shaders/VirtualAperture.metal`.

**I2. A resident cube is bit-identical to the tiled path, and the test asserts
that** — see L2, where the reason it holds is derived rather than assumed.

**I3. Cropped or binned data is a different measurement** and is labelled as
such through display, export and reopen. Reuse `CalibrationValueProvenance` and
the exploratory/physical scale pattern; do not invent a second vocabulary.

**I4. A sampled preview is not a result.** It cannot be exported or promoted to
a product, and is visibly marked as sampled with its stride stated.

**I5. Progress is measured or absent.** A determinate bar means a known
denominator. Unknown-duration phases get a named spinner, never a synthetic
percentage.

**I6. Streaming stays the default and stays tested.** Every path degrades to it
— on allocation failure, on a too-large cube, on user choice — and the parity
harness runs both on every gate.

**I7. Never widen a gate whose failure mode is a fabricated result.** Standing
repo rule; it applies to the residency threshold and to every calibration
re-reference below.

---

## 5. Status

- [x] **L1 — Honest load progress** (2026-08-06, closes #36). The seven
  hard-coded waypoints are gone; unmeasurable phases are named spinners with
  **no** percentage, and the only determinate phase is the whole-cube pass,
  reported as `Scanning patterns 12,288 / 16,384 · 768 MB of 1.00 GB` from the
  tile callbacks that were already emitting real fractions and had no consumer.
  **The load no longer ends before the first whole-cube pass** — that reorder is
  what fixes "sits there looking stuck", since the welcome card used to vanish
  while the app was still scanning. `isLoadingDataset` became stored rather than
  `datasetLoadingProgress != nil`, so nil now honestly means *unmeasurable*
  instead of *not loading*. Pinned by `mac4DSTEMTests/DatasetLoadingProgressTests`;
  the mirroring test is **verified to fail 1/1 without the fix**.
  **Also landed here, out of order:** the L5 local-storage notice
  (`welcome.localStorageNotice`), at the release owner's request.
  **✅ Confirmed on the real app 2026-08-06** by the release owner, on a 3.96 GB
  cube: `Scanning patterns 1,378 / 16,218 patterns · 344 MB of 3.96 GB` with the
  bar advancing and the welcome card still up. That screenshot also **found a
  real defect and it is fixed**: the counts used the system locale while
  `SystemMonitor.byteString` does not, so a German system rendered
  `1.378 / 16.218 patterns · 3.96 GB` — two meanings of "." in one line. Counts
  now group with a fixed `en_US` separator; pinned by
  `testPatternCountsGroupIndependentlyOfTheSystemLocale`. **Not covered by an
  automated visual baseline** — none exists. The QC playthrough was retired
  2026-08-17; L1's on-screen behaviour is now §A of
  [`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md), which
  the 2026-08-06 screenshot already satisfies.
- [~] **L2 — Resident cube + automatic fallback + exact-equality parity harness.**
  **Mechanism landed 2026-08-17; stage NOT complete.**
  In: `Core/Data/ResidentCube.swift` (the `Residency` model and the admission
  rule), residency owned by `FourDArray` — which is why no call site changed,
  every tiled path already takes it — a preload with measured patterns/rows
  progress, `scanTile` served from the resident buffer, and the single-dispatch
  fast path at the top of `VirtualDetector.tiled`. Harness
  `tools/virtual-detector-residency/` asserts exact `==` across circle,
  annulus, off-centre annulus, rectangle, point, edge point and origin point,
  plus both aperture paths, the five tile-served reductions, refusal, release,
  cancellation and the staleness guard. Added to `run-tests.sh scientific`
  (31 harnesses now, not 30). App builds; `run-tests.sh unit` exit 0.
  **The harness's first version was wrong and green.** Setting
  `FourDArray.resident()` to return nil — residency silently never engaging,
  the exact failure L2.3 warns about — left every equality assertion passing,
  because a resident array still serves its *tiles* from the buffer, so the
  tiled fallback produced identical numbers without touching the reader.
  Equality and read counts prove the buffer holds data; only the dispatch
  **count** proves the branch ran. It now asserts progress tick shape (1 tick
  resident vs `ry` tiles streaming) and fails 1/1 on that control.
  **AppState wiring landed too.** The seam extracted for this stage is
  `App/DatasetResidency.swift` — the state L2 *adds* (mode, resident flag, byte
  count, preload progress), in its own `@Observable` type that `AppState` holds
  with **no forwarding properties**. It publishes what the array holds, never
  what was requested. The preload runs in `activate` before the first
  whole-cube pass and reports patterns and MB through L1's
  `scanProgressStatus`; the Performance panel gained a `Cube memory` row and a
  `Release cube` button. Pinned by `mac4DSTEMTests/DatasetResidencyTests`
  (8 tests) — **verified to fail 5/8** when `sync` is rewritten to publish the
  request instead of the buffer. One of those 8 originally passed under that
  control despite being named for exactly that property; it now forces a state
  where the request and the buffer disagree.

  **Adversarial review taken 2026-08-17** (the gate this stage names). It could
  **not** refute the bit-identity claim — it stress-tested 4 shapes × 6 tilings
  × 2 kernels with magnitudes chosen to expose reordering, and confirmed neither
  kernel reads threadgroup shape, SIMD width or thread position beyond the scan
  index. That claim stands. It found eight other things. Fixed here, each with a
  negative control:
  - **CRITICAL — the preload's fill offset was dead code in every test.**
    `makeResident` had no `maximumRows:` seam, so the ~683 MB default budget
    swallowed both fixtures whole, every preload was **one tile**, `filled` was
    always 0, and rewriting `base + filled * …` to `base + 0` left all 22
    harness assertions **and** the whole unit suite green. The four progress
    assertions were vacuous too — all trivially true of `[1.0]`. Now forced to a
    4-tile fill (2+2+2+1 over `ry = 7`); the control fails 1/1.
  - **Actor reentrancy.** `makeResident` suspends at every read, so a
    `releaseResident()` or `.streamed` request in that window was silently
    undone when the preload completed — panel reading "Streaming" with
    gigabytes held. Fixed with a generation counter checked after every
    suspension and before publishing. Two concurrent preloads each allocated a
    full cube; fixed with `preloadInFlight`. Both pinned, both fail without.
  - `maxBufferLength` is now consulted (it had **zero** references in the repo).
  - `selectDataset` preloaded with progress reporting disabled — #36's stall one
    layer down. Bracketed as a load. **UI unverified on screen**; it is a row in
    `docs/visual-acceptance-checklist.md` §A.
  - `ResidentCube.matches` is insufficient for L3 and its comment claimed
    otherwise — see the L3 blocker in `docs/open-items.md`.
  - The staging-copy overhead and `pattern(ry:rx:)` still streaming are recorded
    in `docs/open-items.md`, not fixed.

  **The sweep is built and run:** `tools/residency-sweep/` (a diagnostic, not a
  gate — same standing as `bragg-spacing-probe`). It synthesizes a ratio curve
  from **one** real file by truncating the scan axis, which is stronger than
  L2.3's two-cubes-either-side sketch. Measured 2026-08-17 on an Apple M3,
  5.33 GB working set, `036_STEM_SI…bin_2` (3.96 GB f32) copied to the internal
  SSD:

  | ratio | cube | cold dispatch | ns/MB | ×floor | run 1 ns/MB |
  |---|---|---|---|---|---|
  | 0.10 | 530 MB | 35.9 ms | 67,789 | 1.10 | 52,647 |
  | 0.20 | 1.06 GB | 66.9 ms | 61,550 | 1.00 | 179,053 |
  | 0.30 | 1.58 GB | 192.4 ms | 119,043 | 1.93 | 119,264 |
  | 0.40 | 2.12 GB | 390.3 ms | 179,620 | 2.92 | 141,867 |
  | 0.50 | 2.67 GB | 475.5 ms | 174,222 | 2.83 | 125,115 |
  | 0.60 | 3.18 GB | 1406.1 ms | 431,383 | 7.01 | 216,931 |
  | **0.70** | 3.73 GB | **20,315 ms** | 5,323,697 | **86.5** | 10,359,278 |
  | 0.74 | 3.96 GB | 54,665 ms | 13,482,580 | 219.1 | 6,892,196 |

  **The last column is a second run of the same sweep on the same file, and it
  is why nothing here should be read to two significant figures.** Ratio 0.20
  differs by 2.9× between runs; 0.60 by 2.0×. What is *stable* across both runs
  is the shape — roughly flat to ≈0.30, a climb through 0.40–0.60, and a wall
  between 0.60 and 0.70 of one to two orders of magnitude. Read the shape, not
  the values.

  **`f` stays `nil` by decision** (release owner, 2026-08-17), so `.automatic`
  streams and shipped behaviour is unchanged. Three reasons, weakest first:
  0. **One run does not reproduce another** to better than ~3× in the region a
     threshold would be chosen from.
  1. **There is no plateau** — cost is already 3.4× the floor at ratio 0.20.
     A gentle slope and then a wall, so "the last ratio below the cliff" (0.60,
     itself 4.1× degraded) would be a bad number dressed as a measured one.
  2. **The denominator is in question.** `recommendedMaxWorkingSetSize` is a GPU
     budget hint, and on this 8 GB machine it is **65% of physical RAM** — so a
     buffer at a high fraction of it competes with the OS and with this app's
     own staging copies. §L2.3's premise is that one working-set fraction
     transfers from an 8 GB Mac to a 128 GB one; at `f = 0.5` a 128 GB Mac would
     hold a 48 GB cube with 80 GB of RAM free, which is not the situation
     measured here. **Set `f` only after a second machine with a different
     RAM-to-working-set ratio has been swept** — and if the two disagree, the
     rule needs a second term, not a compromise value.

  **Two measurement defects were found and fixed before any number above was
  trusted** — both would have produced a confidently wrong `f`:
  - The knee criterion ranked by `streamed / resident`, which pays disk I/O on
    one side only. That ratio is monotone in cube size and **cannot** fall below
    the trigger before the swap cliff, so the tool would have recommended an `f`
    derived from whatever cube it happened to be handed. Invariant I7.
  - Its replacement used `min()` as the baseline and fired at 1.5×, which made
    the 530 MB row — small enough to sit in cache — the floor, so it called the
    knee at row two and ignored the 707 ms → 39.5 s wall five rows below. Now a
    running median with an 8× trigger.

  **Still outstanding:**
  1. Sweep a second machine, per the denominator question above.
  2. Re-measure **#37** — but note the review's counter-argument: the resident
     branch checks cancellation either side of one indivisible
     `waitUntilCompleted`, so residency makes cancellation *coarser*, not finer.
  3. The L3 blocker on `ResidentCube.matches`.
- [~] **L3 — `LoadSpecification` + crop-on-read + calibration re-referencing.**
  **Started 2026-08-18. Foundation only; no reader crops yet.**
  In: `Core/Data/LoadSpecification.swift` — `LoadSpecification` (scan crop,
  detector crop, bin factor) with `AxisCrop` stored as offset+extent so it is
  `Codable`/`Equatable` for sidecars and identity comparison, plus `LoadPushdown`,
  the per-reader declaration of whether a crop actually skipped I/O. `FourDArray`
  carries a `loadSpecification` (`.fullExtent` for now) and exposes
  `resident(for:)`. **The L2 blocker is closed**: `ResidentCube` carries its
  specification and `matches` compares it, so two equal-shape crops at different
  offsets no longer collide — verified to fail 1/1 when reverted to shape-only.
  App builds; `run-tests.sh unit` and `scientific` exit 0.

  **Next, and it is the bulk of the stage:** thread the specification through
  the five conformers per the correction in §6's L3 prompt — three of them
  ignore the descriptor entirely today — then the calibration re-reference, then
  `tools/load-spec-test/`. **Hand this to a fresh session**; the reader work is
  where the stage's risk lives and it deserves a clean context.
- [ ] **L4 — Bin-on-read**
- [ ] **L5 — Open-time preview and the load configurator**
- [ ] **L6 — Provenance through session restore and export**

**Order and parallelism.** L1 is independent — do it first, it is small and
visible. L2 before L3/L4, because "make it fit in memory" only means something
once residency exists. L3 before L4 (crop is selection; bin is a transform, and
bin on a cropped frame needs crop to be correct first). L5's *preview* half is
independent of everything and can be built any time; its *configurator* half
needs L3/L4. L6 closes the loop and must not be deferred past L4 — provenance
retrofitted is provenance not shipped.

**Before L5:** fix **#43** (the acceptance gate breaks if a session is saved for
a training dataset). L5 and L6 write load parameters into session sidecars and
will trip it constantly.

### Sizing — this is not a one-session feature

| Stage | Sessions | Why it costs what it costs |
|---|---|---|
| L1 | **1** | Values, not plumbing. Self-contained. |
| L2 | **1–2** | Compute change is small; the residency threshold must be *measured* (`tools/performance-baseline/` sweep), which is its own pass. |
| L3 | **3–4** | Re-sized 2026-08-18. **Five** conformers, not four (MIB and EMPAD both live in `VendorRawReaders.swift`, plus `DemoFourDDataSource`), each with three read entry points — and three of them ignore the descriptor entirely today, so they need real work rather than an offset tweak. Plus the calibration re-reference, a fixture, and an adversarial review that must be a separate agent. |
| L4 | **2** | The `bin2`→`bin8` fixture, then the highest-stakes adversarial review in the plan. |
| L5 | **2** | Preview and configurator are genuinely separate pieces of UI; #43 first. |
| L6 | **1** | Round-trip, if L3/L4 carried the spec correctly. |

**Realistic total: 9–11 sessions**, and most of that is fixtures, four readers,
and UI — not review overhead.

**On the review rule specifically: it costs a subagent call, not a session.**
"Never let the model that wrote a science-affecting change be the only one to
approve it" requires a *different agent*, which runs inside the same session —
minutes, not a calendar slot. What genuinely takes time is the `tools/` fixture,
because that is real work.

**And it cannot be replaced by testing at the end.** Twice — 2026-08-05 and
2026-08-06 — a fix here passed every test written for it, *including one
verified to fail without it*, and was still wrong. Both times the refuting
evidence was already sitting in a log nobody re-read. End-stage testing catches
the class of defect tests catch; it does not catch a **wrong diagnosis**, which
is this repo's actual failure mode. That is why the rule is *review the
diagnosis, not just the code*.

**Where the rule does not apply:** L1 and L5 touch no science and need only an
ordinary `/code-review`. L6 is a round-trip. Skipping the adversarial pass on
those costs nothing. **L3 and L4 are where it earns its keep** — those are the
stages that can produce wrong numbers that look right.

**The shortest path to feeling the win is L1 + L2** — honest progress and
instant virtual imaging — which is 2–3 sessions and touches no science. L3–L6
is where the schedule actually lives.

---

## 6. The prompts

### Session kickoff (copy-paste)

```
Pick up mac4DSTEM. Read CLAUDE.md first, then docs/load-pipeline-plan.md —
read §1–§4 (they carry the constraints), then the Status checklist in §5, and
take the next unchecked stage, executing its prompt in §6 end to end.

This changes app code, so follow docs/development-process.md: Explore subagent
(Haiku) to locate code, implement on the default model, and take the review
gate the prompt names before calling it done. Anything touching Core/ or the
science needs an adversarial review AND a tools/ fixture — and review the
DIAGNOSIS, not just the code. That rule has refuted a fix here twice, both
times after it passed every test written for it.

When it lands: tick the stage in §5, update docs/open-items.md, and stop with
a short summary. Commit only if I ask.
```

### Task closeout (run for every stage)

1. `tools/run-tests.sh unit` — must be exit 0.
2. `tools/run-tests.sh all` if the stage touched `Core/`.
3. **If the stage touched `AppState`, one seam was extracted** — binding since
   2026-08-17, `docs/development-process.md` §7. Overlays first, calibration
   last and not before L6.
4. **If the stage changed what the app draws or where a control lives**, request
   a Track B pass ([`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md)):
   write the specific checklist, and say plainly that the stage is unverified
   on screen until it comes back.
5. Tick the stage in §5 with a one-line record of what shipped **and what
   deviated**.
6. Update [`docs/open-items.md`](open-items.md) — add, amend, or delete.
7. State explicitly what was *not* verified.

---

### L1 — Honest load progress

**Closes #36.** No `Core/` changes.

**Read first:** `mac4DSTEM/App/AppState.swift` (`openFileAsync` ~1495,
`activate` ~1545, `updateDatasetLoadingProgress` ~1747),
`mac4DSTEM/UI/ProductWorkspaceViews.swift:121` (`loadingStatus`),
`mac4DSTEM/Core/Analysis/VirtualDetector.swift` (the `progress?(…)` callbacks).

**The problem, stated precisely.** The plumbing exists —
`datasetLoadingProgress` / `datasetLoadingStatus` drive a labelled bar with
accessibility identifier `welcome.loadingStatus`. What is wrong is the
*values*: they are hard-coded waypoints (`0.08` open → `0.28` discover →
`0.42` prepare → `0.52` calibration metadata), and then the bar **sits at 0.52
through the longest phase of all**, the first whole-cube pass. That is exactly
"jumps in huge blocks, then looks stuck".

**Do:**
1. Route the real per-tile fraction into `datasetLoadingProgress` for the
   initial analysis. `VirtualDetector.tiled` and friends already emit
   `progress?(Double(range.upperBound) / Double(d.ry))` — the callback is
   plumbed and unused at this call site.
2. Report the *quantity*, not the verb: `"Scanning patterns 12,288 / 16,384"`,
   and MB where the read dominates. `DatasetDescriptor.byteCountAsFloat32`
   already exists.
3. Honour **I5**: metadata phases get a named spinner and **no percentage**.
   Delete the synthetic waypoints rather than re-tuning them.
4. Check tile granularity: one tile can be a large fraction of the scan
   (`scanTileRows` = working set / 8), so the bar may still step visibly.
   **Measure before adding sub-tile reporting** — it may not be needed.

**Do not:** interpolate a fake fraction between real ones; report progress
whose denominator is a guess.

**Verify:** a unit test driving a mock `FourDDataSource` that asserts the
reported fraction is monotonic non-decreasing, starts < 0.05, reaches exactly
1.0 once, and never holds one value for more than a stated share of total wall
clock. Plus the QC playthrough reading the status string.

**Review gate:** ordinary `/code-review`. No science touched.

---

### L2 — Resident cube, with automatic fallback

**Read first:** `Core/Analysis/VirtualDetector.swift` (`tiled`, `run(cube:)`,
`image(cube:)`), `Core/Data/FourDArray.swift` (`scanTileRows`),
`Shaders/VirtualMask.metal`, `Core/Compute/MetalEngine.swift`,
`tools/performance-baseline/main.swift`.

**The finding that makes this cheap.** `VirtualDetector.tiled` already builds an
`MTLBuffer` per tile and hands it to **the same functions** a whole-cube path
would call. There is no separate tiled kernel. A resident cube is *"the tile is
the whole cube, and the buffer is not thrown away."*

**Why equivalence is exact, not approximate.** `virtualMaskSum` runs **one
thread per scan position**, summing over the detector in a fixed order, with a
mask built from `qy`/`qx` only. Tiles partition the **scan** axis, so a tile
boundary never splits a per-output-pixel reduction and every tile sees the
identical mask. **Therefore the tiled and full-cube virtual images are
bit-identical.**

**Do:**
1. A `ResidentCube` (one `MTLBuffer` + descriptor) owned beside `FourDArray`,
   and a branch at the top of `tiled(…)` that dispatches once against it.
2. Admission gated on the **Metal working set**, not
   `ProcessInfo.physicalMemory`:
   `descriptor.byteCountAsFloat32 <= device.recommendedMaxWorkingSetSize * f`.
   Note reads return Float32 regardless of on-disk dtype, so a uint16 file
   doubles.
3. **Measure `f`.** Extend `tools/performance-baseline/` (it already reports
   `estimatedWorkingBytes` for both a whole cube and a tile) with a residency
   sweep: repeated virtual images at several `resident / headroom` ratios on a
   real cube, looking for the knee. **Do not pick `f` by reasoning.**

   **Datasets the release owner has open and working (2026-08-06)**, both
   256 × 256 detector — read the exact working size from the inspector's
   *Cube (f32)* row rather than trusting these:
   - `036_STEM_SI_preprocessed_filtered_bin_2_20240723.h5` — scan **186 × 153**,
     28,458 patterns, **≈7.46 GB** as float32. Likely *above* the threshold on
     most machines, so it is the **fallback** case: it must stream, cleanly and
     without a stall.
   - a second cube of **16,218 patterns, ≈4.25 GB** float32 (the one in the L1
     load screenshot) — the plausible *resident* case.

   Two real points on either side of the knee is what the sweep needs. **Copy
   both to the local SSD first** — #30 measured ≈3.3 MB/s over the NAS, which
   would make the sweep measure the link instead of residency.

   **The threshold is a fraction of the machine's own working set, never a
   fixed byte count.** The app ships to Macs from 8 GB to 128 GB+; the same
   cube must go resident on a large machine and stream on a small one, from one
   rule. Hard-coding a size, or tuning `f` to make one particular dataset fit,
   would be a defect.

   **Testability consequence, and it is not optional:** the development machine
   as of 2026-08-06 is an **8 GB M3 MacBook Air**, whose working set is roughly
   5–6 GB — so neither cube above can go resident there, and the resident path
   **cannot be exercised by opening a real dataset on it**. The harness must
   therefore be able to force residency independently of the threshold (an
   explicit `Residency.resident` request, or an injectable headroom value, the
   same way `maximumTileRows` already lets parity tests force tiny tiles). The
   demo cube is 12 × 12 × 64 × 64 and goes resident anywhere. **Without that
   seam the equality harness silently tests the tiled path against itself** —
   the exact "assertion that passes in the broken state" this repo has been
   burned by.
4. **The preload itself reports measured progress**, in the same two quantities
   L1 established — patterns and MB — through `datasetLoadingProgress` and the
   welcome card. This is a **new** determinate phase, not the one L1 wired:
   L1 routes the first *analysis* pass, whereas residency introduces a distinct
   *read into the buffer* that happens before it, and on a multi-gigabyte cube
   that read is the longest single phase of the whole open. Reuse
   `AppState.scanProgressStatus`, and honour I5 — the denominator here is the
   cube, which is known exactly, so this phase must be determinate. **A silent
   preload would reintroduce the stall L1 just removed**, one layer down.
5. An explicit **"Release cube"** action, and automatic release when a
   reconstruction declares a `maxWorkingBytes` need that no longer fits —
   ptychography, parallax and depth sectioning already declare theirs and throw
   `.memoryLimit`.
6. A visible mode indicator: the user must be able to tell at a glance whether
   they are resident or streaming. The Performance panel already shows "App
   memory" and "Cube (f32)".

**The failure mode to design against.** Getting `f` wrong does not throw — Metal
pages, and the app becomes **slower than tiled while appearing to succeed**.
That is the worst regression class this app produces. Prefer a conservative `f`
and a measured knee over a generous one.

**Verify:** new harness `tools/virtual-detector-residency/` (or extend
`tools/virtual-detector-test/`), added to `tools/run-tests.sh`. Assert **exact
`==`** on the float arrays, resident vs tiled, sweeping circle, annulus,
rectangle, point, an off-centre annulus, and a point on the detector edge.

**Write this at the test site, in a comment:** `tiledDPStatistics` and
`tiledDiffraction` **do** reduce across tiles (weighted mean, running sum) and
are float-order dependent. Those are *tolerance* comparisons. Do not copy the
equality assertion into them, and if one flakes, **do not widen the tolerance**
— that is I7.

**Also:** re-measure **#37** (slow virtual-detector cancellation) afterwards.
Residency changes that problem entirely and the item may be obsolete or
different.

**Review gate:** adversarial. It changes how every analysis gets its data, even
though it must not change a single number.

---

### L3 — `LoadSpecification` + crop-on-read + calibration re-referencing

**The first stage that can produce wrong numbers that look right.**

**Read first:** `docs/load-pipeline-plan.md` §2 and §3 (this file),
`Core/Data/FourDDataSource.swift`, `Core/Data/H5Reader.swift`
(`readScanTile` ~438, `readScanRow`, `readPattern`), `Core/Data/DM4Reader.swift`,
`Core/Data/VendorRawReaders.swift`, `Core/Data/Calibration.swift`
(`OriginProvenance`, `CalibrationValueProvenance`),
`References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:123,139`.

> **⚠️ CORRECTION, 2026-08-18, before any L3 code was written.** The sizing
> below said the HDF5 change is "small and local" and that the others are
> "offset arithmetic rather than a hyperslab". **The premise was wrong.**
>
> **Four of the five conformers ignore the descriptor they are handed.**
> `H5Reader` builds its hyperslab from `descriptor.rx/qy/qx`. `DM4Reader` uses
> its own stored `rx`/`qy`/`qx`; the MIB and EMPAD readers in
> `VendorRawReaders.swift` use `scanWidth` / `Self.imageHeight` / `Self.width`.
> The `descriptor` parameter is accepted and never read:
>
> ```swift
> // DM4Reader.readPattern — `descriptor` unused
> let patPix = qy * qx
> let start = dataOffset + (scanY * rx + scanX) * patPix * elementSize
> ```
>
> Harmless today, because the descriptor is built from those same values. It
> stops being harmless the moment a *cropped* descriptor exists: three readers
> would return full-extent tiles. `FourDArray.scanTile`'s length check catches
> that as `allocationFailed`, so it fails loudly rather than fabricating — but
> "pass a smaller descriptor" is an HDF5-only trick, and this stage is four
> readers of real work, not one.
>
> **And §3's "cropped bytes are never read … in both memory *and* I/O" is only
> partly deliverable.** It holds for HDF5 on all four axes, and for a *scan*
> crop on the raw formats (a contiguous seek). A *detector* crop on
> DM4/MIB/EMPAD cannot skip bytes without many small strided reads, because
> patterns are contiguous.
>
> **Decided 2026-08-18 (release owner): push down where it pays, slice where it
> does not.** HDF5 pushes all four axes into the hyperslab. Raw formats push the
> scan crop and read-then-slice the detector crop. **Each reader must declare
> which it did**, and the app records that in provenance, so the saving is never
> overstated and no reader silently ignores a specification.

**Do:**
1. Add `LoadSpecification` (§3) and thread it through `FourDDataSource`,
   together with a per-reader capability declaration (see the correction above).
   HDF5: `readScanTile` already builds a hyperslab with per-axis `start`/`count`
   and passes `0` / full extent on the detector axes — crop moves those offsets.
   DM4 / MIB / EMPAD: scan crop by offset arithmetic; detector crop by slicing
   after the read, declared as such. **Every reader must consult the descriptor
   it is given** — the three that ignore it today are the actual work of this
   step, and a reader that quietly ignores a crop is the defect to design
   against.
2. **Re-reference every detector-frame calibration value** against the new
   frame, or invalidate it with a named reason and a provenance downgrade —
   never silently: `Calibration.origin` (fitted *and* measured per-position
   maps), `meanOrigin`, the ellipse fit (`a`, `b`, `θ`), the probe radius, and
   `Q_pixel_size`. Paste the `DEVIATION` note from §2 at the call site.
3. **A real-space crop changes what a scan index means.** Any existing strain
   map, ACOM map or Bragg-vector set is indexed against the old extent and
   becomes *ambiguous, not stale*. Invalidate them explicitly, with a message
   that says why.
4. **The reduced cube must reach L2's admission test.** A crop produces a
   smaller `DatasetDescriptor`, which is exactly what residency reads — so a
   cube that was too large to hold becomes resident once cropped, with no extra
   machinery. Do not special-case residency for full cubes; see §8.
5. Assert that `minPeakSpacing` still follows automatically — it derives from
   the fitted probe radius (backlog #5 / pipelines §10.3), so it should need no
   special handling. **Pin that with a test**, because it is exactly the kind of
   property that quietly stops being true.

**Do not:** copy py4DSTEM's in-place mutation, or its origin handling. Do not
let a crop reach the compute path before the calibration re-reference is proven.

**Verify:** `tools/load-spec-test/` — a cropped read must equal the
corresponding slice of a full read, **exactly**, on every reader. Plus a
calibration fixture: fit an origin on the full frame, crop, and assert the
re-referenced origin lands on the same physical feature, and that an
un-re-referenceable value is *invalidated* rather than carried.

**Review gate:** adversarial + `tools/` fixture, per CLAUDE.md. **Review the
diagnosis, not just the code.**

---

### L4 — Bin-on-read

**The scientifically hardest stage. Do not start it before L3 is green.**

**Read first:** `References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:155`
(`bin_data_diffraction`) and `:222` (`bin_data_mmap`),
`Core/Data/BraggVectorEMDWriter.swift` (it already divides the probe semiangle
by a bin factor on export — stay consistent with that), §2 of this file.

**Decided 2026-08-06: the offered bin factors are 2, 4 and 8 only.** py4DSTEM
accepts any integer, so this needs a `DEVIATION` note. The reasons are that it
makes the `bin2`→`bin8` ground-truth fixture below exact rather than
approximate, and it makes the edge-remainder path rare on real detectors
(64/128/256/512 are all divisible by 8). **Still implement and test the
remainder path** — a 384 px or cropped detector reaches it, and an untested
path that is merely rare is worse than a common one.

**Do:**
1. Bin in diffraction space at read time, matching py4DSTEM's **array math**
   exactly: it **sums** (not averages), so intensities scale by `bin_factor²`;
   it **crops the edge remainder** when the detector size is not divisible.
   Reproduce both, and state them in the UI — every absolute-intensity threshold
   moves with the binning.
2. Scale `Q_pixel_size` **up** by `bin_factor`; scale the probe radius and the
   origin (both maps) by `1 / bin_factor`. py4DSTEM does the first and not the
   rest; that is the deviation.
3. Label the result. A binned cube is not the same measurement — reuse the
   existing provenance/scale-labelling pattern (I3).

**The fixture, and it is unusually good.** The training set already carries
`bin2` and `bin8` files of the same data. **Binning `bin2` in-app by 4 must
agree with the file's own `bin8`.** That is real external ground truth, not a
self-consistency check. Build `tools/preprocess-crop-bin-test/` around it and
add it to `tools/run-tests.sh`.

**Also assert:** a virtual image from a binned cube relates to the unbinned one
by the documented `bin_factor²` intensity scaling and nothing else; the edge
remainder is dropped from the correct edge; a non-divisible detector size is
handled identically to py4DSTEM.

**Review gate:** adversarial, on Fable 5 or `/code-review ultra` — this is the
highest-stakes science change in the plan. **The reviewer must be given the
py4DSTEM source and told to refute, not to check.**

---

### L5 — Open-time preview and the load configurator

**The release owner's vision, and the stage where it becomes one screen.**

**Read first:** `UI/ProductWorkspaceViews.swift` (the welcome screen and
`loadingStatus`), `UI/DatasetInspector.swift`, `App/AppState.swift`
(`openFileAsync`), `UI/ApertureControl.swift` and `UI/PeakOverlayGeometry.swift`
(existing draggable-overlay patterns to reuse rather than reinvent).

**Fix #43 first** — the acceptance gate breaks if a session is saved for a
training dataset, and this stage writes load parameters into session sidecars.

**Do:**
1. **Preview (independent — can land alone).** On open, before committing to a
   load: a real-space image from a **deterministic strided sample** of scan
   positions, and mean/max DP from the same sample. Label both visibly as
   sampled, **with the stride stated** (I4). Not exportable, not promotable.
2. **The size arithmetic, on screen:** file bytes, cube as f32
   (`byteCountAsFloat32`, already displayed in the inspector as "Cube (f32)"),
   machine headroom, and what the current specification would cost. This is the
   only moment the user has the information and the decision is still cheap.
3. **Rectangle overlays** on the real-space preview (→ `scanCrop`) and on the DP
   preview (→ `detectorCrop`), plus a bin-factor picker, all writing one
   `LoadSpecification`.
4. **Vocabulary discipline (§1).** A crop is not an ROI. Different words,
   different controls, never in the same section as `realSpaceShape` /
   `acomRegionRadius`.
5. **Residency is automatic** (decided 2026-08-06): if the cube fits under L2's
   measured threshold it loads resident, with no prompt. When it does **not**
   fit, the app offers crop/bin as the way to make it fit — **that is the hinge
   that makes this one feature rather than three.**
6. **A short standing notice on the open screen: datasets should be stored
   locally.** This replaces the remote/local prompt originally proposed. #30
   measured ≈3.3 MB/s over a NAS — 4.8 ms per position, ~30× below gigabit,
   latency-dominated — so a network source costs minutes on *every* whole-cube
   pass, resident or not. One quiet line, phrased as guidance rather than a
   warning; it must not read as an error and must not block anything. Consider
   escalating it to a named line in the Performance panel only if measured
   throughput is low, which the app already computes.

**Say this in the UI copy, plainly:** loading into memory does **not** make the
load faster. #30 established that the cost is the link, not the algorithm. It
makes the waiting happen once, visibly, at a moment the user chose. If the copy
implies otherwise the feature will be perceived as broken.

**Trap to pre-empt in the label:** a strided preview and a real virtual image
*will* differ, and a user comparing them will file a bug.

**Verify:** unit tests on the rectangle→`LoadSpecification` mapping (including
inverted drags and out-of-bounds clamping), plus the Track B rows for L5 in
[`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md) §F.

**Review gate:** `/code-review`, plus a Track B pass as acceptance. UI-only
if L3/L4 are already green.

---

### L6 — Provenance through session restore and export

**Do:**
1. Serialize `LoadSpecification` into the session sidecar and into every export
   (`BraggVectorEMDWriter`), so a product traces to *file + specification*.
2. Reopening a session reopens the **source** file and re-applies the
   specification. Never re-derive from reduced data.
3. Display the specification wherever a result's provenance is shown, using the
   existing provenance vocabulary (I3).
4. Round-trip test: full → crop+bin → export → reopen → the specification and
   every calibration value survive identically, and a product from a binned cube
   is still labelled as such after reopen.

**Review gate:** `/code-review` + round-trip fixture in `tools/`.

---

## 7. Decisions owed by the release owner

1. ~~**View or new dataset?**~~ — **DECIDED 2026-08-17: a view** (§3), which is
   what the plan above is written for. **L3 is unblocked.** The deciding
   argument is the release owner's workflow (`docs/v2-scope.md` §1): if the
   reduced cube were a new dataset, "re-run at full extent" would mean redoing
   the analysis from scratch — exactly the manual step the app exists to remove.
   As a view, *removing* the specification **is** the promotion to full extent.
   It also keeps one source of truth for provenance and is strictly better than
   py4DSTEM's in-place mutation, which saves neither memory nor the full extent.
   *If you want a cropped cube writable as its own file, that is an additional
   export, not a change to this model.*
2. ~~**Does L1 ship before the tag, or after?**~~ — moot; L1 landed 2026-08-06,
   after the tag. **L2–L5 ship as `v1.1.0`; the `v2.0.0` question is decided at
   L6 on whether the sidecar/export format actually breaks** (`ROADMAP.md`,
   version policy).
3. ~~**Residency default**~~ — **decided 2026-08-06: automatic.** If the cube
   fits under the measured threshold, load it resident without asking. **No
   remote/local branch** — instead the open screen carries a short standing
   notice that datasets should be stored locally (see L2/L5). Simpler than the
   conditional prompt originally proposed, and easier to tighten later if the
   quiet path surprises anyone.
4. ~~**Bin factors offered**~~ — **decided 2026-08-06: 2 / 4 / 8 only.** See
   L4. A `DEVIATION` note is required, since py4DSTEM accepts any integer.
5. **`docs/v1-scope.md`** — record that the frozen contract is being extended
   deliberately, rather than letting it be widened silently.

---

## 8. Coverage — the release owner's brief, line by line

Audited 2026-08-06 against the original request, so a cold session can see what
is promised and what is not.

| Asked for | Stage | State |
|---|---|---|
| "If it is loading metadata, say that" | L1 | ✅ done — named spinner, no percentage |
| "how many patterns are done out of the total" | L1 | ✅ done — patterns **and** MB |
| "move smoothly and honestly, not jump in huge blocks or sit there looking stuck" | L1 | ✅ done — waypoints deleted; the load no longer ends before the first pass |
| "load the full datacube into memory when the dataset is small enough" | L2 | planned |
| "optional or automatic only when safe" | L2 | planned — **automatic**, decided §7.3 |
| "large files should still work with the current tiled streaming approach" | L2, I6 | planned — streaming stays the default and stays tested |
| "real loading progress during preload, ideally MB loaded and patterns loaded" | L2.4 | planned — a **distinct** phase from L1's; added after this audit found it missing |
| "use the in-memory cube for virtual imaging when available" | L2 | planned |
| "tests comparing in-memory and tiled virtual detector results" | L2 | planned — **exact equality**, stronger than asked |
| "circle, annulus, rectangle, point keep exactly the same pixel-inclusion behavior" | I1, L2 | planned — `makeMask` and both shaders are off-limits |
| "loading screen … inspects the file … preview of real space and diff space" | L5.1 | planned |
| "lets you load everything into memory or cropped" | L5.3 + L3 | planned |
| "draw a rectangle box overlay in the real-space preview … loads only that part" | L5.3 + L3 | planned |
| "bin the diffraction space by a factor x on load" | L4 | planned — 2/4/8 |
| "this lives in memory then" | L3/L4 → L2 | planned — **see the composition note below** |
| "doesn't change the original dataset" | §3 | planned — read-only source, spec applied at read time |
| "can be stored as the analysis along the original cube" | L6 | planned — spec in the session sidecar and every export |

### The composition that makes the vision work

A cropped or binned load produces a **smaller `DatasetDescriptor`**, which is
what L2's admission test reads. So crop/bin and residency compose without extra
machinery: **reduce the cube until it fits, and it becomes resident
automatically.** That is the release owner's "this lives in memory then", and it
is the reason L2 must come before L3/L4 — the stages are one feature, not three.
Any implementation that special-cases residency for full cubes only has broken
the point.

### What this plan does **not** cover

Named so nobody assumes otherwise:

1. **Cropping a dataset that is already open.** Every crop here happens at load
   time, from the open screen. Under the view model a mid-session crop is a
   reopen with a different specification, which is coherent but is *not* a
   "crop what I am looking at" gesture. If that interaction is wanted it is a
   separate stage, not a detail of L3.
2. **Real-space binning or thinning.** Only diffraction binning is planned.
   py4DSTEM has `bin_data_real` and `thin_data_real`; neither was asked for.
3. **Writing a cropped/binned cube out as its own file.** §7.1 chose a view, so
   a reduced cube is a specification, not a new dataset on disk. Exporting one
   as a standalone file is an additional export feature, not a change to the
   model — cheap to add later, but not in scope here.
