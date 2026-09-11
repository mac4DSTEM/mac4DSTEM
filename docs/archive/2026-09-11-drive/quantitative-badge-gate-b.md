# The Quantitative badge fix that did not work — Gate B, 2026-09-11

A fix was written for the badge defect (`open-items.md`), taken through five
tests each broken by a named mutation, and **rejected by Gate B**. It is
recorded here because the refutation established the real mechanism, which the
original diagnosis had only half of, and because the next person to attempt
this needs to know which four assumptions are false.

The fix was **reverted**, not shipped. Shipping it would have looked like a fix
and changed nothing — which is worse than the open defect, because it stops
anyone looking again.

## What the fix did
`ResultExport.originFitProvenance` gained `origin_supports_metrology`, the
verdict of `Calibration.originSupportsReciprocalMetrology`; and a new
`ProductQuantitativeStatus.forProduct(...)` in `Core/` downgraded
`.quantitative` to `.exploratory` when that key was `"false"` and the kind was
in an `originDependentFamilies` list.

## Why it did not work — the reproducing observation
`AppState.publishProduct` composes provenance from
`currentScalarPersistenceMetadata.provenance` merged with `extraProvenance`
(`AppState.swift:295-300`). The **strain branch** of
`currentScalarPersistenceMetadata` (`ResultExport.swift:1566-1601`) builds its
dictionary from `map.diagnostics` plus `strainFrameProvenance` and **never
merges `strain.originProvenance`**.

Verified independently, not taken on the refuter's word:
`grep -rn originProvenance` over `mac4DSTEM/` shows the snapshot taken at
`AppState.swift:4965` (`strain.publish(map, originProvenance:)`) has **exactly
one consumer in the tree** — `ResultExport.swift:516`, inside
`scientificBundleMaps()`. Every on-screen path and every sidecar write misses it.

A probe mimicking `applyStrainDisplay` published a strain product with the
verdict set to `"false"` and read the badge back as **`quantitative`**. The
owner's defect reproduced unchanged with the fix applied.

## Four assumptions in the fix that are FALSE — each checked here
1. **Three of the six `originDependentFamilies` entries are dead strings.**
   `local_lattice` and `matched_template` are OVERLAY kinds
   (`AppState.swift:708, 720, 5425`); `disk_detection` is a REPLAY-STEP kind
   (`AppState.swift:4777`, `ProductWorkflow.swift:186`). None is ever a product
   `kind`. Only `strain`, `dpc`, `idpc` are real — and none of the three has the
   plumbing.
2. **`virtual_detector` is not a product kind either.** The app publishes
   `virtual_\(shapeMode)` — `virtual_circle`, `virtual_annulus`,
   `virtual_rectangle`, `virtual_point` — with units `"intensity"`
   (`AppState.swift:3442`), which `quantitativeStatus` already resolves to
   `.relative`. The deliberate exclusion, and the test pinning it, protected a
   (kind, units) pair the app cannot produce.
   `SessionCalibrationTranslationTests.swift:91` already pins the real answer.
3. **ACOM is the ONE family whose provenance genuinely carries the verdict, and
   the fix excluded it.** `ACOMRunSemantics.provenance` merges
   `originProvenance` (`ACOMWorkflow.swift:145-150`) and the ACOM branch of
   `currentScalarPersistenceMetadata` keeps it (`ResultExport.swift:1603-1606`).
   ACOM re-centres every Bragg vector on the origin. It was the one place the
   gate would have worked.
4. **The `publishRestoredProduct` change was unreachable.** Every sidecar this
   app writes already carries `quantitative_status`
   (`ResultExport.swift:1759-1763`), and that value wins.

## Why the tests did not catch any of it
All five called `AppState.quantitativeStatus(..., provenance:)` directly with a
hand-built dictionary. **Not one asserted on `publishedProduct?.quantitativeStatus`
— the value the screen and every export actually read.** Two mutations therefore
survived the whole suite: deleting the `origin_supports_metrology` emission
outright, and dropping the `provenance:` argument at the publish site. Either
leaves the app behaviourally identical to the unfixed build.

This is the lesson to carry: a test that calls the decision function directly
proves the decision function works. It proves nothing about whether the decision
is reached.

## What the real fix has to be
Bigger than a badge. **Products do not carry the origin they were computed
against** — strain takes a snapshot nothing reads, DPC takes none at all, ACOM
alone is wired. A gate on the badge cannot work until the products carry the
fact. Each of these is a hypothesis and must be broken before it is trusted:
- merge `strain.originProvenance` into the strain branch of
  `currentScalarPersistenceMetadata`;
- give DPC a snapshot site before giving it a gate;
- add `acom` to the gated families, and establish how it interacts with
  `productStatus`, which already returns `.exploratory` for a non-physical scale;
- use REAL product kinds, verified against the `kind:` strings the app passes to
  `publishProduct`;
- and write the assertion on `publishedProduct?.quantitativeStatus`, which is
  the only shape that would have caught any of this.

## Also narrowed, and still open
`originSupportsReciprocalMetrology` may be the wrong predicate for strain in two
directions. `originFitIsSane` returns true VACUOUSLY when `origin` or
`probeRadius` is nil (`Calibration.swift:624-627`), so a `.recordedMean` origin
with no per-position maps records `"true"` — a false pass. And when a displaced
origin does not break indexing, `indexed_fraction` and
`local_residual_median_pixels` — already on the product — are direct evidence the
map survived, which a gate on the INPUT ignores — a false downgrade.
