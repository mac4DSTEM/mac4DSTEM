# tools/ retired 2026-09-23

`tools/` had grown to 69 directories (~35k lines) against ~60k lines of app
code. This session (#3, owner-approved) classified every entry against
`tools/run-tests.sh`'s own gated/diagnostic/support lists and against live
doc citations (excluding `docs/archive`), then retired the diagnostic
one-offs whose question is answered and that nothing live still cites as
the way to re-measure. History keeps each directory; restore any of them
with:

```sh
git checkout <commit> -- tools/<dir>
```

| Tool | Question it answered | Record that holds the answer | Last commit with it |
|---|---|---|---|
| `tools/acom-groundtruth` | What is `power_radial`'s effect on ACOM orientation error, and what value should ship? Measured over 136 planted patterns across 8 zone axes; `power_radial = 0` (the shipped port's value, since py4DSTEM's factor was omitted) was compared against 0.5/1.0/2.0. | `docs/archive/closed-items-2026-09.md` (the `power_radial` table); the resulting 13.6° constant is cited in-line at `mac4DSTEM/Core/Crystal/OrientationPlan.swift:219` and `mac4DSTEM/UI/MapSettings.swift:913,917` as measured-2026-09-15 provenance, not as an instruction to re-run the tool. | `2e805f9` (2026-09-15) |
| `tools/review-record-check` | Did the 2026-08-31 review recovery's accounting (75 initial findings across 11 areas, 15 session records) reconcile — every finding and session given an explicit, non-duplicate disposition? | `docs/archive/2026-08-31-review/README.md` and `process-review.md` ("Recovery-checker review: all 75 IDs preserved"). The tool validates that one fixed directory's `recovery-manifest.json`/`findings.json`/`session-audit.json` schema; no later review (`docs/archive/2026-09-09-review/register.json` is a different, incompatible schema) reused it, and no live doc cites it. | `0531cd9` (2026-09-01) |
| `tools/phase-discrimination-probe` | Does per-position ACOM-score template matching discriminate the β″ precipitate phase from Al at realistic precipitate beam-path fractions (0.05–0.5)? Pre-registered criterion: fails if the argmax needs >0.3 precipitate fraction to pick the right phase. | `docs/archive/v3/phase-discrimination-2026-09-11.md` — "It killed it, twice over." The route was refuted; `tools/phase-vector-matching/run.sh` (gated, `scientific`) is the surviving route and its own header comment now cites this record instead of the retired path. | `b314535` (2026-09-21) |

Total retired: 1,003 lines (566 + 156 + 281).

## Classified but kept (for the record)

Every other `tools/` directory was either already gated (in a
`run-tests.sh` target list, or invoked by one), support infrastructure
(`lib`, `release`, `crystal-structures`, `hooks`), or a diagnostic still
cited by a live doc or another live tool:

- `bragg-spacing-probe`, `residency-sweep` — `docs/open-items.md`: "both
  need gitignored multi-GB data and stay diagnostics only — a standing
  limit, not a gap."
- `origin-fit-diagnostics`, `training-dataset-campaign` — `docs/decisions/020-accelerate-new-lapack-flag.md`
  ("Governs" names their `run.sh`/`swiftc` lines directly) and
  `docs/q-calibration-design.md` ("Live status, checked against HEAD,
  2026-09-23").
- `precipitate-handcount` — cited by `docs/v3-features.md`.
- `phase-map-probe`, `rotation-null-probe`, `hdf5-race-probe`,
  `thronsen-dataset` — cited by live ADRs `docs/decisions/024`, `025`,
  `026`.
- `demo-dataset` — not cited by a live doc directly, but is depended on
  (by path, in-source) by three of the above still-live diagnostics
  (`hdf5-race-probe/run.sh`, `phase-map-probe/main.swift`,
  `thronsen-dataset/run.sh`).
- `performance-baseline` — technically gated: `run-tests.sh benchmark`
  invokes it directly (it sits in the script's own `diagnostic=()` array
  for inventory's bookkeeping, but that is an accounting label, not its
  actual gating status).
- `volume-mmap-probe` — reproduces the mechanism named in `docs/open-items.md`'s
  still-open "DM4Reader silently reads whole files into RAM" item; its own
  header calls it "S9b's evidence, re-runnable," and any future fix needs
  the fixture trick it demonstrates.
- `real-acom-benchmark` — **(?) unclear.** No live doc citation and no
  archive record stating its question is answered; also no other tool
  depends on it. Kept rather than retired for lack of evidence either way;
  worth a follow-up look.
