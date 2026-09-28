# 042 — Thronsen et al.'s SPED-phase-mapping code may be used for ground truth and ported

Dates: 2026-09-28

Status: live. This supersedes the "may not copy" line of `archive/v3/sped-phase-mapping-reference-2026-09-11.md`
§6 and the "no licence" notes that follow from it.

## Decision

The owner spoke with Elisabeth Thronsen, the paper's first author and the repository's owner
(`elisathr/SPED-phase-mapping`), on 2026-09-28. She confirmed that the code was published to be used.
The owner undertook:
- **not to copy it 1:1** into mac4DSTEM;
- to **use it to establish ground truths**: run it locally and reproduce the paper's outputs;
- to **port it to Swift / Metal / MLX / Core AI where that makes sense**, with attribution.

From now on:
- **Running their notebooks** (pyxem 0.14.2, tensorflow) locally, to produce reference outputs on
  inputs we choose, is in scope. Examples: dataset A at stride 3, dataset B, the owner's Al-Mg-Si cube.
- **Ports** follow the py4DSTEM rule. The source is cited by file and cell in the Swift code, every
  deviation gets a `DEVIATION` note, and each port is scored against the original's own outputs on
  the same input before it is called equivalent.
- **Attribution:** Thronsen et al., *Ultramicroscopy* 255 (2024) 113861, and the repository, in
  `NOTICE` for any ported method.

## Caveats, on the record

- **The permission is verbal and not yet written.** The repository still has no `LICENSE` file. This
  repo is public, so a reader cannot yet check it. **Owed:** file the author's written confirmation
  (an email, or a `LICENSE` added upstream) under `docs/archive/`. The drafted request is in the
  session record of 2026-09-28.
- **The repository lists six code contributors** (Christiansen, Bergh, Frafjord, Thorsen, Thronsen).
  The first author's word covers the owner's use in good faith. A written licence upstream would
  cover everyone.
