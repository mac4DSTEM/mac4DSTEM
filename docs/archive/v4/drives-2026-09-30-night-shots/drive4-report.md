# DRIVE 4 report, started Wed Sep 30 10:13:32 CEST 2026
App: drive/app4 (binary 10:08). md5 before: md5-d4-before.txt. Disk 3393 MB free, swap total = 3072.00M  used = 2456.50M  free = 615.50M  (encrypted)
## Steps
### B4-a (s18 legacy sidecar, e00575555c..., plain open via open -n -a app file, pid 97147) - SEEN
- 01-legacy-open.png: opened whole (100 x 100), Prepare; sidebar Session heading reads "Loaded with the dataset — from earlier analysis" (AX sidebar.session too), rows AlMgSi_demo.mac4dstem.h5 and Calibration. Origin/Q/R "From session", orange "Saved origin not applied in full here" line as in drive 3. NOT "Saved". [PASS]
- Dataset toolbar menu > Save Calibration to Session Sidecar (AX press [1.6.0.1], app frontmost): no sheet appeared (sidecar already known); 02-after-menu.png: heading now reads "Saved with the dataset", status bar "Saved calibration -> AlMgSi_demo.ma...", Last run "Session calibration - 0 s". Sidecar md5 changed to e11df48b... (expected, scratch copy under s18/data). [PASS]
- Quit (Cmd-Q, pid gone); restored legacy sidecar from d2b-bak/sidecar.legacy.h5, md5 e00575555cae0eaa95f0e84dd472e92e
### B4-b (drive/data3 copy with the drive-3 sidecar a64c8ed0..., pid 97366) - SEEN
- 03-data3-open.png: plain open; Session heading "Loaded with the dataset — from earlier analysis"; Origin/Q/R "From session"; no orange line. [PASS]
- Dataset menu > Save Calibration to Session Sidecar (AX press, no sheet): 04-data3-saved.png: heading "Saved with the dataset", status "Saved calibration -> AlMgSi_demo.ma...". data3 sidecar md5 now c622f505... (scratch, rewritten as expected). [PASS]
### C1 (--demo-fixture, pid 97450; window sat on a second display at x=-1967, screenshots and ev clicks still worked) - SEEN
- Imaging opened by a real click (AX press on the sidebar label did nothing). 06-imaging.png: Shape already Annulus (2nd icon selected), AX "Aperture inner radius" v=0, centre 32,32. Zoom 06c-zoom.png: white centre dot and the cyan handle touching side by side, cyan directly right, one handle diameter (~13 pt) centre to centre. [PASS]
- Dragged the white centre dot (+40,+20 pt): 07-centre-dragged.png: yellow ring moved with it, both dots moved together, real-space image changed; AX centre 32,32 -> 38,35. [PASS]
- Dragged the cyan handle outward (+50 pt): 08-inner-dragged.png: dashed cyan inner circle appears, following the handle; AX inner radius 0 -> 9; real-space image changed (colour scale 6658-8348). [PASS]
- Note: the inner-radius "readout" is only the AX slider value; no visible number in the Detector panel (Shape / Preset rows only). Observation, not a defect claim.
- Clumsy: AX press on sidebar static text (Imaging) does not navigate; real click needed.
## Step table
| step | expected | seen | shots | result |
|---|---|---|---|---|
| B4-a open whole, legacy sidecar (e0057555) | Session "Loaded with the dataset — from earlier analysis" | exactly that | 01 | PASS |
| B4-a Save Calibration to Session Sidecar | "Saved with the dataset" | "Saved with the dataset", status "Saved calibration -> ..." | 02 | PASS |
| B4-a restore legacy sidecar | md5 e00575555c... | e00575555cae0eaa95f0e84dd472e92e | - | PASS |
| B4-b reopen data3 (drive-3 sidecar) | "Loaded ... from earlier analysis" | exactly that | 03 | PASS |
| B4-b save calibration again | "Saved with the dataset" | yes | 04 | PASS |
| C1 inner handle beside centre dot at r=0 | ~1 handle diameter right | touching, ~13 pt right | 06, 06c | PASS |
| C1 drag centre dot | aperture moves | ring + handle move, centre 32,32 -> 38,35 | 07 | PASS |
| C1 drag cyan handle out | inner radius rises from 0, dashed circle follows | 0 -> 9, dashed cyan circle | 08 | PASS |
| End | window {0,33} 1470x923, Cmd-Q, pid gone | position/size read back 0,33 / 1470,923; pid 97450 gone | - | done |
## md5 before / after (drive/md5-d4-before.txt, md5-d4-after.txt)
- data3/AlMgSi_demo.h5 af58d987... unchanged; s18 data h5 af58d987... unchanged; s18 sidecar e00575555c... unchanged (restored); d2b-bak legacy e00575555c... unchanged; References demo h5 af58d987... untouched (never opened).
- data3 sidecar a64c8ed0... -> c622f505... (CHANGED, by design: step B4-b saved calibration into the scratch copy; not restored).
- Clipboard unchanged (never pasted). No crash, no log query needed.
