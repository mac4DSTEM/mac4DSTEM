# E1 — pooled spectra by phase, diffraction group and drawn region in the Spectroscopy room: pre-registration (2026-10-08; nothing built)

A new item: WP3 built `PoolBuilder`, `MaskTransport` and `RegistrationRecordM2` (Core, tested, called by nothing); E1 wires them into the
room. Scope: ADR 061 §1 (V5-8 b). **Gate B**, not Gate D: pooled counts and their fits are new numbers; no existing number moves (the
lineage key is added only when non-nil, `QuantificationStep.swift:44-47`) and no cause is unknown. H7 guards that; if H7 fails the item
stops and a Gate D diagnosis is registered. Drafted 2026-10-08 (Sonnet), Gate B review of the draft (Haiku, read-only: PASS WITH CHANGES,
six blocking, all taken below). **Owner cards E1–E6 are open** (`owner-decisions-2026-10-08-e-pooling.json`); this text assumes each card's
recommendation, and a different answer is folded in here before any code. Building starts only after his answers.

## What is pooled, and how
- A pool is the exact `UInt64` channel-wise sum of the spectra in a spectrum-grid mask (`SpectrumImage.sum(mask:)`); no weights.
- Membership comes from a 4D-grid label map moved by the registration through **`MaskTransport.pools(transported:)` for phase and group
  alike**: a partition, a spectrum pixel joins a label when that label covers more than 1/2 of it, exact ties join none (the WP3 round-3
  rule, inherited, not set here). `pool(scanMask:)` (which admits ties) is not used by E1. Phase labels: verdict `.indexed`/`.matrix` with its
  `phaseIndex`; group labels: `groupOf == g`, `-1` unlabelled. Per-object pools are not in E1 (card E2 a: all objects of a phase are the
  phase pool); if he picks E2 b or c, per-object pools are registered with a memory bound (one class per object costs classes × pixels doubles).
- The only registration the app states is the identity of a GMS joint attach (`sameScanAs4DCube`, `SpectrumImageOpening.swift:165`), shown as
  "same scan, identity; no lag check" (card E5 a), stored on `SpectroscopySession` and passed to `quantificationParameters`
  (`SpectroscopyQuantification.swift:32`).
- Refusals, each a sentence and no spectrum: no registration; the product's **width and height** differ from the registration's scan
  width/height (`PhaseMap.width/height`, `PhaseVectorMatching.swift:365-366`; `DiffractionEmbedding.Result.scanWidth/scanHeight`,
  `DiffractionEmbedding.swift:88-89`), not only its pixel count (`MaskTransport.swift:134` checks the count alone); the spectrum grid
  differs from the image's; the membership is empty; the registration is singular.
- A region kind per source (`SpectroscopyRegion.Kind` gains `.phase`, `.group`, `.notIndexed`; the enum is closed, `SpectroscopySession.swift:64-73`);
  `mask(of:)` returns the pool's mask for them, never nil (nil means "every pixel", `:175-178`).
- Badge: the room sets `RegionSettings.phase` and a per-region badge from `PooledSpectrum.validation` through `PooledSpectrum.isUnvalidated`
  (`validation == "none"`, `PoolBuilder.swift:45`), not through `ValidationState.isUnvalidated(nil)` (which reads nil as unvalidated,
  `SpectroscopyLogic.swift:334-336`). Phase and not-indexed pools carry `"none"`; group pools carry nil (diffraction groups record no
  validation) and are never called validated.

## Hypotheses, predictions and the observation that refutes each
Chain tests (H1, H2, H4, H5, H8) run twice: through an **injected non-identity record** (`RegistrationTests`' 4×4 → 2×2 mirrored bin,
`RegistrationTests.swift:19`, injected at the controller seam; the app cannot create it) and through the identity.
- **H1 (a pool is the channel-wise sum).** On a non-square 5 × 3 image, dense and sparse (`SpectrumImage.swift:113,145`), the pool through
  labels → transport → session region → `compute` equals the hand sum of the member spectra in every channel, as integers.
  **Refuted** by any channel off by one, or dense ≠ sparse.
- **H2 (phase pools partition).** Phase pools are pairwise disjoint and pools + not-indexed remainder = whole map, channel by channel; on the
  mirrored bin the tied pixels land in no pool and in the remainder. **Refuted** by any overlap or unequal channel.
- **H3 (membership follows its source).** Under identity each phase pool's mask equals `MaskTransport.mask(phase:in:)` (`:218`) bit for bit,
  each group pool's equals `groupOf == g`, with one `groupOf == -1` and one `.notIndexed` position keeping a stale `phaseIndex`. **Refuted** by any pixel.
