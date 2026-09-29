# 047 — Lineage: session record v2 (step ids, input edges); rewind restores parameters and marks stale, never deletes

Dates: 2026-09-30

Status: **accepted by delegation** (owner, 2026-09-30: "clear the board by yourself, no further input") — every R-item is overrule-on-sight; the alternative is named. Mock: `docs/archive/v4/lineage-graph-mock-2026-09-30.html`.

## Context

Today: `SessionReplayRecord` (one step per kind, a re-run overwrites in place, `invalidating:` deletes strain/ACOM),
per-product `provenance`, `stalenessVerdict`, and a chain in the Lineage pane (`UI/BottomWorkspace.swift`). Missing:
step ids, input edges, a second run of a kind; calibration, phase mapping and objects are not steps. ADR 046 kept it.

## Decision (recommended)

**R1 One graph, nodes are runs.** A node is one completed run: `id`, `kind`, `parameters` (the same flat
string-to-string snapshot `recordReplayStep` writes today), `inputs` (edges to the nodes it consumed, with a role:
`peaks`, `calibration`, `phases`, `objects`), `external` (inputs from outside the session: a CIF by file name and its
`contentFingerprint`, never an absolute path), its own `frame` (bin, crop), `recorded`, and `product` (the result node
name when that run's product is saved). New node kinds: `calibration_origin`, `calibration_ellipse`, `calibration_q`,
`phase_mapping`, `precipitate_objects`, and `export` (a sink: format and file name, not rewindable).
*Alternative:* a separate history list beside a data graph — two structures that can disagree.

**R2 Ids.** `s1, s2, …` from a `next_id` counter in the file, never reused, readable in the pane and in provenance.
A saved product's provenance gains `lineage_step = "s7"`, which is how a displayed map finds its node.
*Alternative:* UUIDs (merge-safe across files, 36 bytes each, unreadable); no merge is planned.

**R3 Branching and the collapse rule.** A re-run of kind K whose inputs equal the active K node's inputs **replaces**
that node when it has no children and no saved or exported product (slider exploration stays one node — the v2 S5
"not a keystroke log" rule). Otherwise the run is a **new** node and becomes active; the old node and everything built
on it stay, drawn as another branch. So a rewind followed by any run branches, and today's `invalidating:` deletion
becomes "off the active path". *Alternatives:* every run a node (bloats; the log S5 rejected); no branches (linear,
truncating like undo — loses work).

**R4 Rewind to X, precisely.** (1) The controls of X's kind and of every ancestor's kind take those nodes' parameter
snapshots (the `SessionControlRehydration` route; calibration values included). (2) The active path becomes X's
ancestry plus X's descendants whose ancestry is wholly active. (3) Every product in memory whose node is not on the new
active path is **marked stale** (the existing stale badge and "Computed with different …" sentence) and stays shown.
(4) Nothing is deleted and nothing recomputes; Run does that, and rewinding back to the old branch is always possible.
The pane states the consequence before the click ("Strain, Phase map, Objects become stale; nothing is deleted").
*Alternatives:* delete downstream (irreversible; an ACOM run can take an hour); recompute on rewind (a silent long
run behind a navigation gesture) — offered instead as an explicit Re-run in L4.

**R5 Format.** One root attribute `mac4dstem_lineage` on `/braggvectors_root`: a variable-length UTF-8 JSON string,
sorted keys, dates in seconds (`SessionReplayRecord.jsonString`'s conventions, byte-stable on re-encode):
`{"version":2,"next_id":12,"head":"s9","nodes":[{"id":"s5","kind":"disk_detection","inputs":[{"step":"s4",
"role":"calibration"}],"external":[],"frame":{"bin":1},"parameters":{…},"product":null,"recorded":1790000000,
"source":"live"}]}`. `currentSchema` 6 → 7. The lineage is additive and safe to ignore, so
`mac4dstem_min_reader_schema` is unchanged (5 or 6 by the load specification): v4.0.0 still opens a v7 file.
*Alternative:* a `lineage` group with one subgroup per node (HDF5-native and browsable, but many small objects and a
second reader path to guard); JSON matches the replay record and the load specification.

**R6 The linear record stays, derived.** Every save also writes `mac4dstem_replay_record` as the projection of the
lineage: the active node of each replayable kind in id order. `ReplayPlan`/`ReplayRun` are unchanged through L3, and an
older build's promote-and-replay keeps working on a v7 file. An old build that re-saves the file drops the lineage
(its writer does not preserve unknown attributes); the file then reads as v1 — stated, not prevented.

**R7 v1 sidecars open read-only.** No `mac4dstem_lineage` but a replay record → nodes synthesized **in memory**,
`source:"v1"`, ids in record order, `inputs` **absent** (unknown, not a chain): the pane draws them with order-only
connectors captioned "Recorded before lineage: order only" (absence is absence). Opening never rewrites the file (the
F1 rule); the first save writes v7 with those nodes still marked v1. If both attributes are present and the lineage's
projection differs from the record (a foreign or hand-edited file), the file is read as v1 with a named note, never
merged. *Alternative:* infer edges from kinds (strain ⇒ last disk detection) — asserts what the file never said.

**R8 Size and guards.** A node is ≤ ~2 KB (disk detection's ~15 keys is the largest); a typical session is 10–40 nodes,
20–80 KB, far under HDF5's limits (a VL string lives on the global heap, so the 64 KiB attribute-header cap does not
apply). The reader adds, for this attribute: a 4 MiB length cap, ≤ 2 000 nodes, unique ids, every input id present,
no cycle, unknown `kind` kept as an opaque node — each failure refuses by name (`malformedAttribute`), never a partial
graph; the single-VL-string check in `readStringAttribute` stays the first gate. Test fixtures stay tiny (a 4×4 scan,
16×16 detector, < 64 KiB) so the 1 MiB tracked-file guard never needs an exception.

**R9 Where it lives.** The graph replaces the chain in the bottom **Lineage** pane (ADR 034's debug-area slot, the
owner's "Output + a lineage graph, side by side"); a clicked node's detail is a trailing column inside that pane, not
the inspector (durable room settings) and not a window. SwiftUI `Canvas` for edges, a `Button` per node for focus and
VoiceOver; no AppKit. No Frozen Shell file changes. *Alternatives:* a Results tab (far from the work); a popover per
node (transient, cannot stay open while stepping through nodes with the arrow keys). **Owner:** `SessionReplay` holds
the live lineage (no new `AppState` storage); the type is `Core/Data/SessionLineage.swift` beside the record.

## Phased build — each driven, each test broken before it is trusted

| Phase | Builds | Gate |
|---|---|---|
| L1 | Record v2: `SessionLineage`, recording at every run site incl. calibration/phase/objects/export, R3, write/read R5–R8. No UI. | Not Gate D (no number moves); Gate B on the reader. Tests: re-encode byte-identical (`tools/load-spec-roundtrip` extended); projection equals today's record on every existing `SessionReplayTests`/`ReplayPlanTests` sequence (red if the `invalidating` mapping is dropped); a committed v6 fixture from the v4.0.0 tag opens, lineage synthesized with inputs absent, file bytes unchanged (`cmp`); a v7 file read as schema 6 restores; hostile attributes (array, number, > 4 MiB, dangling id, cycle) refuse by name. |
| L2 | A lineage list in Results (active path, branch count per node). | Waits for an empty "Unverified on screen" row. List-model unit test; drive. |
| L3 | The graph to the accepted mock: layered left-to-right layout (column = longest path from the load node), states by symbol. | Pure layout tests (no overlap, edges only rightward, active path on the top rows); drive at 915 and 1470 pt on the demo cube. |
| L4 | Rewind (R4) and an explicit Re-run of X's stale descendants through `ReplayPlanner`, with its refusals. | **Gate D** (a wrong restore moves a number): predicted outcome — detect d1 → strain, re-detect d2, rewind to d1, Run → strain bit-identical to s1's saved map; red when one restored key is perturbed; node count unchanged by rewind; independent refuter; drive. |

## Why

A graph that restores state needs ids and edges in the file first. Additive format, derived linear record and a
read-only v1 path change no saved session, older build or replay before L4; stale-not-delete keeps every run reversible.
