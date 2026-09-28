# 043 — A fine-tuned detector is judged by detection on held-out labels, not by heatmap equality

Dates: 2026-09-28

Status: live. Owner's choice (option 1 of three) after C2 failed as registered
(`archive/v4/c2-mlx-spike-2026-09-28.md`). Supersedes criteria 1 and 3's heatmap bars (max |Δ| ≤ 1e-2) in
`archive/v4/ondevice-training-research-2026-09-28.md` for every step after C2; C2's own verdict stands as recorded.

## Decision

A detector the user fine-tunes in the app is accepted, and runs on the Neural Engine, on what it detects,
not on whether its heatmap equals the training framework's pixel by pixel. The ANE's fp16 error moved the
shipped weights' heatmap by 0.0355 and the fine-tuned weights' by 0.0591 on the 16-pattern fixture, and it
varies with weights and inputs, so no heatmap bar below it can pass and a bar set from one fixture would be a
threshold measured once.

The rule C3–C5 build to (details are the C3 design session's; overrule on sight):

- **Held-out labels decide.** The user's labels are split deterministically before training; the model never
  sees the held-out part. Scored at the shipped match rule (2 px, `evaluate.py`'s acceptance), through the
  app's own detection path on the runtime it will ship on (the ANE).
- **Non-inferiority against what it replaces.** A fine-tuned model is offered only if its recall and its
  precision on the held-out labels are each at least the currently active model's on the same labels, and
  both numbers are shown to the user. Otherwise the app says so and keeps the active model.
- **Runtime parity is at detection level.** Where two runtimes of the same weights are compared (MLX vs the
  ANE package, in tests and fixtures), they must accept the same peaks within the match radius, not produce
  equal heatmaps.
- **The number carries its dataset.** A pass is a property of the held-out labels it was measured on and is
  recorded with them (CLAUDE.md's threshold rule); it is never promoted to "validated" for other data.

## What this does not settle

- The training memory (MLX peaked at 2.78 GB at batch 8, over the 2 GB bar) and criterion 4 (the app's
  Swift path) are still owed before C3.
- How few held-out labels are too few to decide anything: to be measured, not guessed.
- Core ML vs Core AI (ADR 014's revisit) for models we train ourselves in Python.

## Governs

ROADMAP track C (C3–C5); `tools/mlx-training-spike`; every parity fixture for a fine-tuned model.
