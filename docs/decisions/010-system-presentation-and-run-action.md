# 010 — System-only presentation; toolbar and sidebar own the run action and trust

Dates: 2026-09-03, 2026-09-04

Status: partly superseded by the owner's 2026-09-22 window decision

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

**2026-09-22 amendment:** `docs/archive/v4/window-design.md` §1 and §6 supersede the
toolbar placement: the primary action, Save to Session and Reveal belong in
the centre header, grouped at its right edge as the centre width changes.
The toolbar keeps only window-level controls. The system-only presentation
and sidebar trust rules remain. Phase 1 has not been accepted on screen.

## Why

"An old sidecar loaded with a cube" is exactly the case nobody thinks to go
looking for, so its warning needs to be always visible, not one tab away.
Centring the run action truncated "Cancel" to "C…" under a busy state that
had no room.

## Governs

`architecture.md`'s presentation contract and the sidebar's Dataset/Session
sections; toolbar placement is superseded above.

## Sources

- 2026-09-03 "A system-only presentation (owner)", log line 99
- 2026-09-04 "the toolbar's trailing edge owns the run action, and the sidebar's foot owns session trust", log line 226
