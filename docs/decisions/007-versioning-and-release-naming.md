# 007 — Versioning and release naming: v2.0.0 named never built, v2.5, v3; patch vs minor

Dates: 2026-09-02, 2026-09-03, 2026-09-11

Status: live

## Decision

What exists ships as v2.0; the architecture consolidation is codenamed v2.5
and releases as v2.x increments; v3 is reserved for the owner's feature plan
and bumps when its first feature lands on the new legs. Process and
architecture docs are version-free. `open-items.md`'s lanes set the release
rule: a patch changes no scientific output; a landed change to one cuts the
next minor and the changelog names the number; releases are cut when what
has landed is worth a build, never scheduled against a number. v2.0.0 was
tagged locally on the Gate D closeout commit but never built or pushed; the
six files that called it built were corrected to say "named, never built,
superseded by v2.5.0" (see 028's C1 entry). The learned disk detector's
arrival made v3.0.0, not v2.7.0, the number for the 2026-09-11 cut: a feature
cuts a major version under this rule, and cutting the same work under a minor
would hide its largest change.

**Amended 2026-09-22 night (owner):** a raised system requirement is a
major version. The macOS 14 → 27 floor ships as **4.0.0**, not 3.1.0, although
the calibration foundation alone would have been a minor; v3.0.0 stays the
download for older systems.

## Why

A version number should describe what happened, not a schedule. Tagging the
Gate D closeout let consolidation start on `main` without waiting for a DMG;
naming v3.0.0 instead of v2.7.0 keeps the rule (feature → major) honest.

## Governs

`CHANGELOG.md` version headers, `CITATION.cff`, `docs/releasing.md`.

## Sources

- 2026-09-02 "Naming", log line 31
- 2026-09-02 "Tag before ship" (superseded — never built), log line 36
- 2026-09-03 "Four lanes and a number rule", log line 130
- 2026-09-11 "the consolidation plan is archived and v3.0.0 is the next cut", log line 800
