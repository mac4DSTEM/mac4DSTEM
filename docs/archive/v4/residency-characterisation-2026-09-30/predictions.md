# Residency characterisation — predictions, written before any run (2026-09-30 night)

Machine: M5 Pro, 64 GB, macOS 27.0.1; Metal working set 55.7 GB, `maxBufferLength` 41.7 GB (ratio 0.75); tile
budget physical/24 = 2.67 GB. Data, local copies: `060_STEM SI.dm4` (330 × 330 × 256 × 256 float32, cube 28.5 GB,
ratio 0.51) and, for the rungs above it, `Au_ref_ROI11 … no_bin.h5` (178 × 214 × 512 × 512, 39.9 GB, ratio 0.72;
dtype read before use). Ratio = `byteCountAsFloat32` ÷ working set. Tool: `tools/residency-sweep --characterise`,
one process per (file, rows, mode) cell, every sample kept.

**Step 0 — is resident faster at all? (full DM4 cube, ratio 0.51)**
- P0a, single pass, file not in the page cache: preload + first virtual image costs **0.8–1.5 ×** one streamed
  virtual image (both read every byte from disk once). Resident does not win a single pass. Refuted outside that band.
- P0b, repeated passes, warm: a resident virtual-image pass is **≥ 5 ×** faster than a streamed one (streamed still
  decodes and copies 28 GB per pass out of the page cache). Refuted if < 2 ×: then resident is not worth having.
- P0c, mean diffraction (keeps the tiled reduction when resident): gain **smaller** than the virtual image's but > 1.5 ×.
- P0d: resident and streamed results are bit-identical (checksum) in every cell.

**Step 1 — the size ladder**
- P1 (sharper than the pre-registration's "knee between 0.5 and 0.8"): on the otherwise idle 64 GB machine there is
  **no cliff below the buffer cap**: cold resident ns/MB stays within 3 × of the ladder's median through ratio 0.72,
  swap stays 0, pressure stays normal. The binding limit is `maxBufferLength` (0.75), not paging.
  Refuted if any rung ≤ 0.72 shows cold ns/MB ≥ 8 × the prior median, swap growth, or a refused allocation.
- P2: the preload is the risky phase, not the dispatch: peak footprint = cube + about one tile (≈ 2.7 GB).
  Refuted if the peak exceeds cube + 3 tiles.
- P3: repeats agree within 20 % (max/min of warm samples) in every cell; otherwise the cell is reported as noisy
  and cannot carry a threshold.

**What each outcome means (owner decision 1):** a clean knee below the cap → a measured fraction, rule lifted for
this Mac's class. No knee below the cap (P1 holds) → there is no fraction to measure on this machine; ADR 013 and the
`CLAUDE.md` rule stand, and the curve is the deliverable. Resident not faster (P0b refuted) → measured and declined.

**Correction before the first real run (smoke test on 20 rows only):** the harness reads this session's
`recommendedMaxWorkingSetSize` as **51.84 GB** and `maxBufferLength` as **38.88 GB** (still 0.75 of it), not the 55.7 /
41.7 GB recorded at the bring-up — the hint is not a machine constant. Ratios below use the value each run prints:
the full DM4 cube is ratio 0.55, the Au cube (39.9 GB float32) is above the cap and is truncated to ≤ 173 scan rows
(0.749); 174 rows is run once and **predicted refused**. The predictions above are otherwise unchanged ("0.72" reads
"the cap, 0.75"). Ladder: DM4 rows 60/120/180/240/300/330; Au rows 69/116/139/162/173(/174).

**Second correction, after the Au ladder ran (2026-09-30 17:30):** the "correction" above was my unit error, not a
moving hint. The harness prints GiB (51.84 GiB = 55.7 GB, 38.88 GiB = 41.7 GB); the bring-up numbers were right. So the
Au cube at full extent (178 rows, 39.9 GB = 37.2 GiB, ratio 0.718) is *under* the cap, the "174 rows refused"
prediction was wrong by construction (it was held), and the ladder as run tops out at 0.70, not 0.75. The TSV `ratio`
column was always bytes ÷ working set and is unaffected. Rung 178 (the whole file) is added; nothing above 0.718 can
be reached with the data at hand.
