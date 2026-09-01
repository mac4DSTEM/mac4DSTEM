# CIF pair — core-crystal-02 + core-crystal-04 (2026-09-01)

Owner decision 2026-09-01 (open-items.md §Owner decisions, item 3): the CIF
pair joins v2. Scope: `Core/Crystal/CIFImport.swift` only. Gate: reproduce
first, then Gate B (independent refuter — **requested from the owner, not yet
run when this record was first written**).

## Reproduction (pre-registered, then run — first runtime evidence; the
## 2026-08-31 review was source-only)

Probe: scratchpad harness compiling the shipped `CIFImport.swift` with
`tools/cif-symmetry-test`'s own source list; inputs from the COD WS2 file
(5910003) the owner staged in `References/training_dataset/WS2.cif` plus a
minimal rock-salt MgO. Predictions written before running; all three
confirmed:

| Case | Predicted | Observed (pre-fix) |
|---|---|---|
| MgO, Fm-3m declared, no ops loop | admitted silently, 2 sites | **ADMITTED .cubic, 2 sites** — rock salt as the CsCl structure |
| WS2.cif, ops loop stripped | rejected by `verifyFamily` with a *misleading* cause | **REJECTED** — "no 2-fold axis along a … not actually hexagonal" (false claim about a structure that has one; the atoms just aren't all listed) |
| WS2.cif, last atom-loop token deleted | admitted, sulfur silently gone | **ADMITTED .hexagonal, 2 sites (W only)** |

Baseline control: the intact WS2.cif imports as 6 sites (2 W + 4 f S),
`.hexagonal`, before and after the fix.

Why `verifyFamily` cannot be the guard: MgO's two-site asymmetric unit is
invariant under both cubic generators, so the symmetry check passes it — only
the file's own declaration knows the list is incomplete.

## The fix

1. **`missingSymmetryOperations(spaceGroup:)`** — when a file declares a
   non-P1 space group (H-M/Hall symbol or IT number; CIF nulls `?`/`.` count
   as absent) and carries no expanding operations — no loop, an empty loop,
   or an identity-only loop — the import refuses, naming the declared group
   and the remedy. Declared P1, or no declaration at all, keeps the existing
   complete-cell path. A declaration that exists but cannot be read (a
   non-integer IT number) also refuses, quoting the raw value — guessing P1
   from an unreadable tag is the same silent assumption.
   DEVIATION noted inline: py4DSTEM delegates to pymatgen, which *derives*
   operators from the symbol; this importer has no space-group tables, so
   refusal is the honest alternative.
2. **`truncatedLoop(firstTag:columns:values:)`** — any `loop_` whose value
   count is not a whole multiple of its tag count refuses instead of
   floor-dividing the partial trailing row away. Applies to every loop, not
   just atom sites: a cut file is a cut file.

Behavioural edge recorded: an identity-only ops loop **with** P1/no
declaration previously went through `expand` (dedup could merge
within-tolerance sites); it now takes the wrap path, which keeps duplicates
for `CrystalModel`'s close-contact check to reject loudly. More honest, but a
behaviour change the refuter should look at.

Known residual, out of scope: stray tokens between a loop's last row and the
next tag are swallowed as loop values (pre-existing tokenizer property). If
they complete a whole row they still fabricate a garbage row silently; if not,
they now refuse as truncation (previously: silently dropped).

## Verification

- `tools/cif-symmetry-test`: 30 pre-existing cases unchanged and green
  (*first written as "24" — corrected by the Gate B refuter, who counted*);
  **5 new cases** — MgO no-ops (refuse, message names `F m -3 m`), WS2 asymmetric
  unit (refuse for the *real* cause), identity-only loop declared by number
  (refuse, names `No. 225`), declared-P1 full cell (admit control), loop cut
  mid-row (refuse, names `_atom_site_label`). All green post-fix.
- `mac4DSTEMTests/CIFImportTests`: **5 new tests** (refusal ×3 incl. exact
  Equatable payloads, P1-declared admit control, `?`-placeholder control).
- **Every new check broken before trusting** (2026-09-01):
  - M1 (floor-divide restored) + M2 (`declaredNonP1SpaceGroup` → nil):
    harness **4 distinct FAILs** (two admitted-wrong, one rejected-for-the-
    wrong-reason, one truncation admitted 3-site gold); unit suite fails
    exactly the three new refusal tests, exit 65.
  - M3 (message stops naming the group): harness **3 FAILs** on the
    message checks alone.
  - Restored after each; harness and unit green on the shipped tree.
- `tools/run-tests.sh unit`: **exit 0** on the final pre-review tree
  (2026-09-01, background run; the capture piped through `tail`, so the
  per-test count was not retained — exit status and the passing tail are the
  retained evidence; the next aggregate run recounts).

## Gate B — RAN 2026-09-01, verdict STAND WITH CORRECTIONS, all four applied

An independent refuter (fresh agent, briefed to refute, given the evidence
and the probes — not just the diff) reproduced all three pre-fix results
from `git show HEAD:` independently, confirmed `verifyFamily` structurally
cannot catch the MgO shape, and could not construct a legitimate file the
guards wrongly refuse (it tried Hall-only, `:H`-suffixed rhombohedral,
unchecked-tag-with-complete-cell, `stop_`/`global_` strays, and the common
two-column COD symmetry loop — which the parser handles correctly).

**Its paying-question answer: seven mutations of the fix survived the
original harness.** The sharpest (M8): the truncation guard can only ever
fire on multi-column loops, and a **cut two-column symmetry loop**
floor-divides a centering operation away — the resulting wrong 3-site FCC
**passes `verifyFamily`**, measured on the pre-fix importer. Corrections
applied in this session:

1. **Hardened harness adopted** — 8 refuter cases (Hall-only, H-M_alt-only,
   P-1 vs P1, corrupt IT number, translation-only ops must EXPAND,
   two-column symop loop intact + cut, one-stray-token cut). The refuter
   re-ran all seven surviving mutations against it: **each killed by its
   targeted case**, and the harness is green on the shipped importer.
2. **E1 fixed**: `_space_group_name_h-m_full` and `_space_group_name_h-m_ref`
   added to the checked tags (the same defect through an unchecked
   spelling), with 2 more cases — both verified red under the drop-the-tags
   mutation. Harness now 45 cases, all green.
3. **E2 recorded** as a residual (below).
4. The pre-existing-case count in this record corrected (24 → 30).

**Parity caveat the refuter added**: the DEVIATION's `crystal.py:335` cite
is exact, but pymatgen itself is not vendored, so "pymatgen derives
operators from the symbol" rests on outside knowledge of `CifParser`, not
on anything in `References/`.

## Not verified / residuals

- **E2, the honest boundary (refuter escape, recorded not fixed):** a non-P1
  declaration with a *partial* non-identity ops list (e.g. identity +
  inversion only under Fm-3m) still imports the same wrong crystal —
  detecting an incomplete list requires the declared group's order, i.e.
  space-group tables this importer deliberately lacks. Cheap partial
  mitigation if ever wanted: an IT-number → group-order table (230
  integers). In `docs/open-items.md`.
- On-screen import of a refused CIF (the modal path renders
  `errorDescription`; `CIFImportAppStateTests` pins the routing, but nobody
  has driven the new messages). Queued as a Track B row candidate.
- The WS₂ reference-shell mis-scale (ship-plan Step 1 item 2) is untouched —
  same subsystem, different session.
