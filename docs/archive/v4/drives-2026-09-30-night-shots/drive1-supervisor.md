# DRIVE 1 supervisor verdict (Fable 5.1, read-only) — every cited shot opened; pixel diffs in sup-d1/
Method: all 85 shots downscaled to sup-d1/ (sips -Z 1400); crops/diffs done on the full-res originals with PIL. md5 before/after files agree with the report (data copies unchanged; new sidecar 42f347b3).

## Step table (report row → verdict, shot)
| row | verdict | what the shot shows |
| S12a fresh ranking | VERIFIED | 16: rows [-1 0 0]/[0 -1 0]/[0 0 -1] 38 % · 0.0177 Å⁻¹, no warning, footer "Matrix zone axis — 0 s" |
| S12a tolerance 0,02→0,04 | VERIFIED | 21d: Matrix removal 0,040 (focus ring), rows replaced by orange "The matching tolerance changed since this ranking — fit again" |
| S12a tolerance back | VERIFIED | 22: 0,020, three rows back, no warning |
| S12a matrix change | VERIFIED | 24: Matrix = beta_double_prime_Mg5Si6, orange "The matrix phase changed since this ranking — fit again"; β″ row reads "matrix · zone [0 1 0]" |
| S12a matrix back | VERIFIED | 25b: Aluminium (FCC), rows back |
| S12a identical origin re-run | VERIFIED | 18b: "Last run · Origin calibration — 3 s", Origin & probe row still Fit RMS 0.001807 px; 19: same footer, rows still shown, no warning (17↔18 differ only in the footer MB readout, as the report says) |
| S12b min 1→5 / 20 | VERIFIED | 30: field 5, picture and 6/3 counts unchanged (pane pixel-identical to 29); 31: field 20, six orange squares drawn dim brown, "0 objects · 0,00 /µm²", "Not counted: 6 under 20 px." |
| S12b lineage node | VERIFIED | 34: s6 "Minimum object area px 20", Recorded 23:28; 35: "5", Recorded 23:29, still "6 runs" |
| S12c "In memory" title | PARTIAL on 04 (section scrolled off, not in shot) / VERIFIED on 05 | 05: "In memory" with five empty circles; Product "Origin — Computed this session" |
| S12c origin / detect rows | VERIFIED | 07: "Origin calibration — fitted here" (green); 10: "Bragg disks — 93209 peaks" (green), status bar "93,209 peaks" |
| S12c save + reopen | VERIFIED | 51: "Origin calibration — restored from session", "93209 peaks · restored from session"; footer "Disks restored from the session — 93,209 peaks (detected 29. Sep 2026)"; "Bra/gg/disk/s" wrap is real |
| S12d stripe on objects + legend | VERIFIED | 28: "of which challenged 46.0 %" hatched swatch; my own pane crops of 27 (map) vs 29 (objects): 0 differing pixels in the striped region, only the scale-bar corner (83×81 px) differs; the driver's 27z/29z are byte-identical (same md5) |
| S12e evidence sentence | VERIFIED (on click) | 43: Evidence ends exactly "…so "Show claimed disks" rings the disks it explains as unexplained."; footer "Pattern x 77, y 39"; diffraction legend "Unexplained · 8". Hover (40–42) never changes the Evidence row, as reported |
| S23 restored origin, no wash | NOT EXERCISED (correctly reported) | 53: sidebar "A saved session beside this dataset could not be read." (report wrote "restored" — wording nit); Info shows errno = 1 'Operation not permitted' |
| S23 live wash + legend | VERIFIED | 56/56z: grey patches, legend "891 of 8400 positions excluded by the origin fit's robust trim"; 57: "Positions used 7509 of 8400 positions (11% excluded as outliers)"; 7509+891=8400 |
| S23 overlay off / on | VERIFIED | 58: chip, crosshair, wash and legend gone (pane diff vs 56: 34,486 px); 59: back, pane diff vs 56: 0 px |
| S23 Results | VERIFIED | 60: clean image, no wash/legend, Export PNG / Save to Results only |
| S23 zoom | NOT SHOWN (honestly reported) | 61/61-ctrl/61b/61c differ from 59 by 123 scattered px — no zoom occurred; substitute 63: image and wash rotated together, "20 pixels" bar; 64: back (17 px from 56) |

