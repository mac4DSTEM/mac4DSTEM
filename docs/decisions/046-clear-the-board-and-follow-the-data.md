# 046 — Clear the board; workspaces follow the data (Bragg Disks, Crystal Maps, Reconstruction)

Dates: 2026-09-30

Status: decided by the owner; the workspace change is built in a polish session and driven before it counts as done.

## Decision

**Lanes** (the board-clearing step 2, `ROADMAP.md`): on-device **training is kept** and comes first after the polish;
the **lineage graph is kept** — a real graph with rewind, better than today's linear Lineage pane, pre-registered
before any code (the session-file format with step ids and input edges comes first, the owner's decision);
**volumetric density is parked** (areal density, edge-corrected under ADR 045, is what the app reports);
**β″ orientation maps are parked** (orientation mapping stays cubic and hexagonal; phase mapping's known variants
already label the β″ variants); **the full Thronsen reproduction (A3) is retired** (A3a's reference tooling stays in
`tools/` as a yardstick). The polish sessions put reliability and correctness of what exists before anything new.

**Workspaces** (Frozen Shell, the owner's accepted picture — option A of the 2026-09-30 mock):
Prepare · Imaging (virtual detectors, **diffraction groups**) · **Bragg Disks** (detection, labels, training) ·
**Crystal Maps** (strain, orientation, phases and precipitates) · **Reconstruction** (DPC, parallax, ptychography) ·
Results. "AI Analysis" and "Phase" (as a workspace name) go.

## Why

Clearing the board means closing what is done and retiring what is no longer wanted, not pushing away wanted features;
the owner kept two and parked two on their prerequisites. The workspace names say what each does, in the order the
work happens; "Phase" meant phase contrast beside a workspace mapping crystal phases; "AI Analysis" held vector
matching and PCA, neither machine learning; strain, orientation and phases all consume Bragg disks, and training
lives with the disks. Six workspaces, as today, so the window's width budget is unchanged.

## Governs

`WorkspaceNavigation` / the sidebar (Frozen Shell, changed against this picture only); the rooms' placement.
Session files keep their internal room identifiers, so saved sessions open unchanged. Rejected: B (every map its own
workspace, nine entries) and C (rename only).
