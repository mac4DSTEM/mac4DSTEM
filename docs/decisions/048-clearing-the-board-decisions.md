# 048 — Clearing the board: training on MPSGraph first, the C3 flow, T4 as a quantity, hardware waits

Dates: 2026-09-30

Status: **accepted by delegation** (owner, 2026-09-30: "clear the board by yourself, no further input from my side") —
every item is overrule-on-sight. Evidence: `archive/v4/c25-training-memory-2026-09-30.md`, the C3 pre-registration
(`archive/v4/c3-training-preregistration-2026-09-30.md`), `archive/v4/s10-s11-gateD-2026-09-30.md`.

## Decision

**Training runtime (C3 D2): MPSGraph first, MLX the measured fallback.** MPSGraph is a system framework (zero bytes,
autodiff, the detector graph is 39 ops); MLX would add ≈ 100 MB of Metal library to an 11 MB app — against the lean-app
directive and "pure macOS". Before any app code, an MPSGraph mirror must pass C2's criteria 1–2 in `tools/` (forward on
the GPU within the MLX mirror's 0.0027 of the shipped heatmap; a loss curve matching C2.5's) and fit C2.5's 2 GB bar.
If it fails, MLX (C2/C2.5 measured: micro-batch 2 × 4 accumulated, bf16, 1.48 GB) is used in a separate package.

**The C3 flow (D1, D3–D9, as pre-registered):** training in-process from a local package the `core` lane never sees;
30 % of positions held out by a position hash (the minimum N measured, never guessed, and always shown); always
fine-tuned from the bundled weights, judged against the active model; a fixed recipe (lr 1e-5, flips/rot90 on training
positions, steps from an inner split, no early stopping); one active model app-wide, every run records which; offered
only if ≥ on recall AND precision and > on one (a tie is not offered — narrower than ADR 043's "at least"); a
"judged on N held-out positions of <dataset>" badge; Core ML for every model (ADR 014's revisit: Core AI has no
on-device writer). The weights reach the Neural Engine by the on-disk package route (1.00× speed). The ANE only runs
the model; training is on the GPU.

**T4 (θ′ edge-on speckle):** reported as a measured quantity, per ADR 040's own "ship the quantity" clause and S10's
recommendation — 7 raw spurious objects, 3 of them 1–2 px from truth needles at the stride-3 truth's resolution, 4
inside the published methods' 0–5 range. Phase mapping stays **unvalidated** (CLAUDE.md: until it passes on a dataset
with truth); candidate B (noise hit) runs next; the library's stale Laue-spacing comment is corrected.

**Hardware:** the 28 GB `--parity` run and the parallax/ptychography drive need more than this 8 GB Mac; their lane
stays on the board as "waits on hardware" — the one lane a session cannot clear here.

## Why

The owner delegated the sitting; each choice follows the record (lean app, pure macOS, ADR 043, CLAUDE.md's threshold
and unvalidated rules) and is reversible.
