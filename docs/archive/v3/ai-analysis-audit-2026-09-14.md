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

---

## The status handoff of 2026-09-14 evening, moved here 2026-09-15

**2026-09-14 evening: the four queue items were taken, Gate B ran on all of
them, and it changed the answer on two.** Nothing is verified on screen.

1. **A second matrix grain was labelled as a candidate phase — FIXED.**
   `classify` never asked whether the MATRIX explains the surviving vectors, so
   2 250 positions of pure aluminium on [011] came back 100 % β″ [001]. The
   matrix is now offered every low-index orientation before a candidate label is
   allowed, with the in-plane rotation **derived at the position**. Grain B
   **100 % → 0 %**, precipitate recall unchanged at 96/96 and 108/108, indexed
   total exactly the 204 planted precipitate positions. **Three remedies were
   refuted before this one stood:** a whole-scan rotation fit (carried [-1 1 0]
   at 100° where the grain needs 130°); seeding rotations on the three longest
   vectors (spurious maxima sit farther out — three of them took the catch rate
   to 0 %); and requiring only "at least as many" matched vectors (a 49-axis
   search then stole 26.5 % of three-vector precipitates). It is gated by a new
   Part E in `tools/phase-vector-matching`, whose first check reproduces the
   defect so the second cannot be vacuous.
2. **The ellipse fit's 10 % ellipse — REFUSED, on the owner's decision.** Four
   statistics were measured; three were refuted, including the azimuthal
   contrast that had shipped earlier the same session. The reason none works is
   not a missing idea: a three-grain annulus and a legitimate six-azimuth ring
   occupy the same 12 of 36 bins and differ in nothing a statistic can read,
   only in the answer. The guard is therefore a **degeneracy bound** — `fit1D`
   needs five sixths of the azimuthal bins, not a third — and it refuses the
   sparse legitimate case too, which is stated rather than hidden. Seven new
   gated checks, every fixture circular by construction so a reported a/b is a
   defect: 3 grains refused (a/b 1.685), 12 grains and two spotty rings fitted
   isotropic. **A flag for the sparse case is owed**, at the owner's direction.
3. **The zone-axis chance floor — PARTLY.** The expectation is now computed from
   the same definition the matcher's guard uses and shown in the panel. **It
   does not mark the ⟨112⟩ at 8 % that motivated it:** Al's ⟨112⟩ entries carry
   12-16 vectors, not the 48 the cap allows, so 8 % clears five times chance.
   Said plainly in `open-items.md` rather than claimed as fixed.
4. **The Prepare panel's Clear Calibration — LANDED.** Written by a delegated
   agent in an isolated worktree. Gate B found its confirmation dialog false
   ("maps you have already computed are kept" — the orientation map and parallax
   are discarded); the dialog now says what actually happens.

**Overnight 2026-09-14/15, diagnosis only, nothing in `Core/` touched.** Two
Gate D diagnoses ran with their experiments and independent refuters. The R–Q
rotation one survived, with two of its numbers corrected and one of its
arguments demoted. **The ACOM one was refuted outright:** I blamed py4DSTEM's
intensity power, and the cause is that the demo cube exports reflections at
kMax 0.9 while the plan is built at 1.2, so the bank predicts rings the data
cannot contain and the matcher rationally infers a tilt. That refuter also
found a separate live defect — 26 of 200 templates fail to recover themselves
at an off-grid rotation — and four undocumented py4DSTEM deviations. Nothing
was fixed, by choice: a fix is not a thing to leave unreviewed.

