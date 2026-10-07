# 063 — The learned disk detector stays on Core ML; a Core AI spike runs at the next detector change

**Date:** 2026-10-08 · **Status:** accepted (owner, by option on the decision sheet) · **Amends:** 014 (the runtime revisit), 048 (closes it)

## Context
The owner parked "Core ML vs Core AI" on 2026-09-23. The sheet `docs/archive/v5/coreml-vs-coreai-2026-10-08.md` (a draft, the supervisor's
check against Apple's documentation, and an independent second opinion) recommended staying on Core ML. He answered **a**.

## Decisions
1. **Core ML stays** for the bundled detector and for fine-tuned packages (the in-app writer produces `.mlpackage`; Core AI has no
   on-device writer). The load-time Neural Engine check stays.
2. **A spike runs at the next change to the learned detector (or the precipitate classifier on the Neural Engine, whichever is first)**,
   in this order: (1) is Core AI's model and specialization API available on macOS 27 (Apple's pages for `AIModel`, `SpecializationOptions`,
   `ComputeUnitKind` list no macOS); (2) a one-pattern Neural Engine placement probe; then, only if both pass, (3) placement, warm
   per-pattern time and scan-level detection parity at batch 32 with the same weights, placement confirmed in both runtimes. The runtime is
   reopened only if Core AI wins on all three and the fine-tune path has an answer.
3. **Correction to ADR 014**: "The ANE is reached only through Core ML" is no longer true as a statement about Apple's frameworks — Core AI
   documents a Neural Engine compute-unit kind — but it is a *preference*, and its macOS availability is undocumented.

## Consequences
No code changes. The spike's design is the second opinion's (sheet §"Independent second opinion").
