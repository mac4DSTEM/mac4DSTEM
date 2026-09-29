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

## Amendment — Gate B, 2026-09-30 (L1)

An independent Gate B on the L1 reader/writer found two defects and four gaps; the rules they led to:
- **An unknown lineage `version` reads as v1** (the record only) with a named note — never a refusal of the sidecar,
  since the min-reader marker promises the rest of the file is readable.
- **The writer validates what it writes** (the same R8 checks the reader applies) and writes the lineage only when its
  projection equals the record written beside it; otherwise it omits the lineage and says so. An unvalidated lineage
  string is never carried forward.
- `next_id` is bounded (≤ 1 000 000) and never overflows; pruning at 2 000 nodes keeps the projection's order. The
  4 MiB cap is checked after the read: HDF5 reports a variable-length string's heap id, not its length
  (`H5Aget_storage_size` = 16 for a 5 MiB string, measured), so the read is bounded by the file's own size.
- A calibration-only session exports no "recipe not carried" note (an empty projection is not an omission).
- R5's example: nil fields are omitted, not written as `null` (byte-stable either way; the code omits).

## Amendment — Gate D, 2026-09-30 (L4, rewind; decided by delegation, overrule on sight)

Two independent refuters (Gate D) found that R4 as written ("ancestry plus descendants wholly on it") left the
path claiming states the app does not apply. The rules they led to:

1. **Format.** The rewound active path is a fact the nodes cannot give, so the lineage JSON gains an optional
   `active` key (node ids, node order). It is omitted whenever the fold gives the same set — every file
   written before L4 is byte-identical — and refused when empty, naming an unknown id, or repeating one.
   `version` stays 2; a build without L4 that reads a saved rewind sees a projection that disagrees with the
   record and reads the file as v1 with its named note (R7). *Alternative:* a session-only rewind (lost on save,
   and the record written beside it would disagree with the lineage).

2. **Kinds outside the target's ancestry stay on the path.** The path is the target's ancestry, its descendants
   wholly on it, and the node every other kind holds now (a calibration, a virtual image) unless that node rests
   on a run that leaves the path (a Q scale measured on the newer peaks). Calibration and unrelated products do
   not go stale because disks were rewound, and the next run records the edges of what it actually used.
   Settings are restored for the ancestry, the target and every node the rewind brings back; nodes that stay keep
   their live control. *Alternative:* ancestry only (R4 as first written) — takes an ellipse off the path while
   its value stays applied, a false lineage.

3. **A run after a rewind never collapses (R3) into a node that is not the newest of its kind.** It branches,
   so the run the user went back to keeps its settings. Unrewound, the active node of a kind is always its
   newest, so nothing changes there.

4. **Refuse rather than mislead.** A rewind refuses, by name and before any control changes, when
   (a) the origin fit in use is not the one the run stood on — a fit cannot be restored, only its mean is
   recorded; (b) a node of a kind that a re-runnable step on the path lists as an input was made *after* that
   step, is applied now, and is not among the step's recorded inputs (an ellipse fitted after the strain): the
   next Run would compute with it and the graph would say it did not. Calibrations and exports are exempt (they
   are not re-run); (c) the recorded disk detection used a probe kernel that is not stored (a vacuum ROI or a
   separate vacuum scan), or the file's own probe that is not the one loaded; (d) an ACOM step's scale is not the
   scale that would be in force; (e) the step's detector frame is not the session's. A synthetic kernel is rebuilt.
   *Alternative for (b):* take the held node off the path and say so — rejected: the live value stays applied
   either way, so the path would still not describe what runs.

5. **Recording.** A manual-basis strain also records the basis it indexed with (`input_g1_x` … `input_g2_y`);
   the rewind restores those, replay keeps using the resolved ones. The frame map classifies them as lengths.

**Residuals, named not fixed.** An origin re-fit with identical settings still refuses earlier rewinds (nodes,
not values, are compared). The synthetic kernel's radius is not compared. A Q scale or phase-mapping node that a
path member lists but that left the path is not checked beyond the ACOM scale guard. The lineage still has no
`calibration_rotation` kind and no External edge for a trained detector model; a hand-typed Q is recorded with a
`peaks` edge it did not consume. "Re-run stale steps" is not offered: the replay executor is the promote path. From the third look (Fable): the held-kinds fill is
order-blind within one pass — with o d1 s1 e1 s2(used e1) d2 s3, a rewind to d1 lets s1 win "strain" and then refuses
for e1, though s2 is a consistent strain on d1 (traced, not executed); and a rewind to a detection refuses for a strain
it would merely bring back, so d1's disks alone cannot be returned to without clearing the ellipse. Both refuse, neither
misleads.

**Gates.** First rework: 249 passed, exit 0; 12 new tests red on three mutations. Second round (the two refuter
fixes): 170 passed, exit 0; with the `appliedSince` refusal removed three lineage tests red, with `input_g*` dropped from
the frame map the binned-view plan test red (2026-09-29, sessions 85a5f653 `l4-g2`, `l4-h2`, `l4-mA..C`, eb2a2d51
`me/mut.log`, exit 65).
