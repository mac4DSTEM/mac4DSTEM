# Precipitate follow-up rooms, 2026-10-22: variant map (task 40), N_V (task 41), composition and strain per object (task 42)

A cloud design pass (swiftui-macos skill), no build, no numbers claimed that need Swift or Python. It is the Mac brief for ROADMAP
tasks 40, 41 and 42 in mac4DSTEM. It extends `docs/design/rooms-2026-10-21.md` section 3 (the precipitate view) and builds on what
`main` has today: `PrecipitateObjectsSection` (inspector), `PrecipitateObjectsWindow` (the table, a Codable snapshot
`PrecipitateObjectReport`), `PrecipitateGlyphSet` and `PrecipitateGlyphOverlay` (ellipses on the panes), `PrecipitateTableSelection`
(the relay), `ThicknessEntry` plus `AppState.setPrecipitateThickness` (typed t ± σ, already in the lineage node and the CSV
provenance, **no inspector row yet**). Task 39 (objects on ImagoKit) is assumed landed or landing first; nothing below depends on its
numbers except the length column, which says so.

## 0. Decide first (Paul's), then the open questions

Paul's own, small: (a) the words "Variant" and "Direction" in the UI (recommended as written); (b) default map colouring by
**direction** (3 colours) with variant on demand (section 3.3); (c) the object table stays a window (the macTEM sheet-vs-window taste
item does not touch this app). Everything else is engineering and decided below, with these open for a veto:

