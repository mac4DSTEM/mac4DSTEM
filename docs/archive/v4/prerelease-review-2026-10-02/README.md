# Pre-release review of v4.1 — 2026-10-02 (Slot 4¾)

Owner brief (2026-10-01): whole-app review with fresh eyes before v4.1.0 — six read-only reviewers, one scope each, high and
medium only, every finding at file:line with a failure scenario; merged into one ranked list; high ones fixed in lanes, owner calls
on one sheet. Reviewers: six Opus 5.5 agents on HEAD `b3461496` (scopes: a data safety, b science claims, c concurrency, d memory and
large cubes, e first-run UX, f docs and claims). Every finding was then checked by an independent Fable 5.1 verifier told to refute
it (batches of ≤ 4). Result: **36 findings, 35 CONFIRMED, 1 REFUTED (c3)**. Full findings with the reviewers' evidence and the
verifiers' traces: [`findings.json`](findings.json). Decision sheet (answered): [`../owner-decisions-2026-10-02-review.json`](../owner-decisions-2026-10-02-review.json).

## Ranked list (verifier severity; a1/b5/e1 are one root cause)

| id | severity | verdict | where | finding | disposition |
|---|---|---|---|---|---|
| a1 | high | CONFIRMED | `mac4DSTEM/Support/ResultExport.swift:1027` | The sidecar save panels and Export Scientific Bundle can replace the source dataset (CR3's refusal only covers Preprocess and Export Data…) | lane A |
| a2 | high | CONFIRMED | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:204` | The sidecar path is derived from the file stem only, so scan.dm4 and scan.h5 in one folder share one session file, and nothing in the sidecar says which source it belongs to | card D1 → owner c (leave); lane B patch archived, not shipped |
| a3 | high | CONFIRMED | `mac4DSTEM/Support/ResultExport.swift:1204` | Hand-clicked labels the app refused to restore are silently overwritten by the next Save to Sidecar or Save Calibration | lane A |
| a4 | high | CONFIRMED | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1806` | A sidecar that exists but cannot be opened at write time is treated as absent, and a fresh file is renamed over it | lane A |
| b1 | high | CONFIRMED | `mac4DSTEM/App/AppState+PhaseContrast.swift:474` | Ptychography seed status prints the calibrated R–Q rotation in the app's internal sign, opposite to the Prepare row, and computes the 'apart' angle that decides the defocus sign from that | lane C (Gate D) |
| b5 | high | CONFIRMED | `mac4DSTEM/Support/ResultExport.swift:373` | Export Scientific Bundle has no source/sidecar destination refusal; its rename can replace the dataset or the session sidecar | lane A (same root as a1) |
| c1 | high | CONFIRMED | `mac4DSTEM/App/AppState+DiskDetection.swift:422` | A Bragg vector map that lands after a room switch is labelled with the current room's frame, sampling and provenance, and Bragg Disks keeps that label | lane E |
| d1 | high | CONFIRMED | `mac4DSTEM/Core/Data/FourDArray.swift:367` | A binned view sizes streaming tiles by post-bin bytes but every reader allocates the pre-bin tile: bin² (4x/16x/64x) blow-up of the 'bounded' transient | lane D (Gate D) |
| e1 | high | CONFIRMED | `mac4DSTEM/Support/ResultExport.swift:364` | Results › Export Bundle can replace the source cube or its session sidecar, the one .h5 writer left without the destination refusal | lane A (same root as a1) |
| f1 | high | CONFIRMED | `../website/privacy.html:58` | The published privacy policy says the app makes no network requests, but the Materials Project importer (shipped in v4.0.0) sends the user's API key to api.materialsproject.org | card W1 → owner c (leave the website) |
| f2 | high | CONFIRMED | `SECURITY.md:3` | SECURITY.md says the app makes no network connections and stores nothing outside the files it writes, which is false since v4.0.0 | lane G (SECURITY.md) |
| f3 | high | CONFIRMED | `README.md:74` | The README's CI badge and its 'four jobs on every push' claim are false: the badge has been red on every push since v4.0.0, and the unit job never runs | card R3 → owner a; lane R |
| a5 | medium | CONFIRMED | `mac4DSTEM/Session/SessionGates.swift:188` | A save after promote (or after opening a different configured view) relabels every carried result with the new view: the restore-failure gate ignores a known view mismatch | card D3 → owner a; lane I |
| a6 | medium | CONFIRMED | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2036` | Two windows on the same dataset: the last save silently replaces the other window's recipe, lineage, calibration and labels | card D2 → owner a; lane I |
| b2 | medium | CONFIRMED | `mac4DSTEM/Support/ResultExport.swift:277` | Exported phase-map / precipitate-objects PNG burns no 'unvalidated' on its face | lane F |
| b3 | medium | CONFIRMED | `mac4DSTEM/App/AppState+DPC.swift:132` | DPC angle / colour-wheel products are labelled Quantitative but carry no frame: detector-frame and scan-frame angles export identically | lane F |
| c2 | medium | CONFIRMED | `mac4DSTEM/App/AppState+DiskDetection.swift:173` | The vacuum-scan probe kernel has no epoch check: built on dataset A, it lands on dataset B, and its wrong detector size trips a precondition | lane E |
| c4 | medium | CONFIRMED | `mac4DSTEM/Support/ResultExport.swift:1237` | Opening another dataset while a sidecar save runs cancels the save silently, and labels and results that existed only in memory are lost | lane A |
| d2 | medium | CONFIRMED | `mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:320` | Phase-contrast budget is checked per stage while earlier stage products stay held: parallax level 2+ peaks at ~2x the 'half of RAM' limit, i.e. all of physical RAM | lane C |
| e2 | medium | CONFIRMED | `mac4DSTEM/UI/PhaseMappingSettings.swift:470` | Phase mapping › Add Phase › From CIF file… adds the wrong phase (the last imported model) when the CIF is refused or was imported before | lane F |
| e3 | medium | CONFIRMED | `mac4DSTEM/App/AppState+MaterialsProject.swift:130` | Materials Project Fetch with no network shows a raw NSError dump in the sheet | lane F |
| e5 | medium | CONFIRMED | `mac4DSTEM/UI/MapSettings.swift:463` | Labels' "Save to Sidecar" is not gated on the sidecar-rewrite refusal, and the refusal it then raises names a control that does not exist | lane A |
| e6 | medium | CONFIRMED | `mac4DSTEM/App/mac4DSTEMApp.swift:157` | Analysis › Run Current Task (⌘R) skips the readiness check, so it silently does nothing in several rooms | lane F |
| e8 | medium | CONFIRMED | `mac4DSTEM/UI/ContentView.swift:114` | The one error alert offers "Open Another…" for every error, including CIF refusals, export failures and sidecar refusals | card U1 → owner b; lane I |
| e9 | medium | CONFIRMED | `mac4DSTEM/App/ProductWorkflow.swift:523` | Requirement and help text sends the user to the "tools panel" for controls that live in the inspector | lane F |
| e10 | medium | CONFIRMED | `mac4DSTEM/UI/WorkspaceSidebar.swift:392` | The sidebar says "Nothing saved yet" directly under the warning that a saved session could not be read | lane A |
| f4 | medium | CONFIRMED | `README.md:59` | README, the website and architecture.md advertise orientation mapping 'against a validated catalogue', which the app has not offered since v4.0.0 | lane G (README, architecture; website left per W1) |
| f5 | medium | CONFIRMED | `README.md:15` | The README hero screenshot is the v2.5.0 interface (2026-09-04), and its caption names a workspace the image does not show | lane G (caption); a v4.1 screenshot owed |
| f6 | medium | CONFIRMED | `../website/support.html:58` | The website's support page says 'macOS 14 or later' and names workflow steps that do not exist; the home page quotes a stale harness count | card W1 → owner c (leave) |
| f7 | medium | CONFIRMED | `../website/impressum.html:52` | The live Impressum and privacy-policy controller block still carry '[FULL NAME] / [STREET AND NUMBER]' placeholders, under their own warning that an incomplete Impressum can draw a formal legal warning (abmahnfähig) | card W1 → owner c (leave) |
| b4 | low | CONFIRMED | `mac4DSTEM/UI/ReconstructionSettings.swift:782` | Reconstruction inspector shows 'Shift-fit RMS 0.0000 Å', a number that is zero by construction on every dataset | lane C |
| d3 | low | CONFIRMED | `mac4DSTEM/App/PendingLoad.swift:429` | Keep-in-memory and the phase-contrast budget ignore a cube held resident by another dataset window | open-items (low; after v4.1) |
| d4 | low | CONFIRMED | `mac4DSTEM/UI/LoadConfigurator.swift:148` | Keep-in-memory refusal names the wrong limit: a cube above maxBufferLength but below the working set reads 'is above the GPU working-set limit' beside a larger limit | lane D |
| e4 | low | CONFIRMED | `mac4DSTEM/UI/SettingsWindow.swift:209` | Settings › Advanced › "Log verbosity" is a control that does nothing | sheet "same" list → removed (lane H) |
| e7 | low | CONFIRMED | `mac4DSTEM/UI/ImagePanes.swift:1299` | Single-slice ptychography's empty state tells the user to prepare a parallax preview; the task needs none | lane F |
| c3 | low | REFUTED | `mac4DSTEM/App/AppState+PhaseContrast.swift:79` | Parallax preprocessing or alignment still in flight brings back a product that a calibration edit had just cleared, made with the old calibration | REFUTED by the verifier |

## Crash reports (all five `.ips` since 2026-09-30, read 2026-10-02)

- **10-02 13:39, "crash after Compute Strain"** — an AppKit update-constraints loop inside the toolbar (8 of 8 logged stacks are
  toolbar items; "NSGlassContainerView … 300 iterations"; reason text from the unified log). Not the split-column class. Suspect: the
  idle↔busy swap of the principal run display and the primary button (frozen files). Stress reproduction (2000 idle↔busy cycles × 4 runs,
  incl. every cycle a real strain run): **not reproduced** — a null result, no mechanism inferred. Stays an open item.
- **10-01 11:29 (owner's install) and 10-01 18:03 (test host)** — HDF5 library teardown at exit (`H5_term_library → H5FL__reg_gc_list`).
  Unregistered before today. Diagnosis in progress at the time of writing: the app has no quit hook, so a read still running at Quit
  can race HDF5's teardown (reproduced 1/20 in a harness), but that race leaves a reader thread in libhdf5, which the owner's report
  does not show.
- **09-30 MPSGraph bf16 pool gradient** — fixed earlier (9026863e). **10-01 10:30** — a test-host assertion (a mutation break), not the app.
- **β″ preset CIF picker** (Slot 4½ residual) — no code difference from ACOM's working picker; worked in four earlier drives; to be
  re-tested in the release-candidate drive (a failed reproduction closes it, ADR 050).

## Owner answers (2026-10-02)

W1 c (leave the website as is) · R3 a (make CI honest) · D1 c (leave the silent adoption — the identity check is archived, not shipped)
· D2 a (refuse a dataset already open in another window) · D3 a (refuse a save that would relabel carried results) · U1 b (remove
"Open Another…"). Log verbosity: removed (ADR 049, folded into the sheet's "same" list).

## Lanes — landed (each gated alone on an isolated copy of HEAD + the lane; an independent Fable refuter on each)

| lane | findings | commit | unit (pass / fail / skip = declared) | notes |
|---|---|---|---|---|
| H | sheet "same" list; H1 restore guard | `9cb622be` | 1492 / 0 / 3 = 1495 | + its control test run alone 4/4 |
| G | f2, f4, f5 (docs) | `75703ea7` | docs only | website left as is (W1 c); prepared edits kept in the session scratchpad |
| E | c1, c2 | `6e9a7fe4` | 1500 / 0 / 3 = 1503 | refuter HOLDS |
| F | e2, e3, e6, e7, e9, b2, b3 | `26b3f9ef` | 1505 / 0 / 3 = 1508 | |
| C | b1 (Gate D), d2, b4 | `6d42f602` | 1496 / 0 / 3 = 1499, scientific 52 zero FAIL | Gate D record `../review-c-rotation-gateD-2026-10-02/` |
| A | a1/b5/e1, a4, a3, e5, c4, e10 | `443dc69c` | 1500 / 0 / 3 = 1503, scientific zero FAIL | |
| R | f3 (card R3 a) | `7ae5d593` | 1493 / 0 / 3 = 1496, scientific zero FAIL | CI green unproven until pushed |
| D | d1 (Gate D), d4 | `5babc867` | 1496 / 0 / 3 = 1499, scientific zero FAIL | `../review-d-tile-budget-gateD-2026-10-02.md`; binned mean pattern ±8–10 float32 ulps |
| B | a2 (card D1 c) | `ac22cc97` | not shipped | `../review-sidecar-identity-2026-10-02.patch` + report |
| L | d1 residual (two sibling formulas) | `81b599cb` | 1554 / 0 / 3 = 1557, scientific zero FAIL | no bit moves |
| I | a6, a5, e8 (cards D2 a, D3 a, U1 b) | `d212bf88` | 1558 / 0 / 3 = 1561 | |
| K | the HDF5 quit race (found by the crash diagnosis), three unguarded session readers | `cbb647a4` | 1570 / 0 / 3 = 1573, scientific 53 zero FAIL | probe 198/200 crashes on the old code → 0/200; `../review-k-hdf5-exit-2026-10-02/` |

Counts are from each lane's own gate (its base commit differs as lanes landed); the release's `run-tests.sh all` on one commit is
the gate that covers them together.

## Release cut and the stopped gate

The cut is `7ee4419f` (4.1.0 / 8; the v4.1.0 CHANGELOG section, README, CITATION, releasing.md). `run-tests.sh all` on it, on a clean
tree, ran unit 1570 / 0 / 3 = 1573 (reconciled with 1573 `func test`) and the first 32 scientific harnesses with zero FAIL lines, and
was stopped at the owner's word inside `datacube-discovery-test` — not a complete gate. Lane K's isolated gate had run all 53
scientific harnesses with zero FAIL on code identical to the cut (it differs only in version numbers and docs). The complete run followed on
`388634ef` (the cut + docs): unit 1571 / 0 / 2 = 1573, 54 sections, zero FAIL, `GATE_EXIT=0` — the release gate.

## Not fixed here (registered in `docs/open-items.md`)

The toolbar layout loop (seen once, not reproduced in 12 000 stress cycles; a fix would touch frozen files — no card without a
reproduction); the shared-by-stem session file (D1 c); stored disks after a relabelling save; quit latency on a stalled volume; the
⌘R / toolbar predicate copies; iDPC frame; the preview-stride I/O budget and the post-bin "Streamed" figures; d3 (keep-in-memory across
windows); the β″ CIF picker (to re-test in a drive). Unverified on screen: every refusal and disabled state these lanes added.

