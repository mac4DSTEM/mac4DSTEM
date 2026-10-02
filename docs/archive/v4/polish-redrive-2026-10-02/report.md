# Slot 4½ re-drive — scratch build of e79d4197, 2026-10-02

Driver Sonnet 5.5, pid-pinned, no other instance running, Retina 2×. The supervisor (Opus 5.5) reviewed the six kept shots in `shots/`:
`22-pprev` (parallax BF preview shows the lattice, not solid red — the SCAN inset, now top-right, still covers part of it), `06-info`
(real-space preview has contrast; summary names the bright-field disk sum), `45-strain` (badge kept; the new line wraps to two lines),
`53-angle` (in-plane note, "Re-run Full Orientation Map", "Mirrored No"), `15c` (numbered group swatches), `33-demo` (opening a cube in the
DPC room re-runs DPC on the new cube — the opening pass, not a leak — and the wheel then stays on screen in Prepare). Found and handled in the
session: the stale map in Strain / Orientation / Reconstruction (lane J); a crash after Compute Strain (AppKit layout exception, not
reproduced; open-items); the β″ preset's CIF picker would not enable Open (code unchanged this session; open-items).

## The driver's report, verbatim

# Slot 4.5 re-drive report
Commit e79d4197; display Retina 2x (3024x1964); other instances at start: none; pid 82839
1 Preprocess menu: window+no dataset = enabled (true); NO window = disabled (false, queried twice) -> FAIL for no-window case; sidebar row 'Preprocess…' PASS (shot 01-launch). Window 1512x949 at launch.
NOTE: File>New Dataset Window after closing the only window opened TWO windows (1512x949 + 1280x800); closed the extra (shots 02a/02b). Possible defect: duplicate window.
2a Configurator real-space preview: visible grey image, caption 'real space: bright-field disk sum' PASS (shot 04-opts)
2 Info>Preview Real space: visible grey image, summary says "bright-field disk sum" -> PASS (06-info). Window stayed 1512x949 after load.
3a Prepare rows: single line "Quantitative in 0 of 6 steps", Voltage among rows, verb "Calibrate Origin" (toolbar + row) -> PASS (05-loaded)
3b R=0,5 nm before origin: virtual image scale bar '10 nm' (not px) PASS (07-r05)
3c Q=0,25: subtitle '0,25 nm⁻¹/px' PASS (08-qcrop)
3d Ellipse row (fit run by mis-click): 'a 23,81 px · b 21,77 px · θ 47.4°' PASS (09-origin). Panel scrolled itself so clicks landed on ellipse button
3e Origin calibrated (probe 25.3 px); verb 'Calibrate Origin' then 'Re-calibrate Origin' PASS (10-origin); window still 1512x949
4 BF preset: circle = beam edge (r~25 px), dark halo outline readable over bright disk -> PASS (12c). ADF: 3r=76px > detector half-width 64, so fractions fallback ring (~0.6r..1.4r of beam), dashed blue + dark halo readable -> PASS as fallback by design; the 3r..6r branch NOT REACHED (needs a larger detector) (13c). Did not check whether the 'no beam' one-line note appears (beam was measured).
5a Entering Groups with no result: 'No Result Yet' placeholder, no stale map PASS (14-groups)
5b Groups legend: numbered swatches 1-6 (not a bar), beside scale bar, translucent panel -> PASS (15c). Window still 1512x949
NEW? Reconstruction>DPC before running shows the Diffraction-groups map in the right pane (carried from Groups room), title 'Diffraction groups (k = 6)' (16-recon)
6a DPC run: toolbar verb 'Re-run DPC' PASS (17-dpc)
6b R-Q rotation measured shows '0.0°' (no '−0.0°') PASS (20c); voltage 80 kV set for parallax
6c Parallax Prepare Preview: BF preview pane shows an image (not red), SCAN inset top-right PASS (22-pprev)
6d Align 7/7 levels, Fit Aberrations: Last run caption 'Aberration fit — 0 s' (not Parallax alignment) PASS; status 'rotation -0.07°' (no -0.0°) PASS (25-fit)
7a Results Export Data…: Save panel (default folder = dataset folder 4D_STEM_Datacubes; redirected by me), file gr_data.h5 written 550 KB, status 'Exported Parallax aligned BF → gr_data.h5' PASS (28-saved). NOTE: typing '/' in the Save-As name field opens Go-to-folder sheet (std macOS)
7b DPC colour wheel shown: Export Data… greyed out (disabled) PASS (31-wheel); hover tooltip NOT VERIFIED (Claude app held the foreground, no tooltip captured, 32-hover)
NEW? Opening demo cube in the same window (via File>Open Dataset) ran DPC by itself: right pane 'DPC color wheel 100x100', status 'DPC ✓ Color Wheel vs global center, Last run DPC 1 s' on Prepare (33-demo) - carries last display + auto-runs?
8a Build kernel: 'Last run · Probe kernel — 0 s' PASS; funnel '131 candidates → 9 accepted' + words line PASS (35-kernel)
8b Labels: 2 disks clicked, Export Labels… opens Save panel (title 'Export Disk-Centre Labels', default name AlMgSi_demo-centres-2026-10-02T…, default folder = demo-dataset), labels.json written 389 B, status 'Exported disk-centre labels → labels.json' PASS (38-lpanel, 39-lsaved)
NEW? Crystal Maps>Strain with no strain result still shows 'DPC color wheel' (from the previous dataset/room) in the right pane (40-crystal) - stale product from another room
CRASH (NEW, high): app (pid 82839) died right after clicking Compute Strain on demo cube after full Detect All Disks (Strain room, Whole-scan mean/Automatic). ~/Library/Logs/DiagnosticReports/mac4DSTEM-2026-10-02-133933.ips: EXC_BREAKPOINT, NSException thrown from -[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints] during NSView layout (AppKit 'update constraints during layout' crash). Retest once next.
9a Strain (2nd launch, pid 84191): 'Quantitative' badge + 'Components along detector x/y — R–Q rotation not calibrated' PASS (45-strain). Crash NOT reproduced on retest (first crash came after labels/export + DPC-wheel carryover session) -> filed as intermittent
9b ACOM: requirement shown once (Orientation, before CIF; gone after import 47-cif); Import CIF Al ok; Preview (48-prev) + Full scan: toolbar 'Re-run Full Orientation Map' PASS (50-full); picked pixel: Info 'Mirrored No' (51-pick) (no Yes pixel found, Yes variant NOT REACHED); Display 'In-plane angle' note 'Angle relative to the matched template — a mirrored match (Mirrored: Yes) is measured from the mirror image (py4DSTEM's convention)…' PASS (53-angle). Note: Orientation room before running showed the Strain map in the right pane (46-orient) - map of another room.
10a Phase mapping before run: 'No Result Yet', no stale Strain/ACOM map PASS; Max |q| '1,60' PASS (54-phase)
10b Add Phase menu on already-added Al CIF: 'Imported: Al_thronsen2024 (another zone axis)' PASS (66-addmenu2). Phase preset 'Al-Mg-Si (β″ needles)…' opens a file Open panel whose Open stays disabled for folders AND CIF files (no hint visible which item it wants; 58/59/61/63) -> preset, zone-axis rows, Map Phases legend, SCAN inset NOT REACHED. Possible defect: unclear picker/ no prompt text.
11 Bullseye: scale bars '50 px' / '10 px' (no [pix]); Prepare text 'Reciprocal dimensions remain in pixels (1 px/px)' (no 'lacks supported physical units ([pix])') PASS (67-bull)
12 Window size: stayed 1512x949 at 0,33 at every step (no self-resize), except File>New Dataset Window after closing opened a second 1280x800 window.
## NEW defects
- App crash (EXC_BREAKPOINT, AppKit layout 'needs update constraints' NSException) right after Compute Strain in a long session (labels export, DPC wheel carry-over); not reproduced on retry - DiagnosticReports/mac4DSTEM-2026-10-02-133933.ips
- File>New Dataset Window with no window opens two windows (02a/02b)
- File>Preprocess Raw Data… disabled when no window exists (item 1 FAIL for no-window case)
- Stale products from other rooms: Reconstruction/Crystal Maps rooms show Groups map (16-recon), DPC wheel (33-demo, 40-crystal), Strain map (46-orient) before own result
- Phase preset file picker: Open disabled for every item, no hint (58-63)
- Ellipse fit ran from a mis-click because the Prepare panel scrolled/re-laid out after Q/R entry (minor)
