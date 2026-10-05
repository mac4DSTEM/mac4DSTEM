# v5.0 WP1 — spectrum-image readers, headless — pre-registration (2026-10-05; NOT started)

Queue line: `ROADMAP.md` › v5.0 (ADR 052, 053). Written before any code or run. This is the first piece of the
Spectroscopy room that needs none of the following:

- **No UI.** So neither the frozen shell (ADR 035) nor the "Unverified on screen" rule applies.
- **No quantification.** So it does not wait on the design session (`quant-design-brief-2026-10-05.md`).
- **No new acquisition.** It runs on the owner's existing Velox files.

## What it reads (owner, 2026-10-05)

Three cases, all in scope:

- **Plain Velox EDX spectrum images.** This is most of his data. One is copied to `References/EDX/` (gitignored).
- **GMS 4D-STEM runs beside separate Velox EDX maps.**
- **A GMS run with 4D-STEM, EDX and (optionally) EELS together.** GMS drives the Super-X in his lab (ADR 053, amended);
  he records the first such run on his next TEM visit.

WP1 delivers the Velox reader in full and the GMS reader's structure. The GMS EDS-SI decode is finished against his
first joint file, because no such file exists yet.

## What it changes, and who owns the state

New `Core/Data/` types in `DSTEMCore`. They hold no `AppState` state, so nothing in the app sees them until the room
lands.

1. **`VeloxEMDReader`** for Velox EMD v9 and v11. It reads:
   - **`SpectrumStream`**: uint16 values, with 65535 ending each pixel. It is decoded once into a per-pixel sparse
     event store (CSR, channel → count), with a frame range chosen at decode. The default is all frames, as in Velox's
     own frame trimming.
   - **The HAADF frame stack** on the spectrum grid.
   - **The energy axis** (dispersion and offset).
   - **The Super-X geometry**: azimuth and elevation per segment, plus the holder type. ADR 053 item 5 needs it.
   - **Stage α/β, dwell, screen current, scan size, `ScanArea` and `ScanRotation`.**
   - **The per-frame `ScanTransformation`**, recorded only (Velox already drift-corrects; dossier finding 2).

   Velox's derived element maps and its pruned `SpectrumImage` are **not** read. The app computes its own from the
   stream, and the pruned format is unreadable (dossier §3).
2. **GMS `.dm4` "one experiment" grouping** in `DM4Reader`. It lists every image object of an `STEM SI` file with its
   role (`Experiment keywords.2.Label`: Survey, Scan Signal, EELS, Diffraction, EDS) and its `Spectrum Image Rect` on the
   survey (`reports/gms.md` §2). Today the reader returns the 4D object alone and drops the survey (`grep -i survey` over
   `*.swift`: no match, 2026-10-05).
3. **The Velox misread is closed.** `H5Reader.discoverPrimaryDataset` stops offering a Velox EMD as a one-row 4D cube
   (`open-items.md` "Velox `.emd` opens as a one-row cube"). The file is routed to `VeloxEMDReader` instead. This is the
   one change to shipped behaviour, so it goes through **Gate B**.

**Gate D does not apply.** There is no defect of unknown cause, and no shipped number moves. A reader *creates* counts,
so the bar is bit parity with a reference reader, set below.

## The reference, and the fixtures

**rosettasciio 0.14.0** (`049e7d70`, GPL-3.0, as the app) is the reference reader. Its own test data carries `.npy`
truth arrays: `fei_emd_si.npy`, `fei_emd_si_frame.npy`, `fei_emd_spectrum.npy`. Its Velox v11 zips (`velox_emd_version11`,
`velox_emd_v11_elementSelection`, `velox_EELS_EDS`) are 2–6 MB each, too big for the 1 MiB tracked-file guard. So a
`tools/lib/fetch-rsciio.sh` pins the commit into `References/` (gitignored), the same way `fetch-py4dstem.sh` does.
This is decision 1 below.

The owner's `SI HAADF 1456 77000 x 20260420.emd` (1.74 GB, EMD v9, Talos F200X, 200 kV, 1.83 nA, dwell 6.25 µs,
1607 frames, 4096 channels) runs as a **diagnostic, never a gate**: it is private and not reproducible from the repo.

