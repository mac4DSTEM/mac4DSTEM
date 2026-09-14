# AI Analysis audit, 2026-09-14

Moved verbatim from `docs/status.md`'s handoff on 2026-09-14 (evening) once
the demo-cube review superseded it as the newest paragraph. The findings it
records live in `docs/open-items.md`; the fixes are in commit `94c4d29`.

**Audited 2026-09-14, unattended, by three independent readers and a
refuter; nothing seen on screen.** The AI Analysis room only. Fixed, each
with a test broken first on a clean bundle: `Crystal.reflections` now tiles
each index by `ceil(kMax·|aᵢ|)` — py4DSTEM's shortest-direction bound loses
reflections on oblique cells (48 at β = 115°, 198 at 125° on the β″ shape;
none for Al or the shipped β″, sets identical) and is an inline `DEVIATION`;
`tools/phase-vector-matching` builds its own in-plane frame, so the L3
blind spot is closed — a handedness flip in `detectorBasis` now fails A4 and
P2 (measured, 2 of 27 red) where it passed 27 of 27; the embedding suite pins
`coordinates` against its own reference (both Gate B mutations red);
`explainedVariance` is clamped at 0; `phaseSignature` follows the list order
because colours do; the zone-axis fit carries the dataset-epoch and
slot-identity guards its sibling had. Recorded, not fixed: three precipitate
findings (dark ridges register through their flanks; a negative peak
collapses an object to 1 × 1; a NaN neighbour passes the maximum test) and a
grouping-name fallback outside the scope — `open-items.md`. Could NOT be
faulted by reading or probing: the PCA maths, binning, k-means seeding and
empty-cluster handling, the matcher's prune, score, chance guard and
refusals, the zone-axis parser on every spelling tried, the Evidence stride,
the hatch, and every `validation: "none"` label. Phase mapping is still
UNVALIDATED; step 3 has still not run. **Gate B ran** (a fresh refuter,
70 tool uses, byte copies instead of `git restore`): the tiling fix was
re-derived from this repo's own matrix helpers and checked on triclinic,
hexagonal and β = 170° cells, with byte-identical sets to the old code on
every shipped cell; of its four frame mutations, the true mirror and the
swapped projection failed A4 and P2, a negated e1 passed because it is a
rotation, and a flipped `rotate` sign failed P5c only — as the Al [001]
symmetry predicts. Two of its claims were tested rather than taken: the
slot-identity guard did match on a reusable model id and now requires
`isMatrix` too; the per-component basis rescale it called invisible to the
coordinates assertion turned the eigenpair test red (`pvm-run6-mutE.log`),
because λ there is computed from the published row. Live markdown is UP
(6 076 → 6 087) and the reason is stated as the rule requires: three closed
entries moved to the archive and four new findings were recorded; nothing
live was found stale enough to delete. Committed 2026-09-14; the owner pushes.
