# 010 — System-only presentation; toolbar and sidebar own the run action and trust

Dates: 2026-09-03, 2026-09-04

Status: live

## Decision

Tools stay on the left, information (dataset, product, preview, sidecar,
diagnostics) on the right; every settings group is a system `Form`; no
custom backgrounds, tints, bars or fixed frames outside the scientific
panes; the app takes the system's appearance from its containers. The
primary run action lives in the toolbar's `.primaryAction` (trailing), not
`.principal` (centred) — centred had no room for the busy state and
duplicated the status bar's own progress. The sidebar's foot carries a
Dataset and Session section, and session-vs-data disagreements (an
unreadable sidecar, a sidecar describing a region the file lacks, a result
computed on a different view) are permanent, not buried in an Info tab.

## Why

"An old sidecar loaded with a cube" is exactly the case nobody thinks to go
looking for, so its warning needs to be always visible, not one tab away.
Centring the run action truncated "Cancel" to "C…" under a busy state that
had no room.

## Governs

`architecture.md`'s presentation contract, the toolbar's `.primaryAction`
placement, the sidebar's Dataset/Session sections.

## Sources

- 2026-09-03 "A system-only presentation (owner)", log line 99
- 2026-09-04 "the toolbar's trailing edge owns the run action, and the sidebar's foot owns session trust", log line 226
