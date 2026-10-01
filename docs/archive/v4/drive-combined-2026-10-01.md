# Combined drive — today's landed work on a scratch build of 237a1aaf, 2026-10-01

Driver Sonnet 5.5, pid-pinned (the owner's instance untouched; frame restored and read back). The supervisor (Opus 5.5) reviewed the four kept shots: `03-bragg-room` (TH: the ring hint with "Use 11 px" on the bullseye), `24b-crop` (DC: no Method row, "Limit object transmission to 1" checked by default — the higher-order toggle still present, removed by lane HO), `39-wrote` (X3: "Wrote gr_s2_b2.h5 · 50 × 50 × 64 × 64 · 41 MB" from the sheet with no dataset open), `59-acom-pos` (ACOM: template marks on the measured disks; a few weak outer reflections in background; no mirrored position was reachable — the UI shows no mirrored flag). Seen: TH, X3, R4 (no vignette, fit line without the RMS pair), DC, P2's 0.0° and provenance labels. Not reached: the mirrored overlay, the Reconstruction bar angle, the hover text, the resident sidebar row.

## The driver's report, verbatim

# Drive report — app: scratch build of commit 237a1aaf (R4 + DC), pid 14864, owner's instance pid 59748 untouched (14754 no longer existed)
| NN | action | seen | verdict |
| 01 | Cmd-O bullseye .h5 | loaded, Prepare, calibration not set | ok |
| 02 | Measure Origin & Probe | origin measured, "Probe: 6.84 px" | ok |
| 03 | Bragg Disks › Probe kernel | orange hint "Ring-shaped probe: Its outer edge is at 11 px (now 6.8 px)" + button "Use 11 px" | E PASS |
| 04 | click Use 11 px | hint + button gone, only Build Kernel remains | E PASS |
| 05 | Prepare | "Origin & probe … Probe: 11 px (Manual)" — radius changed to N | E PASS |
| 06-07 | open graphene, Measure Origin & Probe | origin measured, probe 25.3 px | ok |
| 08 | Bragg Disks › Probe kernel on graphene | only Source + Build Kernel; no ring hint | E negative PASS |
| 09-10 | enter Q 0,25 nm⁻¹ / R 0,5 nm / 80 kV | first attempt mis-aimed (focus loss + wrong y; one stray Clear Calibration dialog, Cancelled); redo OK | ok (driver errors, not app) |
| 11 | Measure R–Q rotation | Prepare row caption "0.0°", status bar "Rotation ✓ θ = 0.0°" (crop 11b) | A part 1 PASS (Prepare) |
| 12-17 | Reconstruction › Parallax: prepare, align 7/7 levels | aligned BF at level 7/7 (status "level 7/7 · bin 1 · 514 groups · 3.53 px max shift · error 0.0148 → 0.0148 · schedule complete"); no dark edge vignette, margin is a flat green | D parallax edge PASS (by eye) |
| 18 | Fit Aberrations | status "Recursive aberration fit ✓ · 7 terms · rotation −0.07°" — no RMS pair | D fit-line PASS |
| 19-20 | Correct Phase; Info scrolled | Provenance: Display domain / Full fit / Q highpass (Å⁻¹) / Q lowpass (Å⁻¹) / Quantitative status / Source product; label left value right, values short; "Source product" value drops to a second line (wrap); Sampling value reads "sampling 5 × 5 Å/px" (redundant word) | A provenance mostly PASS; 2 nits |
| 21 | hover over a value (CGEvent move) | screencapture -l does not capture tooltips; nothing visible | A hover UNVERIFIED |
| 22 | Parallax Settings | no Method row; no difference-map anything | D PASS |
| 23-24b | Single-slice ptychography › Advanced ptychography (crop 24b) | Iterations/Step/Norm min/…; "Limit object transmission to 1" CHECKED by default; no Method row | D clamp-default PASS |
| 25-26 | DPC & iDPC, Run DPC | Display picker only (Magnitude (detector px)); product badged Quantitative; no separate Reconstruction bar R-Q readout found in this room | A "Reconstruction bar 0.0°" NOT REACHED (no such bar seen) |
| 30 | plain launch, no dataset | sidebar Dataset group: "Open Dataset…", "Open with Option…", "Preprocess Raw…" | B sidebar PASS |
| 31 | toolbar Dataset menu | popup not capturable by window shot; AX tree lists Open Dataset…, Open with Options…, Preprocess Raw Data… ; File menu (AX) also lists "Preprocess Raw Data…" | B menus PASS (AX, not visual) |
| 32-35 | sidebar Preprocess → file panel "Choose the file to reduce. It is never changed." → graphene → sheet | sheet: title "Preprocess twisted_bilayer_graphene.hdf5", Source file + Choose…, three previews, Real-space crop (Scan stride), Diffraction binning (Bin factor), Hot pixels, Size, Output › Destination; stride 2x + bin 2x set | B sheet PASS |
| 36 | scrolled sheet | Output shape 50 × 50 × 64 × 64; Destination "not chosen"; Calibration readiness not seen in the visible top/bottom (middle not inspected) | B (1a absent w/o dataset) not fully verified |
| 37-39 | Write… → save panel (default folder = source folder!) → typed export dir | status "Wrote gr_s2_b2.h5 · 50 × 50 × 64 × 64 · 41 MB"; file in SP/driveC/export | B write PASS |
| 40 | open written file | "50 x 50 scan · 64 x 64 detector", 2,500 positions | B reopen PASS |
| 41-43 | File › Preprocess Raw Data… with dataset open | Source file reads "gr_s2_b2.h5 · current view"; Calibration warning "Not quantitative — still needed: …" present (readiness only with open dataset) | B pre-fill + 1a PASS |
| 50-52 | demo cube: Bragg Disks Build Kernel + Detect All Disks | 1,296 peaks, 9 per pattern | ok |
| 53-58 | Crystal Maps › Orientation; Materials-Project sheet cancelled; Import CIF Al_thronsen2024.cif; Run Full Orientation Map | "Physical ACOM result", IPF-Z map (almost all one red orientation, grey = below threshold), Fit overlay toggle on | C map PASS |
| 59 | click position (5,1), Fit overlay | overlay = orange x template marks; most x's sit centred on measured disks (fit overlay legend "measured × template · reliability 0.19"); 3-4 x's sit in empty background (templates with no disk) | C overlay partial |
| 60-61 | Info pane | provenance lists no "mirrored" field or per-position mirrored flag (only Friedel angle period 180, Interpretation physical); no position could be identified as "mirrored" | C mirrored-position NOT REACHED |
