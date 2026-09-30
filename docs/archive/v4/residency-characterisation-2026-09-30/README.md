# Resident vs streamed on the M5 Pro — measured 2026-09-30 (decision: `.automatic` stays dropped)

Machine: M5 Pro 64 GB, macOS 27.0.1, working set 55.7 GB, `maxBufferLength` 41.7 GB. Data (local copies):
`060_STEM SI.dm4` (330² × 256² float32, 28.6 GB) and `Au_ref_ROI11 … no_bin.h5` (178 × 214 × 512², 39.9 GB).
Run: `tools/residency-sweep/characterise.sh`, one process per cell, 3 repeats, page cache dropped before each cold
cell; table `summary.md`, chart `curve.svg`, every sample in `samples-*.tsv`, predictions (and two corrections) in
`predictions.md`. Ratio = cube bytes ÷ working set.

| Question | Measured |
|---|---|
| Single pass, file not cached | Resident is **not** faster: preload + first image costs 0.93–1.45 × a streamed pass (DM4), 1.4–2.9 × (HDF5). |
| Repeated passes | Resident is **57–73 ×** faster per virtual image on the DM4 (84 ms vs 6.2 s at 27 GB), 21–29 × on the HDF5; mean DP 50–61 × and 17–19 ×. Pays for itself after 2–4 passes. |
| Same numbers | Checksums identical across modes, passes and repeats in all 13 cells. |
| Memory | Peak footprint = cube + 2.7–4.0 GB. Swap 1 MB through ratio 0.56; 18 MB at 0.65; **3.0 GB and one pressure warning at 0.70**. |
| Knee | **Not clean.** Warm resident passes stay flat to 0.72 (no cliff). The first dispatch after the preload degrades gradually from ratio ≈ 0.45 (12.8 → 41.9 → 86.4 µs per MB on the DM4 at 0.37 / 0.47 / 0.51: 1×, 2.8×, 5.9× the ladder median; the HDF5 ladder climbs from 0.28 on), and swap starts between 0.56 and 0.70. A slope, then swap — no plateau-then-wall. |

Predictions: P0b, P0d, P2 held; P0a held on the DM4 and failed on the HDF5; P1 failed (swap and a pressure warning
below the cap); P3 failed in 6 of 13 cells (warm samples spread > 20 %, mostly the small streamed rungs).

**Decision (owner's rule 1: lift only on a clean knee).** The knee is not clean, so ADR 013 and the `CLAUDE.md` rule
stand: `measuredWorkingSetFraction` stays nil, `.automatic` does not return. Decision 2 is moot. No Core change, no
number moved. **Not done:** the independent refuter — dropped at the owner's word in-session (2026-09-30); this
record is one model's reading of its own sweep. Nothing above ratio 0.718 was reachable with the data at hand.

**What the curve says for later** (owner's, not decided here): resident is worth having for repeated work and is a
loss for a single pass, so the honest switch is the user's intent, not a size threshold — the parked per-open toggle.
On this Mac a cube up to ≈ 0.37 of the working set (≈ 20 GB) went resident with no first-touch penalty and no swap;
that is one machine, two files, an idle desktop, and is a description, not a threshold.
