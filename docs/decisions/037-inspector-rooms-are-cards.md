# 037 — Inspector rooms are GroupBox cards; Prepare is the reference

Dates: 2026-09-22 (evening)

Status: live — rebuilt as GroupBox cards the same night; owner drive owed

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