- **H4 (refusals refuse).** Each refusal returns its sentence; a spy `SpectrumImageSource` records that `sum(mask: nil)` is never called for a
  pool region. Cases: 4 × 3 map on 5 × 3 image; **3 × 5 map on 5 × 3 image** (same count); empty pool; singular record. **Refuted** by any spectrum.
- **H5 (quantifying a pool = quantifying its sum).** `PooledQuantifier.run` fed by the room for pool P and fed the hand-summed counts with the
  same method agree in every row field exactly; the pixel count is the pool's. **Refuted** by any field.
- **H6 (provenance).** `quantificationParameters` carries the registration and `region_kind ∈ {phase, group, notIndexed, drawn}`; the per-region
  badge function returns unvalidated for phase/not-indexed pools and not for group or drawn pools. **Refuted** by either.
- **H7 (no existing number moves).** With no 4D product, and with one present but a drawn or whole-map region selected, the spectrum, maps,
  fit, results table, lineage parameters and Spectrum CSV export are byte-identical to outputs recorded from the pre-change build on the
  `--demo-spectrum-fixture` image and `demo-edx-tiny` (the recording command is committed with the fixture). **Refuted** by any byte.
- **H8 (never stale).** `PhaseMappingProduct.publish` (`:611`) and `DiffractionGroupsProduct.publish` (`:70`) gain an additive generation id;
  on a change the room's product hook calls `cache.forget` and the selected pool is recomputed, or removed with a sentence if its source
  vanished; pins taken from a pool and Auto ID outcomes for it are cleared with it. **Refuted** by an old spectrum, pin or outcome shown.
- **H9 (truth on the simulated joint file; precondition: it attaches with `sameScanAs4DCube` true).** (a) Gated: the pool of each truth
  region's mask equals `realised_total_eds_counts` as integers (`sim_edx.py:594`; per-phase truth = sum over regions with that phase name).
  (b) Reported, no bar: phase-map vs truth agreement and the k-free Mg/Si ratios of the β″ pool with Garwood intervals
  (`CountingInterval.garwood`). A miss in (a) stops the item; (b) is printed either way (threshold rule).

## Tests first, and the mutation each must go red on
1. `SpectroscopyPoolsTests` (new, pbxproj + inventory manifest): H1, H3. Mutations: weight by overlap (red only on the mirrored record);
   swap nx/ny; drop the last pixel; `groupOf` off by one; drop the verdict condition.
2. H2. Mutations: build phase pools with `pool(scanMask:)` per class (a tie enters two pools); leave the remainder out.
3. H4. Mutations: `mask(of:)` returns nil for a pool region (spy sees `sum(mask: nil)`); drop only the width/height check (3 × 5 case red).
4. H5. Mutations: pass `nx*ny` as the pixel count; normalise the counts.
5. H6. Mutations: badge from `ValidationState.isUnvalidated` (group pool red); omit `registration:` in `quantificationParameters`.
6. H7. Mutation: route a drawn 3 × 2 rectangle at (1, 1) through the pool path with a one-pixel dilation.
7. H8. Mutations: skip `cache.forget`; keep pins on a source change.
New Swift files: `PoolCatalogue.swift` (Session) and the test file, each in the pbxproj and the inventory manifest.

## On screen (only what the owner pictured)
The Source picker lists pools in sections (card E3 a): Drawn · Whole map · Phases (with Not indexed, card E4 a) · Groups; before a phase
map exists, one disabled line "Run phase mapping in Crystal Maps to pool by phase." A pool behaves like a drawn region; the Phase row and
badge show for phase and not-indexed pools. Nothing else is drawn (card E6 a). No frozen-shell file is touched.

## Ship rule
H1–H8 survive on the registered fixtures; unit + core + inventory green from a dated run reconciled against `func test` names; every
mutation above red; H9 (a) holds; an independent read-only refuter (another model) agrees from the logs. Lands unverified on screen
(ADR 055), its rows added to "Unverified on screen", owed a drive on the joint simulated file with a phase map.

## Not in this item
Per-object pools (card E2); excess over the matrix (scale undefined); f and the registration residual; channelling angle I (a new
misorientation function); K and dose (no probe current, no per-pixel live time, ζ not in the menu); H's outline and its Crystal Maps half;
J; B* and the per-phase score; D; a typed or landmark registration and the lag check; live-time normalisation between pools.