| # | Question | Recommendation (built unless vetoed) |
|---|---|---|
| Q1 | Where does an object's variant come from? | Phase-map route first: the winning library entry per pixel (`PhaseVectorResult.entryIndex`: phase × zone axis × in-plane rotation) voted over the object's pixels, mapped to the nearest OR variant. ACOM orientations are the second source behind the same seam (`ObjectVariantSource`), not built now. |
| Q2 | When is an object "ambiguous"? | Two user-set numbers, recorded in the sidecar, never shipped cuts: the nearest-variant angle must be within a **tolerance** (default = half the library's in-plane rotation step, because no pixel can say more than its grid) and the object's pixel **agreement** (share of pixels voting for the winning variant) must reach a floor (default 0.5, "a majority"). Otherwise the object is counted under "Unassigned" with the reason, never forced into a variant. |
| Q3 | Which β″ axis is the needle, and how are the 3 directions named? | The needle is along Al ⟨001⟩ (D24). Direction = which of Al [100], [010], [001] the needle lies along, as the kit states it on each variant (`variant.needleAxis` or the variant's rotation applied to the β″ needle axis; confirm against DiffractoKit 0.10.0's CHANGELOG and Andersen 1998 — the Mac session reads, does not guess). The UI names directions in the **sample** frame as "[100]", "[010]", "[001]" and in a scan with beam ∥ [001] says "end-on" for the one along the beam. |
| Q4 | N_V formula | v1 = N_A / t (areal density over thickness), flagged on screen as assuming objects span the foil; the Underwood correction N_A / (t + D̄) is a later option once ADR 050's refutation is revisited. σ shown = the kit function's propagated σ; the help text says which terms it holds. |
| Q5 | Composition for tiny objects | An object needs at least **4 EDX pixels** after transport (user-set, shown in the section) else its composition is "—" with the reason "under 4 EDX px" (row stays). |
| Q6 | Strain profile | One selected object; sampled across its minor axis; precomputed into the snapshot (section 5.4) so the table window stays a value with no AppState. Averaging several selected objects is Later. |
| Q7 | Table columns | Fixed new columns for variant and direction; composition and strain columns are **dynamic** (`TableColumnForEach`) and appear only when their source exists; at% shown, wt% by a toolbar menu. |

## 1. What each task rests on (state of the kits, to be confirmed by the session at its start)

- ImagoKit 0.7.0 (tasks 32-34, landing today): `ObjectStatistics` (labelled `mean`, `standard_deviation`, `center_of_mass`; Feret,
  perimeter, solidity), the areal-density function (frame required, Miles–Lantuéjoul) and N_V = areal density / thickness with σ
  propagated, `validation: "none"`. **Names are the kit's CHANGELOG; this document says "the kit function".**
- DiffractoKit 0.10.0 (task 35): OR variants of β″ in Al (12) from `CrystalPresets`, `nearestVariant`, two-symmetry misorientation.
  If it does not expose an entry's orientation, the app builds it from `ZoneAxisFrame` + the entry's in-plane rotation (both public
  today) and files a kit ask; it never reimplements rotation algebra.
- SpectroKit `EDXQuantification.quantifyMaps` (present), CuboKit strain maps (present), ImagoKit `LineProfile.sample` (present),
  `MaskTransport` and `GridRegistration` (present; used by Pool by Class).
- Rule held throughout: **no number is computed in a view or in the app**. The app picks, votes, joins, formats.

## 2. Shared model (tasks 40-42 add to the same two types)

### 2.1 The report grows, additively

`PrecipitateObjectReport.Row` gains optional fields, decoded with `decodeIfPresent` (the precedent is `sourceID`); an old snapshot
decodes with all of them nil and the table shows today's columns:

```swift
package nonisolated struct VariantAssignment: Codable, Hashable, Sendable {
    package enum Status: Codable, Hashable, Sendable { case assigned, ambiguous(String), noOrientation }   // the String is the reason in words
    package let variant: Int?            // 1...12 in the kit's order; nil unless .assigned
    package let direction: Int?          // 0...2 (needle along sample [100],[010],[001]); nil unless .assigned
    package let angleDegrees: Double?    // distance to the nearest variant
    package let agreement: Double        // share of the object's pixels voting for it
    package let status: Status
}
package nonisolated struct ObjectComposition: Codable, Hashable, Sendable {     // one per element in the quantify set
    package let symbol: String; package let weightPercent: Double?; package let atomicPercent: Double?
}
package nonisolated struct ObjectStrain: Codable, Hashable, Sendable {          // rows and columns, not x and y
    package let rr: Double; package let cc: Double; package let rc: Double; package let rotationDegrees: Double
    package let sigmaRR: Double; package let sigmaCC: Double; package let sigmaRC: Double   // spread across the object's pixels
    package let pixels: Int
}
```

`Row` adds `variant: VariantAssignment?`, `composition: [ObjectComposition]?` (nil = no EDX/quantification; empty-with-reason is
`compositionNote: String?`), `strain: ObjectStrain?`, `strainProfile: StrainProfile?` (section 5.4). `ClassSummary` generalises to a
`GroupSummary` keyed by a `Grouping` (`.phase`, `.direction`, `.variant`), same fields (total, counted, edge, small, areaFraction,
medianLengthPx, arealDensity) plus `nVolume: NumberDensity?` (section 4). Phase summaries are unchanged byte for byte when no variants
exist (existing tests stay green).

### 2.2 Who computes what, and when

| Piece | Home | Runs |
|---|---|---|
| `ObjectVariantAssigner` (vote per object, nearest variant via the kit, ambiguity rule) | `Session/` (pure, value in/out) | detached, generation token, on a new class map, a tolerance change, or a new OR |
| `ObjectCompositionJoin` (transport labels, labelled means via the kit) | `Session/` | detached; keyed by (sourceID, quantification method hash, mask version) |
| `ObjectStrainJoin` (labelled means over the strain maps, profiles) | `Session/` | detached; keyed by (sourceID, strain run id) |
| `PrecipitateObjectReport.make(...)` | existing | takes the three optional join results; pure |
| Glyph colours, legend model, table columns, section rows | `UI/` | main actor, reading snapshots |

Each join lands only if its token is current (`PrecipitateClassificationProduct`'s pattern). A join that cannot run publishes a
**reason** (`.unavailable(String)`), shown in the section note and as the CSV comment, never an empty column.

### 2.3 Sidecar and replay

Settings, not results, ride in the objects lineage node's `parameters` next to `thickness_*`: `variant_source`
(`known_variants`), `variant_or` (the preset's name), `variant_tolerance_deg`, `variant_agreement_min`, `composition_min_px`,
`strain_profile_samples`. Replay recomputes. The thickness keys are unchanged. `ReplayPlan`'s per-key table classifies the new keys
(`.invariant` for `variant_or` and `variant_source`, re-run for the numeric ones). A sidecar without them replays as today.

## 3. Task 40: variant map, legend, per-direction counts

### 3.1 Where it lives (existing rooms, no new room)

Crystal Maps → phase mapping → inspector "Precipitates" section (exists), the scan panes' glyph overlay (exists), and the object
table window (exists). A new block inside the section, between the per-phase rows and the toggles, and one new result picture.

```
inspector › Precipitates
┌──────────────────────────────────────────────────────────────────┐
│ ⚠ From the unvalidated phase map above.                  (exists)│
│ β″ end-on      ■ 14 objects   median 23 nm   410 /µm²    (exists)│
│ β″ in-plane    ■  9 objects   ...                                │
│ ── Variants ─────────────────────────────────────────────────── │
│ Orientation relationship   [ β″ in Al, Andersen 1998 ▾ ]         │
│ Angle tolerance            [ 3.0 ]°     Agreement ≥ [ 0.50 ]     │
│ Colour by                  ( Direction | Variant )               │
│  ■ [100]   6 objects  140 /µm²  ┐  legend rows: swatch ·          │
│  ■ [010]   7 objects  165 /µm²  │  name · count · areal density  │
│  ■ [001]   9 objects  210 /µm²  ┘  (end-on)                      │
│   ▸ Variants 1-12 …  (disclosure: 12 rows, count each)           │
│  ▭ Unassigned  3 objects  (ambiguous 2, no orientation 1)        │
│ validation: none                                                 │
│ Objects on panes ☐  Counted only ☑  Labels ☐        (exists)    │
│ [Show Objects] [Object Table] [Export CSV…]          (exists)    │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Flow

Map phases (as today) → the Variants block appears once a class map has objects **and** the phase list carries a β″ OR preset
(the Al–Mg–Si preset sets it; otherwise the block shows a note "Choose an orientation relationship to count variants." with the
picker) → the assigner runs (progress dot in the block header) → legend fills → "Objects on panes" colours glyphs by the chosen
scheme → the object table gains Direction and Variant columns, sortable and filterable.

### 3.3 Colour, legend, glyphs

- **Direction** (default): three Okabe–Ito hues from `PhaseMapPresentation.palette` — sky blue, bluish green, vermillion. They are
  already the app's colour-blind-safe set; matrix stays the dark neutral. The phase's own colour remains in the phase rows.
- **Variant**: the direction's hue in four steps (lightness 0.0, +0.2, +0.4, −0.2 of the hue, kept above 3:1 against the pane) **and** a
  one- or two-digit number inside the glyph when Labels is on or the pane zoom allows; lightness alone is never the only cue.
- Unassigned objects: outline only, no fill, hatched in the table swatch. Edge/small objects are dimmed exactly as today.
- Selecting a legend row outlines that group on the panes (the same white outline the table selection draws) and filters the table
  (same relay, `PrecipitateTableSelection` gains `groupFilter`).
- `PrecipitateGlyph` gains `direction: Int?`, `variant: Int?` and `readout` becomes "#12 β″ [010] v7 23 nm"; `PrecipitateGlyphSet.make`
  reads them from the report. Colour is chosen at draw time from `PrecipitateOverlaySettings.colourBy` (an `Equatable` field), so a
  scheme change redraws, not reassigns.
- A result picture "Show Objects" draws the objects by variant when Colour by is not "Phase"; the picker has three values: Phase
  (today's), Direction, Variant.

### 3.4 States

| State | What the person sees |
|---|---|
| no class map | today's note |
| class map, no OR chosen | rows as today + the "Choose an orientation relationship" note and picker |
| assigning | block header progress dot; legend shows last result dimmed |
| done | legend with counts, densities (kit function over the group's counted objects) |
| failed | the kit's sentence in the block (LocalizedError) |
| nothing assignable | legend rows "0 objects"; Unassigned carries all; note says why (e.g. "no object had an orientation") |
| ACOM-only dataset | block disabled: "Variants from ACOM orientations are not built yet." (the seam exists) |

Counts mean **counted objects** (not edge, not small), consistent with the phase rows; the totals line beneath the legend reads
"22 assigned + 3 unassigned = 25 counted; 1 on the scan edge; 1 under 4 px (27 objects)" so the arithmetic is visible.

### 3.5 State and views

`ObjectVariantState` in `AppState` composition (owner named first, per the layering rule): `.idle / .running / .done(VariantRun) /
.failed(String)`, `VariantRun` = (sourceID, settings, per-object assignments, per-group summaries, version). Views read the
snapshot only. Legend row, swatch, glyph layer are separate structs; the legend `ForEach` reads the settings once above the loop.
Heavy work: `@concurrent` function with a generation token; the kit's cancellation closure is the task's.

### 3.6 Accessibility identifiers (task 40)

`precipitates.variants.section`, `.orPicker`, `.tolerance`, `.agreement`, `.colourBy`, `.legend`, `.legend.direction.0/1/2`,
`.legend.variant.1…12`, `.legend.unassigned`, `.totals`, `.progress`. Table: `precipitates.table.direction`,
`precipitates.table.variant`. Legend rows are buttons with a label "[010], 7 objects" and a value (the density); the colour is never
the only carrier of meaning (VoiceOver reads names; the swatch is hidden).

### 3.7 Done when (task 40)

1. A planted class map of needle objects with known variants (the fixture; section 7) gives the planted per-variant, per-direction
   and unassigned counts **exactly**, through the assigner, the report and the CSV.
2. Per-group areal density equals the kit function applied to that group's counted objects (test calls both).
3. The sidecar round-trips tolerance, agreement and OR; reopening reproduces the legend; an old sidecar replays unchanged.
4. Screenshot of the Precipitates section + panes coloured by direction and by variant, light and dark; `validation: none` visible.
5. `PrecipitatesJourney` steps 1-6 (section 8) green.

## 4. Task 41: N_V panel

### 4.1 Layout (same section, below the legend)

```
│ ── Thickness and N_V ─────────────────────────────────────────── │
│ Source     ( Typed | EELS method file | EELS map  ⓘ later )      │
│ t [ 120 ] ± [ 15 ] nm        Source note [ CBED fringes        ] │
│ [Read EELS method JSON…]      (sets the source words, not t)     │
│ N_V   per phase / direction / variant (same Group menu)          │
│   β″ end-on     3 400 ± 430 /µm³    ← = N_A / t                  │
│   β″ in-plane   2 100 ± 280 /µm³                                 │
│ Assumes objects span the foil.  validation: none                 │
```

- "Group" for N_V is the same `Grouping` picker as the legend (phase / direction / variant); default phase.
- **Source** segmented: *Typed* (built), *EELS method file* (the existing `ThicknessEntry.source(fromEELSMethodJSON:)`: fills the
  source words and origin, thickness stays the person's number until the EELS route is validated — as the type's header already
  states), *EELS map* disabled with a tooltip "Needs the EELS t/λ map from SpectroKit (suite task 16) and its adoption", behind a
  protocol (below) so enabling it later changes no view.
- Empty: no thickness → rows read "—" and the note "Type a thickness to get N_V." No scan scale → "no scan scale" as the density rows say
  today (the kit refuses without a frame; the refusal text is shown verbatim).
- Invalid input (≤ 0, NaN, σ < 0): the field keeps the typed text, marks itself invalid with the reason, and does not call
  `setPrecipitateThickness` (the existing `isUsable` rule). A change records a new run through `setPrecipitateThickness` (exists).
- Formatting: `/µm³` from nm inputs, locale-aware digits (D30), three significant digits, σ with the same digits.

### 4.2 Seam for the EELS map

```swift
package protocol ThicknessSource: Sendable { var entry: ThicknessEntry? { get } }   // typed today; EELS map later:
// reduce the t/λ-derived map over the analysed area to (median t, spread) → a ThicknessEntry with origin .eelsMap(...)
```
`ThicknessEntry.Origin` gains `.eelsMap(file:, method:, lambdaNanometres:, validation:)` **only when task 16 lands**; this design adds
no case now (a dead case is a lie). The "later" segment is disabled.

### 4.3 Compute and badge

One call per group: the kit's N_V function with the group's areal density, t and σ_t → value, σ, `validation: "none"`. The app
formats and caches by (run version, thickness entry). The badge text on the panel and in every export comes from the kit's
validation string, not from a literal in the app (the `inventory` check greps the key). CSV: the summary block gains `n_v_per_um3`,
`n_v_sigma_per_um3`, `thickness_nm`, `thickness_sigma_nm`, `thickness_source` (provenance pairs exist for the last three);
the table header comment says "assumes objects span the foil".

### 4.4 State and ids

`NumberDensityState` is derived (a pure function of the run, the grouping and the thickness entry), so it is a computed value in the
legend model, not stored state. Ids: `precipitates.nv.section`, `.source`, `.thickness`, `.sigma`, `.sourceNote`, `.readJSON`,
`.group`, `.row.<group>`, `.assumption`.

### 4.5 Done when (task 41)

1. A planted foil (known N_V, known t, σ) recovers N_V and its σ at the kit function's own tolerance through the panel's model;
   the registration is the planted foil, not Paul's cube (App work 2, ADR 050), so it runs now. State the registration's
   predictions before running (P-rows in the commit).
2. Type t → N_V appears; clear it → "—"; invalid input does not touch the run; sidecar round trip (exists) plus the new group choice.
3. The CSV and the panel carry the same number; badge key present.
4. Screenshot; journey steps 7-9.

## 5. Task 42: composition and strain per object, and the strain profile

### 5.1 Composition

- Needs: an EDX spectrum image **of the same scan** opened in the Spectroscopy room and quantified (`quantMaps.done`). Registration to
  the class-map grid is the existing `GridRegistration`/`MaskTransport`; the labels move to the EDX grid, the kit's labelled mean runs
  over each element's at%/wt% map with `navigationMask` respected (failed pixels are not averaged; their count is kept).
- Per object: `ObjectComposition` per element with role `.quantify`, plus `pixels` used. Under `composition_min_px` (default 4) → note
  "under 4 EDX px". No spectrum image → the columns are absent and the section note reads "Open the EDX spectrum image of this scan for
  composition per object." (same sentence as Pool by Class uses).
- Honest wording: a per-object mean is a **mean of per-pixel values** from the badged maps (they have no σ); the column header carries
  "mean, per-pixel" and the badge `validation: none` rides the columns. It is **not** the pooled-fit composition with a σ; Pool by Class
  remains the route for that, and the section says so in one line.
- Table: dynamic columns "Mg at%", "Si at%", "Al at%" via `TableColumnForEach(elements)`; toolbar menu "Composition: at% | wt%";
  right-aligned numeric, locale digits. CSV always writes both (`mg_at_pct`, `mg_wt_pct`, `…`) plus `composition_px`.

### 5.2 Strain

- Needs a strain map from the Crystal Maps strain task on this cube (same scan grid as the class map, no transport). Components are
  the app's existing product names; columns use **rows and columns** (`strain_rr`, `strain_cc`, `strain_rc`, `rotation_deg`) with the
  mean over the object's pixels and the spread (σ across pixels) in a secondary line/tooltip and in the CSV.
- A strain map exists only for the run it was made with; the join keys on the strain run id and the object `sourceID`; if the strain
  is stale against the class map's cube/reference it says so (`.unavailable("strain map is for another reference")`).
- No strain → columns absent, note "Compute strain in Crystal Maps for strain per object."
- Badge: whatever the strain product badges; if it self-reports `validation: "none"` the columns carry it.

### 5.3 Table layout (window)

```
┌ Precipitate Objects ───────────── [Phase ▾] [Group ▾] [Composition at%/wt% ▾] [Counted only] [Export CSV…] ┐
│ summary grid (exists + variant/direction counts rows)                                                       │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ id  phase  direction  variant  length  width  aspect  orient  … │ Mg at%  Si at%  Al at% │ ε_rr  ε_cc  ε_rc θ │
│  … sortable; new columns only when their source exists; selected row = outline on the panes                  │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Strain profile across #12   component [ε_rr ▾]    ▁▂▅█▅▂▁  object edges as rules   mean ± σ   validation… │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
Window default size grows to 1360×760; the table is in a `VSplitView` with the profile pane collapsible (default shown only when one
row is selected and a profile exists). The window width budget has a test (`InspectorWidthBudgetTests` precedent); add one for the
section.

### 5.4 Strain profile (the window stays a value)

The table window receives a snapshot and has no `AppState`. So the **profile is precomputed into the snapshot**: for every counted
object, `StrainProfile { component → [Double] }` of **33 samples** along the line through the centroid **across the object's minor
axis** (perpendicular to the major axis), from −(semiMinor × 3 + 3 px) to +(…), sampled by `LineProfile.sample(_:from:to:linewidth:)` on
the strain component as a `Micrograph` on the scan grid (linewidth 1, `.linear`, `.reflect`), with the object's edge positions stored
as fractions of the line. 33 samples × ≤ 4 components × objects (hundreds) is small. Done off-main with the join. Needle length
direction is not profiled (that is along the needle; a later item).
View: one `Chart` (Swift Charts, SwiftUI-native, no AppKit) with a `LineMark`, rules at the object edges, a component picker, and the
validation line; axis in scan pixels or the real-space unit when the scale exists (the profile positions come with the unit). Selection
of exactly one row shows it; zero or several: "Select one object to see its strain profile."

### 5.5 CSV (task 42)

Appended after today's 14 columns, in this order, each header literal and locale-independent: `direction`, `variant`,
`variant_angle_deg`, `variant_agreement`, `variant_status`, then `composition_px`, `<el>_at_pct`, `<el>_wt_pct` per element, then
`strain_px`, `strain_rr`, `strain_cc`, `strain_rc`, `rotation_deg`, `strain_rr_sigma`, `strain_cc_sigma`, `strain_rc_sigma`. Blank where
unavailable. Comment lines state the OR, tolerance, agreement, thickness, N_V assumption, quantification method hash, strain run id, and
`validation`. Column order of the existing 14 does not change (a moved fixture is its own commit with the reason).

### 5.6 Ids and done-when (task 42)

Ids: `precipitates.table.composition.<el>`, `…composition.mode`, `…strain.rr/cc/rc/rotation`, `…profile`, `…profile.component`,
`precipitates.composition.note`, `precipitates.strain.note`.
Done when: a planted object with known composition and known strain reads back through the join, the table (via the report's row
values) and the CSV at the kit's labelled-mean tolerance; two objects with different planted values do not mix; a failed EDX pixel is
excluded and counted; the profile of a planted step shows the step at the object's edges; no EDX / no strain gives the notes, not empty
columns; screenshot of the table window with columns and profile.

## 6. Layering, concurrency, AppKit

- Pure SwiftUI. **No AppKit needed** anywhere above (Table, `TableColumnForEach`, Charts, `Canvas` for glyphs, `fileExporter`).
- Owner named first: variant, composition and strain states are small `@Observable @MainActor` products composed by `AppState`, each
  publishing one `Equatable` snapshot with a version; caches `@ObservationIgnored`. The table window reads only `PrecipitateObjectReport`.
- The three joins are `@concurrent` functions, never called from a `body`; one generation token per join; progress through a
  `@Sendable` closure setting one `Double`.
- Every numeric above is a kit call; the app code is selection, voting, joining, formatting. `DEVIATION` notes are not expected
  (this is not a port of py4DSTEM); if the session needs one, it is inline and listed in the hand-off.
- Layering test: the new `Session/` types import no `SwiftUI`.

## 7. The planted fixture (one, shared by 40, 41, 42 and the journey)

A pure value built in code (`PlantedPrecipitateScan`, in the test support target, also used by the demo launch below): a 64 × 64 scan,
pixel 5 nm, 27 objects of known geometry (not touching each other), planted so that:

- variants: counts per variant 1-12 = [3,2,0,1, 4,2,1,0, 3,3,2,1] (22 assigned, directions 6 / 7 / 9 by blocks of four), 2 further
  objects planted ambiguous (one equidistant between two variants, one with a 50/50 pixel vote → status ambiguous) and a third with no
  entry (noOrientation); a 26th touches the scan edge, a 27th is 3 px (under the minimum). (27 objects in all; every group has a planted, asserted count including zeros.)
- thickness 100 ± 10 nm; the expected N_V per group is stated in the fixture file next to the kit function that produces it.
- composition: each object has a constant planted Mg/Si/Al at% (different per direction) on a synthetic quantified map with a few
  failed pixels inside two objects.
- strain: ε_rr = +0.010, ε_cc = −0.004, ε_rc = 0.002, θ = 0.1° inside every object of one direction, 0 elsewhere, plus one object with
  a linear ramp.

Truth values live in the fixture; no hand-copied numbers in assertions.

**UI demo.** `--demo-precipitates` (read in `App/LaunchOptions.swift` only, like `--demo-fixture`) installs the planted scan's
class map, variants, quantification and strain as in-memory session products — no cube, no heavy compute — so the journey ends on a
planted number. The existing `UITestingLaunch` reset helper clears it.

## 8. Journey: `PrecipitatesJourney` (new file, `mac4DSTEMUITests`)

Per `process/ui-testing-2026-10-21.md`: launch+activate+`waitForExistence(20)`, find by identifier, read through
`accessibilityValue`, terminate in teardown, no sleeps, window width via `--ui-window-width`. One screenshot per step.

1. launch with `--demo-precipitates` (opens in Crystal Maps, phase mapping, the planted scan).
2. the Precipitates section shows the phase rows (`precipitates.variants.section` exists).
3. legend: `precipitates.variants.legend.direction.0/1/2` values read "6", "7", "9"; `…unassigned` reads "3".
4. switch Colour by to Variant: the legend variant rows read the planted counts (spot-check 1, 5, 12 and a zero row).
5. Objects on panes on: the pane overlay exists; the legend selection outlines a group (the table relay value changes).
6. open Object Table: Direction and Variant columns exist; sort by variant; selecting a row sets the relay.
7. thickness: type 100 ± 10, source note; `precipitates.nv.row.<phase>` reads the planted N_V string.
8. composition and strain columns present; the first planted object's `…composition.mg` and `…strain.rr` read the planted values.
9. select one object: `…profile` exists; export CSV opens the panel and cancels (the CSV content is a unit test, not a journey).

Final assertion: the N_V readout equals the fixture's planted figure. The journey is the touched one per landing; the full `ui` run is
the nightly's.

## 9. Order, size, and the Mac brief

One session chain, one writer, the app repo only (kits are tagged and re-pinned first; exact tags restored at closeout):

| Step | Task | Prereq | Duration | Commit |
|---|---|---|---|---|
| 1 | 41 (thickness row + N_V panel + CSV; the planted foil) | ImagoKit 0.7.0 tag (tasks 34) | 45-60 min | own commit |
| 2 | 40 (assigner, legend, colouring, table columns, sidecar keys) | DiffractoKit 0.10.0 tag (task 35), task 39 landed | 90-120 min | own commit |
| 3 | 42 (joins, dynamic columns, profile, CSV) | ImagoKit 0.7.0 (33), EDX room quantified maps, strain run | 90-120 min | own commit |
| 4 | `PrecipitatesJourney` + `--demo-precipitates` (can land with step 1 and grow) | none | 30 min | with each step |

Brief for the session: read this file, `docs/design/rooms-2026-10-21.md` section 3, `process/ui-testing-2026-10-21.md`, ADRs 019, 038,
045 and the kit CHANGELOGs; load the swiftui-macos skill; per step: failing test first, `tools/run-tests.sh unit` once at the end of the
step, the touched journey (`tools/run-tests.sh ui PrecipitatesJourney`), screenshot into the commit, CHANGELOG line (the user sees
variants, N_V, columns), **commit on local `main`, never push**; the hand-off sentence names what Paul clicks (open the demo, read
the legend, type a thickness). One Sonnet review before the commit of step 2 only if the app's vote or ambiguity rule is more than
glue (it touches numerics only through the kit; otherwise CI and the nightly cover it). AppKit: none expected; if the session needs
any, it names it in the hand-off.

## 10. What this design deliberately leaves out

ACOM as a variant source (the seam is `ObjectVariantSource`); averaging profiles over several objects; profiling along the needle;
the Underwood correction; the EELS t/λ map as a thickness source (task 16); true contours instead of ellipses (`find_contours`);
re-colouring the objects CSV by anyone's labelled scan (study item 4 needs Paul's data).
