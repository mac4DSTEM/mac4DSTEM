# 037 — Inspector rooms are GroupBox cards; Prepare is the reference

Dates: 2026-09-22 (evening)

Status: **reversed 2026-09-22 afternoon** — he drove the cards ("much better now" for the window as a whole) and then: "the Prepare panel still looks different from the rest — make it look like the other panels, make everything the same, then improve from there." Prepare is back on the rooms' `InspectorRows` kit (the file of `69c40d1`, the six-step readiness line kept); a room's look now improves in the kit, for all six rooms at once. The card vocabulary below is the record of what was built, for that discussion.

## Decision

The inspector's Settings tab for a room shows each step as a `GroupBox`
(owner, 2026-09-22 late evening, rejecting the grouped-`Form` built
earlier that night, `window-design.md` §9.4): every step a `GroupBox`
whose first row carries its number, its name, its state and its one
action (Measure / Fit / Measure Again…); rows beneath carry the label
left and the value right; regular control size, 13-pt text; in pipeline
order — Prepare: 1 Origin & probe · 2 Ellipse distortion · 3 R–Q rotation
· 4 Q pixel scale · 5 R pixel scale · 6 Accelerating voltage. Readiness
is one row at the top ("Quantitative in 4 of 6 steps · still needed:
…"), never a paragraph. Advanced fields are a disclosure row inside
their card. Clear Calibration is a plain destructive button at the end
of the room.

The grouped-`Form` version of the same evening drew macOS's Settings
list, not a card, and the owner rejected it on sight the same night
("even the previous version was better"); `GroupBox` is the native card.
The shared sections (Requirements, Interpretation, Display, Dataset
actions, Computed this session) stay unchanged in the flat
`InspectorSection` host for now. Cards do not collapse — Advanced is a
disclosure row.

Prepare is the reference room; no other room converts until the owner has
driven it. When every room is converted, `InspectorRows.swift` goes.

**Superseded 2026-09-22 night (owner, on his build: "this can't be it … look
up the Apple dev documentation"):** cards were built into the kit, driven,
and then dropped for Apple's own inspector guidance — `Form` "renders as a
vertical stack" on macOS; ≤ 2 prominent buttons per view (the room's verb is
the toolbar's); leading disclosure; colour on symbols, text in label
colours; no Liquid Glass in content. The kit (`UI/InspectorRows.swift`, whose
header cites each source) is now flat sections with the whole title row as
the leading disclosure, label leading / control trailing (his Pixelmator
rule), bordered buttons at one shared width (`.buttonSizing(.flexible)`),
and `InspectorStatusRow` with the state on the symbol. Gaps: no adaptive
`Menu`, no tinted warning note.

## Why

The owner's reading of the 2026-09-21 restyle ("cramped, three
alignments, no workflow") and his 2026-09-22 vision (§8.8: fonts too
small, workflows not considered, Pixelmator's panel as the cleaner
example). A grouped form is the native macOS shape of that panel; nesting
one form in another was the rejected 2026-09-21 trial, so the whole tab
is the form.

## Governs

`PrepareSettings` (`stepOrder`, `readinessSummary` — one test, red under a
mutation), `TrailingValueLabeledContentStyle`, `LayoutPolicy.cardPadding`.
Supersedes ADR 034's row vocabulary for converted rooms and §6.1 of
2026-09-22 morning.

## Sources

- `docs/window-design.md` §6.8, §8.8; the Pixelmator screenshot he sent
- `docs/archive/v3/ui-review-2026-09-22.md` §4 (item 2)