## The clumsy list against its shots
1 no re-measure on the Origin & probe row — REAL (17: only Fit Detector Ellipse / Measure R–Q Rotation; Calibrate Origin lives under Fit diagnostics, 18b).
2 "93209" ungrouped vs "93,209" — REAL (10, 51). 3 "Matrix removal" label vs "matching tolerance" warning — REAL (both in 21d).
4 two identical "beta_double_prime_Mg5Si6" Matrix entries — REAL (23). 5 lineage lists s4 above s2/s3 — REAL (32/34).
6 no way back from Precipitate Objects to the map — PARTIAL (39 shows the pane menu is orientation-only; absence of a control is not provable from a shot).
7 Evidence help text "under the cursor" vs click — PARTIAL (hover/click behaviour shown in 40–43; the help text itself is a source claim, in no shot).
8 "Loaded with the dataset — from earlier analysis" right after saving — REAL (46). 9 "Bragg disks" one syllable per line — REAL (51).
10 Au cube: "Phase map (0 candidates) / No Result Yet" in Prepare before any phase work — REAL (53, 54; 55 shows Imaging's own empty state).
Also real: saving the result silently added a BraggVectors row (47); footer status truncation (15, 16, 27).

## Per item
S12a — ON-SCREEN VERIFIED (16, 21d, 22, 24, 25b); identical-origin re-fit stays CURRENT (18b, 19). Tolerance was exercised at 0,04, not the brief's 0,03 (typing never committed; paste did) — the claim holds either way.
S12b — ON-SCREEN VERIFIED at minimum 20 (31) and for the node 20→5 (34, 35). At 5 nothing dims because no object is <5 px (30); the brief's "1→5 dims" is a property of this dataset, not a defect.
S12c — ON-SCREEN VERIFIED (05, 07, 10, 51) — with the "Bragg disks" wrap defect and the ungrouped count on the same shots.
S12d — ON-SCREEN VERIFIED (28 legend row; 27 vs 29 pane crop identical in the striped region).
S12e — ON-SCREEN VERIFIED on a click (43); PARTIAL against the brief's "hover" — hover updates only the pane readout (40–42).
S23 — wash + legend 891 of 8400 and Positions used 7509: ON-SCREEN VERIFIED (56, 56z, 57); toggle: VERIFIED (58, 59); Results: VERIFIED (60); zoom: NOT VERIFIED (61*), rotation substitute VERIFIED (63, 64); restored-origin-no-wash branch: NOT VERIFIED (sidecar EPERM on the copy, 53).

## The three post-drive string changes — re-drive needed, and one is not what it claims
All three are drawn text (PhaseMappingProduct.swift mtime 23:40, SessionProductOrigin.swift 23:46 — both after the drive ended 23:40). By the owner's rule they are unverified until a drive sees them: the S12a tolerance-warning row and the S12c detect/restore rows must be re-driven before any "verified" claim (three actions: change Matrix removal, Detect All Disks → Info, reopen the copy → Info; ~10 min).
DEFECT before that re-drive: SessionProductOrigin.braggDisks comments "the same grouped count as the status bar" but computes `String(peakCount)` → "93209 peaks"; SessionProductOriginTests.swift:42 expects "93,209 peaks" and will go red. Either the edit is unfinished or the test is ahead of the code — resolve, run the unit gate, then drive.
Also: "· restored" shortens the detail but the wrap in 51 is a layout-priority defect (label yields to detail); a shorter string may still wrap at a narrower inspector — only the re-drive can say.