## Predictions, stated before any code

**P1. Parity.** For every public rsciio Velox file, the Swift-decoded spectrum image (frames summed) equals rsciio's
`sum_frames=True` array **count for count**. The HAADF stack equals rsciio's image array. The energy axis offset and
scale match to float32. **Refuted if** any single count differs. A mismatch in the axis is a defect, not a tolerance.

**P2. The sub-area raster.** In the owner's file, `AcquisitionSettings.RasterScanDefinition` is 1024 × 1024, while the
image stacks are 926 × 215 and `Scan.ScanArea` is a sub-rectangle (left 0.400, right 0.610, top 0.062, bottom 0.966).
Prediction: the stream carries only the 926 × 215 sub-area's pixels, so the pixel ends per frame equal 926 × 215.
**Refuted if** they equal 1024², or neither. Then the reader follows whatever rsciio does, and that behaviour is recorded
here as a dated addendum.

**P3. Speed and memory.** On this M5 Pro, the 1456 stream (408 M uint16 values) decodes in under 10 s. The event store
stays under 10 % of the dense size (926 × 215 × 4096 × 4 bytes ≈ 3.3 GB). **Refuted if** either bound fails. Then V5-4's
CSR-cache question is decided by this number, and that is the reason it is measured here.

**P4. Totals.** The summed spectrum's total counts equal the stream's non-marker value count, and equal rsciio's total on
1456 (diagnostic).

## Tests written before the code (each broken first)

- **Parity:** the public files against their `.npy` truth arrays. Break it: drop the last pixel of each frame, and the
  test goes red.
- **Marker handling:** a 2-pixel, 2-frame synthetic stream with an empty pixel (two markers in a row). Break it: treat a
  marker as channel 65535.
- **Frame range:** frames 2–3 of the 10-frame fixture equal rsciio with `first_frame` / `last_frame`. Break it: an
  off-by-one in the range.
- **Super-X geometry:** read from the 4-detector fixture, and equal to its metadata. Break it: swap azimuth and elevation.
- **Discovery:** an H5Reader-style probe of each Velox file returns "Velox spectrum image", never a 4D cube. Break it:
  restore the old ordering.
- **GMS grouping:** on the owner's `055_STEM SI.dm4` header (diagnostic) and on a synthetic tag tree (gated), the roles
  and `Spectrum Image Rect` are listed.

The gates are `run-tests.sh core` and `unit`, with test names reconciled against the expected delta, then Gate B. An
independent reviewer reads the parity harness's own output, not the diff.

## Decisions owed to the owner

1. **Fetch the rsciio fixtures by script into `References/` (recommended), or commit them under Git LFS.** The repo has
   no LFS today. The script keeps the 1 MiB guard intact.
2. **Velox's own element maps: ignore them, and compute from the stream (recommended).** Showing them would only be a
   comparison against Velox's quantification. The design session may still ask for them, as that comparison.
3. **Frames: sum at decode with a chosen range (recommended), or keep per-frame events.** Per-frame events would allow
   time-resolved "frame peel-back" as in Velox. They cost about the stream's size again, so they are deferred.

## Not in WP1

The room and its mock, quantification, the registration record, MSA and `.hspy` (WP1b, small), Bruker `.bcf`, and
Oxford `.h5oina`.

## Addendum 2026-10-05: lane B outcome

- **Where the scan's rectangle lives.** `Spectrum Image Rect` (top, left, bottom, right) sits on the SI objects, not on
  the survey: `SI.Acquisition.Survey Image.Spectrum Image Rect`, next to `.Unique Image ID`. Measured on the owner's 036
  and 134. Its aspect equals the scan's (0.693 / 0.611).
- **Bit parity with rsciio.** Both surveys match byte for byte (max |Δ| 0).
- **Header-only listing.** It goes through a `FileHandle` on every volume: 212 kB read for the 17 GB 036.
- **The shipped reader's string-tag fault.** The independent review found the type-18 desync in `DM4Reader`
  (`open-items.md`), and lane B reproduced it on a synthetic file.
