# The owner's raw Al-Mg-Si cube, subsampled from the SSD (2026-09-29)

ROADMAP 3, first step. Source: `060_STEM SI.dm4` (28.56 GB; 330 × 330 scan, 256 × 256 detector, float32; q
0.1144 nm⁻¹/px, scan step 1.539 nm) on the owner's exFAT/FSKit SSD. Tool: `tools/dm4-parity-probe --subsample`
(`12cf8b5`, proved first on the 128 MB fixture). One job at a time, under `guard.sh` (kills the probe above 1.5 GB
phys_footprint or at critical memory pressure; the run script's RSS limit lifted because mapped file pages are clean).

| Step | Result |
|---|---|
| `--open-only` on the SSD | `readingOptions(forPath:)` answers alwaysMapped; patterns (0,0), (165,165), (329,329) read at footprint 3 MB — **the 2026-09-24 panic path is closed on the physical SSD itself**, not only on a disk image |
| `--subsample --stride 3` | 110 × 110 × 256 × 256 float32, 3.17 GB, written to `ROI_5/mac4dstem_subsampled/060_STEM_SI_stride3.h5` (originals untouched) in 34 s; peak footprint 53 MB; RSS 1.2 GB of clean mapped pages; memory pressure reached "warning" once, never critical |
| `--verify-subsample` | **12 100 / 12 100 kept patterns bit-identical**, 0 differing pixels; calibration q unchanged, scan step 4.618 nm (× 3); 39 s, footprint 17 MB |

The result keeps the full 256 × 256 detector — 4× finer diffraction sampling than the binned 64 × 64 file used so far.
Not yet opened in the app or analysed: the cube needs its own calibration (Q from the lattice, the ellipse at this
detector sampling — ADR 039's typed values were for the 4× binned detector).
