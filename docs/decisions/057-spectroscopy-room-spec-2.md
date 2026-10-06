# 057 — Spectroscopy room, spec 2: the owner's bullet list rebuilds the room's controls (one window, controls in the inspector)

**Date:** 2026-10-06/07 · **Status:** accepted by delegation (owner's list of 2026-10-06; decisions D-1…D-16 "overrule on sight") · **Amends:** 056 §4, §6, §7

## Context
After driving the room rebuilt to ADR 056 the owner wrote 28 bullets (spec: `docs/archive/v5/ux-spec-2-2026-10-06.md` §1 lists the
decisions taken for him). The structure stays (ADR 056: one window, maps own the content, static sidebar); what changes is where the
controls live and how the maps, the table and Auto ID behave.

## Decisions
1. **Controls live in the inspector**, like every room: the maps header row goes; int / net and the region tool are rows.
2. **The quantification panel leaves the content** (056 §7 reversed): the spectrum takes the full width; the results table and all
   its labels (the `unvalidated` badge, "· no absorption", the caveat, χ²ᵣ, "k-free", Method, the whole-map line) are the inspector's
   Results section.
3. **Tiles are pickers; the ColorMix is the only canvas.** A click puts an element (or the HAADF backdrop) in or out of the mix — the
   accent outline says so. Regions are drawn, moved, resized, deleted (⌫) on the ColorMix only. Colour / contrast / gamma stay on the
   tile's chip popover; the Map display section goes.
4. **Auto ID is a button and applies its picks** (056 §6 amended): on open and on the button, the elements it finds are picked and
   mapped at once; the person removes the wrong ones in the table. The badge `unvalidated` stands beside the button; the "Picked"
   row carries the reasons on hover. The "proposed" tile state, the three-tile cap, Accept and the sum-peak question markers on the
   plot are gone (the questions stay in the Picked row's hover).
5. **The periodic table has the table's own shape** (056 §4 amended): 18 columns scaling with the inspector's width, the f-block
   folded; right-click lists each line family with its energies.
6. **The spectrum opens linear**; double-click shows the full range, Home the lines' span; a drag in the y gutter stretches the scale.
7. **Two draggable dividers**: the spectrum header (maps ↔ spectrum) and the ColorMix edge (ColorMix ↔ tiles), scene state.
8. **Sections:** Elements · Region · Results · Quantification · Fitting · Export. Export once (results CSV, method JSON, spectrum
   CSV); no hash on screen; the lineage step shows readable keys (`method_json` and the full hash stay in the record, hidden).
9. **Quantify and Auto ID run as operations** (the infobar's bar, elapsed and Stop).
10. **Glass only on the capsules over maps** (HIG Materials); the shell's glass, the inspector width, "Compute Image", EDX products
    in the Results room and per-line fitting are owner pictures / cards (spec §4).

## Consequences
Built overnight by six Sonnet lanes on disjoint files, merged and gated as one landing, driven by the session on the synthetic
4D-EDX cube and the owner's Velox SI 1339 (`docs/archive/v5/room-drive-3-2026-10-07.md`). Dead code the amendments retired
(`active`, the proposed-tile pipeline, the suspect and proposed marker kinds, the two-band layout, the Auto ID switch) was removed in
the same session's clean-up commit (−283 lines).
