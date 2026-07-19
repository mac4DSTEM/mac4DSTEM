# Development plan: executing the forward plan token-conservatively

Companion to [`code-review-2026-07-19.md`](code-review-2026-07-19.md). Four
prompts, run **in order, one fresh Claude Code session each**, starting the
next only after the previous session's commit is green. Each prompt is
self-contained; the review doc is the shared spec, so the prompts stay short
and no session re-explores the codebase.

## How to run

- **Orchestrator model:** Fable 5 (or Opus). It plans, reviews every diff,
  and writes documentation.
- **Implementation:** delegated to subagents (`model: sonnet`) for isolated,
  well-scoped items; trivial single-file edits are done inline by the
  orchestrator (spawning an agent for a 5-line edit wastes more tokens than
  it saves).
- **Gates:** narrowest harness per item; `tools/run-tests.sh unit` once per
  prompt; the full `tools/run-tests.sh all` only at the end of Prompt 4.
- Sessions may need `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
  (see `tools/run-tests.sh`).

Shared rules embedded in every prompt below (the "Working rules" block) keep
token use down: no re-review, read only files being edited, subagent briefs
carry full context and return diff summaries + test output, never file dumps.

---

## Prompt 1 — Scientific contract fixes (Milestone 1: A1–A4)

```text
Read docs/code-review-2026-07-19.md, section A only. Implement A1–A4. The
file:line pointers in the doc are verified — trust them, do not re-review the
codebase, and read only the files you will edit.

Working rules (token budget):
- You are the orchestrator and reviewer. Delegate A2+A3 together to one
  subagent (model: sonnet) since both live in Core/Data/DM4Reader.swift; do
  A1 and A4 inline (small, single-file, scientific judgment required).
- Subagent briefs must include: exact file paths, the change specified in the
  review doc, and the gate command. Require back: a unified-diff summary and
  the gate output. No file dumps.
- After each item, run only its gate; run tools/run-tests.sh unit once at the
  end. Do not run run-tests.sh all.

Items:
- A1 (inline): AppState.calibrateEllipse feeds the log10-scaled display image
  into the intensity-weighted ellipse fit. Decide: fit the raw calibrated
  Bragg-vector map (preferred, matches py4DSTEM), or keep log weighting with
  an inline DEVIATION note per project convention. Gate:
  tools/ellipse-calibration-test/run.sh.
- A2+A3 (subagent): DM4Reader — throw .truncated when a decode slice exceeds
  the mapping instead of returning zeros; reject blob length ≠ cube size;
  use multipliedReportingOverflow for the shape product; cap walkGroup
  recursion depth (~64). Add malformed-fixture cases (truncated blob,
  overflow dims, deep nesting) to the most appropriate harness
  (tools/vendor-reader-test or a small new dm4-robustness harness following
  the existing tools/<name>/run.sh pattern). Gate: that harness.
- A4 (inline): unify AppState.realSpaceRegionShape and realSpaceRegionMask on
  one region predicate so the strain reference mask matches the displayed ROI
  pixel-for-pixel. Gate: tools/run-tests.sh unit (covers workflow contracts).

Finish: review all diffs yourself against the review doc's intent; mark A1–A4
done (✅ + date + one-line resolution) in docs/code-review-2026-07-19.md;
update README "Known limitations" if any entry is now resolved; commit once:
"Contract fixes: ellipse fit input, DM4 robustness, ROI parity (review A1-A4)".
Do not push.
```

---

## Prompt 2 — Responsiveness & forgiveness (Milestone 2: B1, B2, B5, C4, D1, D6)

```text
Read docs/code-review-2026-07-19.md, sections B (items B1, B2, B5), C (item
C4), and D (items D1, D6). Implement them. No scientific-contract changes are
allowed in this session — if a fix would alter numerics, stop and report.

Working rules (token budget):
- Orchestrator (you) reviews and documents; delegate parallelizable
  implementation to subagents (model: sonnet), one per bullet group below.
  Briefs carry full context; agents return diff summaries + test output only.
- Read only files being edited. Gates: tools/run-tests.sh unit once at the
  end, plus tools/ui-smoke-test/run.sh if UI behavior changed. Capture a
  tools/performance-baseline/run.sh JSON before the B fixes and after, and
  compare with compare.py.

Subagent 1 — perf (App/AppState.swift):
- B1: cache patternDisplayedValueRange / resultDisplayedValueRange behind the
  existing versioned-cache pattern (see patternNormCache) so colorbar labels
  stop costing O(pixels) per SwiftUI evaluation.
- B2: coalesce live disk detection in detectCurrentPattern using the same
  inFlight/pending scheme as scheduleLiveVirtualDetector.

Subagent 2 — hot loops:
- B5: remove the two full-array copies per pattern in
  DiskDetector.crossCorrelate; vectorize the ring-sum in
  OrientationMatcher.match. Numerical outputs must be bit-identical or
  within existing harness tolerances: gate with
  tools/disk-detection-test/run.sh and tools/acom-matching-test/run.sh.

Inline (orchestrator) — product judgment required:
- D1: updateAperture currently discards fitted origin maps on any center
  drag. Implement forgiveness: retain the fitted calibration and require an
  explicit confirmation ("Use manual center — supersedes fitted origin maps")
  OR a one-click undo in the status area. Pick the design that fits the
  existing UI idiom; keep the export-honesty invariant (manual center must
  never silently coexist with stale maps at export).
- D6: route the three most common failures to existing diagnostics instead of
  terminal alerts: zero accepted Bragg peaks → open the acceptance funnel;
  strain basis rejected → show basis diagnostics with the offending
  threshold; ACOM without Q calibration → link the Q-calibration step.
