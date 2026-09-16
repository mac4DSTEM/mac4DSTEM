# 006 — py4DSTEM pin fetched not vendored; DEVIATION notes cite it

Dates: 2026-09-03, 2026-09-14

Status: live

## Decision

The 196 tracked source files formerly under `References/` are replaced by
`tools/lib/fetch-py4dstem.sh`, which clones upstream at commit `f050d207`
(dev, 2026-03-26, version 0.14.19 — the commit whose tree matched the tracked
copy byte for byte) into the gitignored `References/` folder on demand; CI
and the scientific runner call it. Every intentional divergence from the
pinned source gets an inline `DEVIATION` comment at the point it diverges.

## Why

A public repository should not carry a copy of another project. The pin
being exact keeps `DEVIATION` file:line citations true. `Crystal.reflections`
is the worked example of why the note matters: py4DSTEM bounds every Miller
index by the shortest of ten reciprocal directions, which under-bounds an
oblique cell (6 reflections lost at β=110°, 198 at β=125° on the shipped β″
shape); the port tiles each index by `ceil(kMax·|aᵢ|)` instead and says so
inline, because phase mapping is the first feature to hand this function
arbitrary imported cells.

## Governs

`tools/lib/fetch-py4dstem.sh`, `References/` (gitignored), the `DEVIATION`
comment convention, `mac4DSTEM/Core/Crystal/Crystal.swift`'s `reflections(kMax:)`.

## Sources

- 2026-09-03 "The py4DSTEM lock is fetched, not vendored", log line 75
- 2026-09-14 "`Crystal.reflections` deviates from py4DSTEM's tile bound", log line 1268

Evidence: `tools/lib/fetch-py4dstem.sh`, `mac4DSTEM/Core/Crystal/Crystal.swift:112`
(verified: `func reflections(kMax:tolerance:)`).
