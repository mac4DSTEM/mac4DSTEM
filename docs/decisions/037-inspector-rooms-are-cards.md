# 037 — Inspector rooms are cards in one grouped form; Prepare is the reference

Dates: 2026-09-22 (evening)

Status: live — built the same evening; owner drive owed

## Decision

The inspector's Settings tab for a room is ONE top-level grouped `Form`
(owner, 2026-09-22 evening, choosing "Pixelmator cards" over the
morning's columns form, `window-design.md` §6.8, §8.8): every section a
card, every card a title row and rows beneath, regular control size,
13-pt text. A calibration step is a card whose header carries its number,
its name and its state, and whose rows carry the value, the one action and
the manual fields that belong to it, in pipeline order — Prepare:
1 Origin & probe · 2 Ellipse distortion · 3 R–Q rotation · 4 Q pixel
scale · 5 R pixel scale · 6 Accelerating voltage. Readiness is one row at
the top ("Quantitative in 4 of 6 steps · still needed: …"), never a
paragraph. Advanced fields are a disclosure row inside their card.

The shared sections (Requirements, Interpretation, Display, Dataset
actions, Computed this session) render as cards in the same form through
`SettingsSection(inForm:)`, and as the flat `InspectorSection` stack in the
rooms not yet converted. A card does not collapse — a grouped form has no
native collapsing section — which answers the open question of the
morning: always-open cards, Advanced as a disclosure row.

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
mutation), `WorkspaceInspector.SettingsSection`, the Prepare branch of the
Settings tab. Supersedes ADR 034's row vocabulary for converted rooms and
§6.1 of 2026-09-22 morning.

## Sources

- `docs/window-design.md` §6.8, §8.8; the Pixelmator screenshot he sent
- `docs/archive/v3/ui-review-2026-09-22.md` §4 (item 2)
