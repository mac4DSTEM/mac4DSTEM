# Disk detection grows GPU memory per tile — Gate D (2026-09-29)

Found on the owner's 3.2 GB raw stride-3 cube: the matrix-orientation probe, calling the app's
`DiskDetection.detectAll(data:)` (`Core/Analysis/TiledDiskDetection.swift`), reached 1.6–2.1 GB footprint and was
killed by the guard three times; `vmmap` showed IOAccelerator 770 MB in 22 tile-sized buffers. An `autoreleasepool`
around each tile (probe copy only) held ≈ 500 MB with identical peaks (`almgsi-raw-stride3-registration-2026-09-29.md`).

## Diagnosis

`detectAll(data:)` is an `async` loop: per tile it creates an `MTLBuffer` holding the tile (`makeBuffer(bytes:)`,
line ~126) and calls the synchronous resident detector (`detectAll(cube:…)`), which creates command buffers and
encoders. No autorelease pool drains inside the loop, so the per-tile autoreleased Metal objects — and through them
the tile buffers — survive until the scan ends. Memory then grows by about one tile per tile.

## Refuting observation

With a pool drained per tile (around the synchronous part: buffer, detection, peak copy), memory still grows by
about one tile per tile → the diagnosis is wrong (look at the prefetcher, `allPeaks`, or the detector's own caches).

## Experiment and prediction

A probe runs the app's own `DiskDetection.detectAll(data:)`, unmodified, on the Thronsen stride-3 cube (internal
disk, 171², 128² detector) and samples `phys_footprint` and the IOAccelerator region at each tile boundary, under
the footprint guard; then the same with the pool patch applied to a scratch copy.
**Predicted:** unpatched, footprint rises roughly linearly by ≈ one tile's bytes per tile (a guard kill counts as
confirmation); patched, it stays flat within one to two tiles' worth; the peaks are identical (count and a checksum).

## Then

Fix in Core (the pool per tile), a gated harness that fails when footprint grows by more than two tiles over a
multi-tile synthetic cube (broken first by removing the pool), an independent refuter on this diagnosis and the
logs, unit gate. Until it lands: **do not run Detect All Disks in the app on multi-GB cubes.**

## Experiment — the diagnosis HELD (2026-09-29; `mem-A.log`, `mem-B.log` + `.guard`; Sonnet runner, reviewed)

Thronsen A stride 3 (171², 128²), 0.15 % floor; tiles of 31 rows = 331 MB, 6 tiles. `phys_footprint` at each
tile's first tick (MB):

| tile | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| A — the app's own `detectAll(data:)` | 1087 | 1423 | 1757 | 2093 | 2095 | killed at 2602 |
| B — the same loop, a pool per tile | 1104 | 1127 | 1096 | 1102 | 1105 | 1107 |

A grows by one tile per tile (+336, +334, +336 MB; IOAccelerator 663 MB → 1.3 GB in 17 → 19 regions) until the
guard kills it at 2.6 GB, 7 s in; B holds one 332 MB IOAccelerator region and finishes in 7.2 s (691 682 peaks,
FNV checksum d7a0da6cd4c29952). **Not only big cubes: the everyday Thronsen cube reaches > 2.6 GB in the app.**
Gaps: A never completed, so A = B peaks is unchecked here (the probe's 8-row crop matched last night); both runs
start at ≈ 0.93 GB after the origin fit, unexplained. The fix (pool per tile in Core, a memory harness broken first,
refuter, unit gate) is overnight item A1.