- C4: delete vestigial AnalysisMode.isAvailable; deduplicate the ellipse
  transform-matrix construction in Calibration.swift.

Finish: review diffs, verify the before/after performance JSON shows no
regression (B1/B2 wins are UI-side and may not appear in the harness — note
that), mark items done in the review doc, commit once:
"Responsiveness + forgiveness: cached ranges, coalesced detection, calibration
undo, diagnostic-routed failures (review B1-B2, B5, C4, D1, D6)". Do not push.
```

---

## Prompt 3 — First-run experience & visual polish (Milestone 3: D2, D3, D5, D7)

```text
Read docs/code-review-2026-07-19.md, section D items D2, D3, D5, D7.
Implement the product-polish milestone. UI-only: no changes under Core/
except where D5 needs an existing calibrated quantity exposed.

Working rules (token budget):
- This work is design-judgment-heavy: do D2 and D3 inline as orchestrator.
  Delegate D5 (mechanical once specified) to a subagent (model: sonnet).
- Use the app itself to verify: build and drive the demo fixture
  (--demo-fixture launch argument, see DemoFourDDataSource) rather than
  reasoning from source alone. tools/ui-smoke-test/run.sh is the gate.

Items:
- D2 First-run: surface the existing demo fixture on the welcome screen
  ("Try with demo data") and add a minimal guided path — open → calibrate →
  virtual image → Bragg → strain — using the existing readiness/guidance
  machinery, not a new tutorial framework. A scientist should reach a strain
  map without documentation.
- D3 Visual hierarchy pass over the tools panel and inspector: consistent
  8-pt spacing grid, one accent color reserved for each workspace's primary
  action, secondary labels .secondary / controls .small, monospaced digits
  for all numerics. No new features, no layout restructuring.
- D5 (subagent): add the direct scattering-angle (mrad) CBED scale option —
  the conversion already exists (DPC.milliradiansPerDetectorPixel); wire it
  into the CBED scale-bar/axis options where physically calibrated. Gate:
  tools/run-tests.sh unit.
- D7: capture a screenshot set from the demo fixture (welcome, Prepare with
  readiness, virtual imaging, Bragg overlay, strain map, Results) into
  docs/screenshots/ and embed the two best in README. Review the app icon
  against current macOS conventions; note (don't redesign) any gaps in the
  review doc.

Finish: run tools/ui-smoke-test/run.sh and tools/run-tests.sh unit; review
diffs; mark D2/D3/D5/D7 in the review doc; update README with screenshots;
commit once: "First-run demo path, visual hierarchy pass, mrad CBED scale,
screenshots (review D2-D3, D5, D7)". Do not push.
```

---

## Prompt 4 — Result storytelling, throughput, final gate (Milestones 4–5: D4, B3, B4)

```text
Read docs/code-review-2026-07-19.md, sections D item D4 and B items B3, B4,
plus section E. This is the final prompt of the plan: it ends with the full
aggregate gate.

Working rules (token budget):
- D4 and B3 are independent: delegate both to parallel subagents
  (model: sonnet) with complete briefs; you review.
- B4 (GPU disk-detection correlation) is the largest single project in the
  plan. Treat it as budget-permitting: implement only if D4+B3 land cleanly
  with budget to spare; otherwise scope it precisely (kernel design, parity
  plan, expected win) as a standalone follow-up section in the review doc
  and stop. A parity-gated stub is worth more than a half-validated kernel.

Subagent A — D4 result storytelling:
- Surface the existing Quantitative/Relative/Exploratory/Categorical status
  as a persistent colored badge on the result viewer (today it is inspector
  text). Add a one-click quality-overlay toggle pairing each map with its
  quality field (strain ↔ residual, ACOM ↔ reliability) using the
  ProductQualityField data already carried by DisplayedProduct. Gate:
  ResultPresentationTests via tools/run-tests.sh unit, plus
  tools/result-presentation-test/run.sh.

Subagent B — B3 tiled I/O↔GPU overlap:
- Double-buffer the tiled passes in Core/Analysis/VirtualDetector.swift and
  TiledDiskDetection.swift: read tile N+1 while tile N computes. Preserve
  cancellation semantics and the bounded-memory contract (at most two tiles
  resident). Gate: tools/virtual-detector-test/run.sh,
  tools/disk-detection-test/run.sh, and a before/after
  tools/performance-baseline comparison.

B4 (orchestrator decision, budget-permitting): Metal batched-FFT correlation
for Bragg disk detection, parity-gated exactly like the ACOM Metal backend
(CPU stays the oracle; Automatic selects by measured production benchmark,
not synthetic microbenchmarks). Parity gate: tools/disk-detection-test plus
tools/real-acom-benchmark-style real-data comparison; the README performance
narrative may only change with measured numbers.

Finish: run the full aggregate gate tools/run-tests.sh all. Review all
diffs. Update docs/code-review-2026-07-19.md: mark completed items, record
measured B3 (and B4, if landed) numbers with hardware/config per the
development-history measurement policy, and list anything deliberately
deferred. Update ROADMAP.md to reflect the cleared review backlog. Commit
once: "Result storytelling + tiled overlap [+ GPU correlation] (review D4,
B3[, B4]); full gate green". Do not push.
```

---

## Why not one prompt

A single session would (1) mix scientific-contract edits with UI polish,
defeating per-milestone gates and making a failed harness ambiguous; (2)
carry every intermediate diff in context for the whole run — the opposite of
token-conservative; (3) leave no clean commit boundary to bisect. Four
sessions each start cold but cheap: the review doc is the spec, the prompts
carry the file pointers, and nothing is re-derived.

C1–C3 (AppState extraction) intentionally has no prompt: per ROADMAP
Priority 3 it rides along — each session extracts only what the files it
already touches make natural, at that session's green boundary.
