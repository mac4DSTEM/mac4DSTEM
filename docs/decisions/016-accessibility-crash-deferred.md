# 016 — Accessibility crash does not block a release; VoiceOver deferred

Dates: 2026-09-11

Status: live

## Decision

The `accessibilityLabel()` stack-overflow crash does not block a release cut.
The owner, asked directly: *"i dont care about VoiceOver, it is not part of
the consideration... we care about something like this in v8.0.0 or
whenever."* The defect is not VoiceOver-only — it fires for any AX client
that resolves labels on the front window, including Accessibility Inspector
and UI automation — and it stays in `open-items.md` as a known defect rather
than being quietly dropped. The README and CHANGELOG say nothing that claims
accessibility support.

## Why

The owner's stated priority is explicit and the condition ("no other
practical meaning") is not fully met — the crash is also a hard blocker on
ever restoring an automated driving rig — so the caveat is recorded even
though it does not override the decision.

## Governs

`docs/open-items.md`'s accessibility-crash entry, `README.md`/`CHANGELOG.md`
accessibility claims (must make none).

## Sources

- 2026-09-11 "the accessibility crash does not block v3.0.0", log line 776
