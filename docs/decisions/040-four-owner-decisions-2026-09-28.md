# 040 — Four owed decisions settled: the object pass bar, the R–Q sign, the Al constant, CI

Dates: 2026-09-28

Status: live. The owner, on the v4.x board's "Waiting on you" cards: "we go with your
recommendations". Each decision below is the card's recommendation, word for word in substance.

## Decisions

1. **The object-level pass bar is the T4 draft**
   (`docs/cloud/2026-09-23/T4-object-preregistration-DRAFT.md`, now marked adopted).
   - Raw spurious objects and split/merge/vanished counts come first; cleaned counts come second.
   - A null map must fail.
   - The published four methods' range is the reference (the draft's decision 3).
   - The draft's convention stands: rule P with H as the bracket, on the stride-3 grid.
   - θ′ edge-on is scored on area only at stride 3. Dataset B's run is not funded now.
   - Per-position error is reported for continuity and does not gate.
   - `lengthPx` keeps the definition the app computes: centre to centre + 1.
2. **The R–Q rotation is displayed and written in py4DSTEM's convention.** The app's internal
   angle is the negative of py4DSTEM's on the same file (the axis order). The conversion happens
   once, at the file boundary. It changes a scientific number, so it goes through Gate D, with a
   file-faithful fixture and a check of `ellipseTheta` at the same boundary
   (`open-items.md` "App R–Q rotation is −py4DSTEM's …").
3. **Aluminium keeps 4.0495 Å** (pure Al at room temperature) for the built-in, with a
   `DEVIATION` note naming the paper CIF's 4.04 Å (`Crystal.swift`). The 1.81 → 1.83 % difference
   on Thronsen (5 of 29 241 positions) comes from the {220} ring straddling `kMax` = 0.70 Å⁻¹
   (√8/a = 0.6985 Å⁻¹ at 4.0495 Å, 0.7001 Å⁻¹ at 4.04 Å). It is not an excitation-slab effect: that
   corrects Finding 4 (`archive/v3/precipitate-overnight-2026-09-23.md`). Revisit only if a second
   dataset disagrees.
4. **CI's unit job is paused** (`if: false`, with a note in `.github/workflows/ci.yml`) until GitHub
   offers a macOS 27 runner image. The `macos-26` image cannot build a macOS 27 app. The other jobs
   are unchanged. It comes back as the independent gate this one-machine setup lacks.
