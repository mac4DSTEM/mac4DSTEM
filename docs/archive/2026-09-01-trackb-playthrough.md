# Track B playthrough and review recovery — 2026-08-31 / 2026-09-01

**Archived from `docs/open-items.md` at closeout, 2026-09-01.** History, not
guidance. These nine entries were written live during the session and are kept
verbatim because several record *how a diagnosis converged or was retracted*,
which is the part the live log is not the place for.

The live residuals they produced are summarised in `docs/open-items.md` under
**"Track B playthrough — 2026-09-01"**, which points back here. Where the two
disagree, this file is the evidence and the live log is the summary — the same
rule §9's stubs follow.

**What this session did NOT change:** nothing under `mac4DSTEM/` or
`mac4DSTEMTests/`. Every finding here is eval-only.

---

### Track B drive-kit preparation — 2026-08-31

Prep for the owner's TB1 sittings 2–4 + TB2 playthrough. Nothing under
`mac4DSTEM/` was touched; these are checklist and kit changes plus one
prediction that is **not** a diagnosis.

**Two queued rows could not have been driven as written** — the F1.1/F1.36
class, caught this time in a code survey rather than by the owner losing a drive
slot. Both are corrected in
[`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md) with the
correction stated in the row.

- **F1.42 named a menu item that does not exist.** It said *"Open the demo
  dataset (File ▸ Open Demo)"*. There is no such command: `DatasetCommands`
  (`App/mac4DSTEMApp.swift:40-56`) has New Dataset Window / Open Dataset… /
  Reopen …, and the demo is reachable only from the welcome screen's **Try Demo
  Data** button (`UI/ProductWorkspaceViews.swift:60`) or the `--demo-fixture`
  launch argument (`:35`).
- **F1.8 described a state that cannot exist.** It asked for *"a real-space crop
  with existing strain / ACOM / Bragg results on screen"*. A scan crop can only
  be chosen in the pre-load configurator, which *replaces* the dataset — so
  results can never be on screen at the moment the crop is set. The message the
  row wanted **is** real, produced at
  `Core/Data/CalibrationReReference.swift:306-312` and rendered as a *"Not
  carried into this view"* inspector section (`UI/DatasetInspector.swift:169-188`);
  the row is rewritten to reach it, with the second trap named — `showInspectorPane`
  defaults to `false` (`App/AppState.swift:1014`), so that refusal notice is
  invisible unless the reader opens the inspector.

**Done criterion 4 had no numbered row, and now does (F1.46).** "The
colleague-sidecar row passes on the clean account" (`docs/v2-release.md` §5) and
§1's *"Hand a colleague the recipe"* rested entirely on prose in the sitting-4
plan — no check, no expected result, no cited control. That is exactly what the
rule against queueing a row ahead of its affordance exists to prevent. F1.26 is
not a substitute: F1.26 is the sidecar that does **not** fit and must be refused;
F1.46 is the one that **does** fit and must restore.

**A prediction that should be settled BEFORE a clean account is set up —
Gate D owed, not run.** Writing F1.46 surfaced this; it is read from source and
**has not been reproduced**, which is why it is recorded as a prediction and not
as a defect.

- The app holds `files.user-selected.read-write` only. A sidecar is a **sibling
  the user never picked**, so it is reachable only through a bookmark stored
  when they chose it in a save panel — the locator's own header states this as
  measured, not inferred (`App/SessionSidecarLocator.swift`, 2026-08-19: with no
  bookmark `FileManager.fileExists` still returns true and `H5Fopen` fails with
  **errno 1, EPERM**).
- The only caller that stores a grant is `writableSessionSidecarURL`
  (`Support/ResultExport.swift:154-169`), and it is a **save** panel.
- The inspector's unreadable-sidecar section (`UI/DatasetInspector.swift:283-297`)
  is honest and offers **no remedy control** — no Locate…, no Grant access….
- F1.26 hit exactly this on 2026-08-29: HDF5 `errno = 1`, *Operation not
  permitted*, on a sidecar copied in from outside.

**Prediction, written before the experiment:** a colleague's cube + sidecar
copied to a clean account shows *"A saved session sits beside this dataset and
could not be read"*, errno 1, and loads at full extent — and the only route to a
grant is a save panel that would **write over the colleague's sidecar**.
**Refuting observations:** the pair restores with no grant step; or the refusal
carries errno **13**; or a route exists that grants read access without writing.

**GATE D RAN 2026-08-31, SAME DAY. THE ALARMING HALF IS REFUTED — three
independent ways, two of which were already in this file and one of which was
already *observed*.** Recorded here rather than argued away, because the
prediction above was written by a reader who had not searched this document for
the symptom first — the S1 lesson, repeated, and the skill warns about it
literally by name.

- **The save cannot overwrite it, because the save is refused.** The EPERM
  branch calls `gates.noteSidecarRestoreFailed(.unreadable, …)`
  (`App/AppState.swift:1490`), which arms `SessionGates.sidecarRewriteRefusal()`
  (`App/SessionGates.swift:179-205`). All three rewrite entry points consult it —
  `saveCurrentResultToSessionSidecar` (`Support/ResultExport.swift:711`),
  `removeSavedSessionResult` (`:1031`) and `saveCalibrationToSessionSidecar`
  (`:1259`) — and the calibration path checks it **before**
  `writableSessionSidecarURL` ever opens a panel. S7's F9 gate was already
  standing guard over exactly this.
- **Even reaching the panel would not overwrite it.** `copySidecarFile` returns
  `.nothingToCopy` on a filesystem-**identity** match before any `removeItem` or
  `copyItem` (`Support/ResultExport.swift:1097-1112`), and picking the same file
  is handled explicitly as a grant-only action (`:1193-1194`).
- **It was measured, and the measurement is in this file.** The 2026-08-29
  same-file re-grant left the staged sidecar byte-for-byte and identity
  unchanged — SHA-256 `7d21932f…`, 543,856 bytes, inode 317831317, mtime
  unchanged — and after relaunch the grant let the app read it. The entry
  already concluded **"the sandbox blocker is clearable"**.

**What survives, unchanged:** a copied-in sidecar IS refused on first open with
errno 1 (measured 2026-08-19, reproduced by F1.26 on 2026-08-29). Done criterion
4 still requires a grant step the recipient must discover.

**And the discriminator turned up a sharper finding than the one predicted — the
F1.3h defect class, repeated in the sibling message.** The app prints **two
different remedies for the same state, and the one the colleague sees FIRST is
the one that cannot work.**

- The inspector's unreadable-sidecar section (`UI/DatasetInspector.swift:283-297`)
  renders `SessionSidecarLocator.explanation(sidecar:)`, whose `.notPermitted`
  case says: *"Save the session once (**File ▸ Save Calibration to Session
  Sidecar**) and choose that file, which grants access for future opens."*
- By the time that text is on screen, `sidecarRewriteRefusal()` is armed — so
  that exact command is **refused**, and its refusal names a *different* remedy:
  *"re-grant with **Change…** in the dataset inspector (choosing the same
  file)."*
- `App/SessionGates.swift:188-190` names this class in its own comment — *"a
  printed remedy that cannot work is the F1.3h defect (Gate B, 2026-08-25)"* —
  while the sibling text in the locator still carries it. The Gate B that wrote
  the careful version fixed one of the two messages.

**Consequence for sitting 4, which is why this was worth doing first:** a
colleague follows the first instruction, is refused, and reasonably concludes the
app is broken. The working remedy (**Change…**) is never named on the surface
that reports the problem. **This is a finding, not a fix** — eval-only, no app
code touched. It wants an owner call on whether it is v2 or v2.x, and the fix is
plausibly one string.

**Not established, and needing the sandboxed app rather than source:** that the
inspector's `Change…` control is reachable and does re-grant on a genuinely
foreign sidecar in a *never-granted* account (the 2026-08-29 run was the owner's
own machine, one run, recovered testimony, no second reader). **A second reader
of this diagnosis has NOT run** — the Gate D protocol owes one, against the
primary evidence rather than this summary.

**A navigation fact recorded because it changes how rows are driven** (an S22
lead, not scheduled for repair here). Once a dataset is loaded, **"Open with
Options…", the Recents list and "Try Demo Data" are all unreachable in that
window**: all three are sole-call-site'd inside the welcome screen
(`UI/ProductWorkspaceViews.swift:44-66`), none has a File-menu item or shortcut,
and the sidebar's open control sits inside `if !appState.hasDataset`
(`UI/ContentView.swift:122`). Plain ⌘O survives, so the **configured** open is
the one that silently disappears after first use; the escape is ⌘N. Every
configurator row — F1.8, F1.19, F1.30, F1.31, F1.37, F1.39, F1.42 — needs that.

**Also landed:** a *free-form pass* subsection under *Recording a run* in the
checklist, carrying the six-item capture list and the three standing cautions, so
the owner's proposal to drive his own cubes is a recognised recordable mode of
Track B rather than an argument re-made each sitting. The verdict it encodes:
**an addition with a reorder, not a substitution** — free-form first and
unprimed (F1.37 and F1.40 measure whether something *reads as* broken, and
being told the answer first destroys that), then the rows, because five of the
fourteen done criteria are worded as dependencies on specific rows and two (DC2,
DC13) cannot be ticked from an unstructured session at all.

**One stale fact corrected in the machine-local kit:**
`sim_Au_data_all_binned.mac4dstem.h5` no longer exists, so F1.3f runs on
Si_SiGe.

### Assistant-driven Track B rows — 2026-09-01

Driven on the Xcode Debug product (executable 2026-08-31 23:55, single
DerivedData, verified before driving — the bundle directory's mtime reads
2026-08-18 and is misleading; check `Contents/MacOS/mac4DSTEM`). Real `CGEvent`
input; every click behind a frontmost assertion that aborts rather than clicking
into whatever app is in front. Datasets: the demo fixture and
`sim_Au_data_all_binned.h5`. **Track A was NOT running** — the aggregate
finished first, deliberately.

- **F1.39 PASSED**, both halves verbatim. The row reads `GPU working-set limit
  5461 MB` and the caption says the limit *"is a property of this Mac's
  hardware, not an amount you may load"*. S9a's rename is on screen.
- **F1.33(a) PASSED, one observation.** Sidebar scrolled ~28pt while the hovered
  pane stayed pixel-identical. Scored as one observation because the row's own
  trap says the old behaviour is intermittent. **(b) not driven.**
- **F1.38 PARTLY PASSED.** Prepare, Image, Map, Results all render both image
  surfaces. The comparison pane and inspector thumbnails were **not reachable** —
  the demo has no saved products.
- **F1.30 NOT DRIVEN, and deliberately so.** Its assertion is on the status line
  during **Export Calibrated DataCube…**, which writes a real reduced file — on
  sim_Au that is a ~500 MB write on a machine that runs near its disk floor.
  **That is an owner decision, not a default**, so it is left undriven with the
  reason recorded rather than performed quietly.

**A finding, observed rather than predicted.** Opening a second window (⌘N — the
only route back to *Open with Options…* once a dataset is loaded) produced a
welcome screen whose **entry buttons were entirely below the visible area**: only
the three Prepare / Analyze / Preserve cards and *"No file loaded"* were on
screen. Scrolling brings the buttons back, so they are **below the fold, not
unreachable** — but nothing signals that a scroll is needed, and the three cards
that push them down are inert. This is the owner's 2026-08-27 report given exact
form, and it compounds the recorded navigation defect: ⌘N is the documented
escape to the configurator, and the escape hatch itself opens below the fold.
Filed as an S22 lead; **not fixed** (eval-only).

**Incidental corroborations** worth having on the record, each seen rather than
inferred: the demo really does draw a simple-cubic zone on a gold lattice (four
discs at 45°, four on-axis — F1.42's central trap); the dataset card carries its
axis labels (F1.34, already passed); the configurator's three previews all draw
(F1.3b's fix holding); and the configurator's closing caption sits below the
sheet's visible edge until scrolled (**F1.17's clipping defect, reproduced on a
third occasion**).

### sim_Au playthrough: strain, a clean Q control, and a badge that disagrees with itself — 2026-09-01

Driven jointly on `sim_Au_data_all_binned.h5` (`4DSTEM_AuNanoplatelet`, 100 × 84
scan, 125 × 125 detector). **Nothing under `mac4DSTEM/` was changed.**

**F1.28 PASSES IN FULL, and S8's live-derivation contract is confirmed on
screen** — it had been "not verified" since S8. With origin calibrated and
rotation NOT, the line under the Component picker read, in orange:
**`Detector x/y — R–Q rotation not calibrated`**. After **Calibrate Rotation**
(`Rotation ✓ θ = 1.8°`) the same line read **`Scan frame (R–Q 1.8° applied)`** —
**without the map being recomputed**: every diagnostic stayed byte-identical
(`Basis consensus 100% · 95226/95257 peaks`, `Basis fit RMS 0.962 px · κ 4.85`,
`Local fits 52% indexed · median RMS 0.426 px`, `Reference inliers 3850/4365`)
while the colorbar moved **±0.07736 → ±0.07602**. The stored map stayed
detector-frame and the display re-expressed it, exactly as S8 designed.
*One caveat on the row's wording:* at θ = 1.8° the ε_xx/ε_yy trade is a 1.7%
change — real, but not "visibly" trading strain.

**A CLEAN CONTROL FOR THE REFERENCE-SHELL DEFECT.** Q calibration from the
crystal, same code path, two specimens:

| Specimen | Measured | Predicted | Disagreement |
|---|---|---|---|
| **Gold (FCC), `sim_Au`** | 1.148 | 1.155 | **0.6%** |
| **WS₂ (basal), `polycrystal_2D_WS2`** | 1.633 | 2.000 | **18.4%** |

For FCC the first two allowed shells are {111} and {200}, |g| ratio
2/√3 = **1.1547** — the app's predicted 1.155 is exactly right and the
measurement agrees to 0.6%. **The shell-ratio machinery is therefore sound, and
the WS₂ disagreement isolates to the WS₂ reference-shell *selection*, not to a
broken estimator.** Full line:
`Q calibration ✓ 0.019827 Å⁻¹/px · first shell 21.42 px · 4380 positions ·
shell ratio 1.148 vs 1.155 predicted`.

**Strain works and is well-instrumented.** `Strain ✓ 52% indexed · 100% basis
support · RMS 0.962 px · κ 4.85 · 3850/4365 ref`, overlay `● measured ✕ local
fit ⋯ reference · residual 0.415 px`. Two good design details: the Result
colormap **auto-switched to RdBu (diverging)** for a signed quantity, and the
masked region carries an explicit **"masked · no fit"** legend entry **on
screen** — note that review finding `support-export-07` is about the *exported
publication figure* omitting that legend, which this pass did not test.

**Full ACOM on gold:** `ACOM full ✓ Accelerate CPU · Physical · measured in app ·
8.400 positions · 1.5 s`, uniform IPF over the platelet with a cubic key
(`001`/`111`/`101`) — correct, since the nanoplatelet is a single crystal.

---

**A BADGE THAT DISAGREES WITH ITSELF — hypothesis with a discriminator, NOT a
conclusion.**

The **same product** carries different trust badges on the two datasets, and both
screenshots are retained:

- `polycrystal_2D_WS2`: **`ACOM full scan · IPF · Z`  [Quantitative]** (green)
- `sim_Au`: **`ACOM full scan · IPF · Z`  [Categorical]** (magenta)

An IPF map is a direction colour-code, so **Categorical is the correct badge and
the WS₂ one is wrong** — and "Quantitative" on a map that is not a quantity is
precisely what §1's fourth commitment forbids.

**Why it cannot come from the ACOM path.** `ipfZ` maps to
`baseKind = "acom_ipf_z"` (`Support/ResultExport.swift:1421`) and the final kind
is `acom_<qualifier>_ipf_z` (`:1438`), so it **always contains "ipf"**. Both
deciding functions return `.categorical` for that —
`ACOMWorkflow.productStatus(for:)` (`App/ACOMWorkflow.swift:121`) and
`AppState.quantitativeStatus(for:units:)` (`App/AppState.swift:744`). The only
route to `.quantitative` is the **fall-through at `App/AppState.swift:749`**,
reachable only by a kind that is neither `acom_*` nor contains `ipf`.

**Hypothesis:** the WS₂ window's badge was computed from the **restored** product,
not the displayed one. That window had `result_dpc_magnitude_6d39bfff` restored
from the staged sidecar, kind `dpc_magnitude` — neither `acom_*` nor containing
`ipf` — and its stored provenance reads literally
`"quantitative_status":"quantitative"` (read from the file). The `sim_Au` window
had **no restored product** and badged correctly. If that holds, this is a
**runtime reproduction of `app-appstate-01` / `support-export-01`** (restored
provenance surviving onto a freshly computed product), which the review could
confirm only by source inspection.

**DISCRIMINATOR RUN 2026-09-01. THE HYPOTHESIS SURVIVED — on a cleaner product
than the one that raised it.**

*First attempt FAILED, and the failure is worth recording:* renaming the sidecar
to `…discriminator-bak` did **not** stop the restore — the log read
`Restored DPC magnitude ← polycrystal_2D_WS2.mac4dstem.h5.discriminator-bak`.
**A security-scoped bookmark tracks the file by inode, not by path**, so a rename
follows it (this file already recorded that a sidecar bookmark "FOLLOWS the
file"). The inspector honestly named the renamed file, which is correct
behaviour. **A rename is not a valid way to withhold a sidecar from this app** —
use a different *source path*, since the bookmark key is derived from it.

*Second attempt, the valid one:* a **hard link** to the cube at a fresh path
(no sibling sidecar, no stored bookmark for that path). Nothing was restored.

**Result — a controlled A/B on the same cube, same product, same settings, one
variable changed:**

| Session restored from sidecar | `Virtual detector · Annulus` badge |
|---|---|
| **Yes** (normal path) | **Quantitative** — wrong |
| **No** (fresh path) | **Relative** — correct |

`Relative` is right: the product's units are `intensity`, and
`AppState.quantitativeStatus` maps `units.contains("intensity")` → `.relative`
(`App/AppState.swift:745-748`). **A restored session's provenance is reaching the
trust badge of a freshly computed product.** That is `app-appstate-01` /
`support-export-01` **reproduced at runtime** — which the review could establish
only by source inspection, its Limits section saying plainly that source
inspection cannot reproduce.

The virtual detector turned out to be a **better** discriminator than the ACOM map
that raised the question: fewer moving parts, no calibration, no template
matching, and an unambiguous correct answer. The IPF `Quantitative` observation is
explained by the same mechanism, **but the ACOM leg was not itself re-run** — that
half remains inference, not observation.

**Severity:** Group A, now on reproduced rather than source evidence. The badge is
the app's own statement about whether a result may be read quantitatively, and
§1's fourth commitment is exactly that such a statement cannot mislead.

**Not established:** that any exported file carries the wrong status (only the
on-screen badge was observed); that the strain or ACOM *numbers* are affected
(nothing suggests they are); and the mechanism itself, until the discriminator
runs.

### `polycrystal_2D_WS2` reaches ACOM on screen — Done criterion 8 — 2026-09-01

Driven jointly: the owner set the detection threshold and the display range, the
assistant drove the sequence. **Nothing under `mac4DSTEM/` was changed.**

**The run, verbatim from the log:**

```
01:03:47  Disks ✓ 570392 peaks (Parabolic subpixel)
01:06:07  Orientation plan ✓ 200 templates (Tungsten disulfide (2H–WS₂))
01:06:07  ACOM preview ✓ Accelerate CPU · Exploratory · 1.024 positions · 0.4 s
01:08:46  Q calibration ✓ 0.022122 Å⁻¹/px · first shell 7.34 px · 16384 positions
          · shell ratio 1.633 vs 2.000 predicted
01:11:59  ACOM full ✓ Accelerate CPU · Physical · measured in app · 16.384 positions · 5.6 s
```

**Done criterion 8 is met on screen**: WS₂ entered through the model contract and
`polycrystal_2D_WS2` produced a full orientation map with fit-overlay acceptance.
The gating chain also worked end to end — before Q calibration the header said
**"⊘ Ready · limited interpretation / Exploratory matching only: set physical Q
sampling for quantitative orientation output"** with an *Improve in Prepare*
button, and the run logged `Exploratory`; after calibration the same run logged
**`Physical · measured in app`**.

**The scientific finding, and it is the reference-shell open item seen on screen
for the first time.** The Q self-check reports **shell ratio 1.633 measured vs
2.000 predicted** — an 18% disagreement. For basal 2H-WS₂ the first two in-plane
shells are {10-10} and {11-20}, whose |g| ratio is **√3 ≈ 1.732**. The
*measurement* (1.633) sits near √3; the *prediction* (2.000) does not correspond
to that pair. This is consistent with the recorded reference-shell defect
selecting the wrong shells — **but it did NOT reproduce W4b's 2.2563×/2.2129×
mis-scale**, and the detection settings differ (0.01% relative threshold, 570,392
peaks), so **the two observations are not directly comparable and this is not a
refutation of W4b**. What is established: on this cube, with these settings, the
estimator's predicted shell ratio disagrees with its own measurement by 18%.

**And the app proceeds anyway.** Q pixel scale is marked ✓ green **"Measured in
app"**, the ACOM map is badged **Quantitative**, and the run is labelled
**Physical** — while the only statement of the disagreement is a status line that
scrolls away. **This is F1.42's product question in its sharpest form, on real
data rather than the demo fixture**: is reporting enough when nothing refuses and
the disclosure is transient? It belongs with the truncation and below-the-fold
findings — the honesty is implemented, and then placed where it loses to its own
reassurance. **Owner judgement, not a defect call.**

**A row expectation that is wrong.** F1.45 says IPF·Z should be *"nearly uniform
— that is the specimen, not a bug (the cube is basal, ~98% [0001])"*. It is not:
the map shows large, sharply-bounded grains. Either the specimen is not what the
row assumed or the near-uniform prediction was mis-derived. **Recorded as a row
defect, not scored as an app defect** — this needs the owner's eye.

**Two honest corrections from this pass, both mine.**

1. I attributed the Bragg-vector map's multi-ring appearance to the lower
   detection threshold. The owner had **also** adjusted the histogram range and
   gamma. Two variables moved; the inference was not available. **Withdrawn.**
   *Method consequence, and it is a real gap:* display range and gamma change what
   is visible without changing the data, and they are ordinary user actions —
   **the Track B capture list must record them**, and currently does not.
2. I overwrote the owner's chosen `0,01` threshold, having assumed it was my own
   scroll accident. Two drivers, one app. The turn-taking rule is not optional.

**Reproducibility, incidentally established:** detection is deterministic —
`0,1 %` gave exactly **199,463** peaks on two separate runs, `0,01 %` exactly
**570,392** on two.

### F1.26's state is REACHABLE — and a false alarm I raised and retracted — 2026-09-01

**The headline: F1.26's expected state is present and correct, and the 2026-08-29
errno-1 blocker is genuinely cleared.** Opening `polycrystal_2D_WS2.h5` with the
staged fixture in place (`mac4dstem_load_specification =
{"scanCrop":{...,"height":200,"width":200},"detectorBin":1}`, verified by reading
the file) produced, in the dataset inspector:

- **Session provenance** — *"The saved session was computed on a different view of
  this file."*, **Session view: scan 200x200 at (0, 0)**, **Loaded view: whole
  file**, and *"Restored results describe the session's view, not the one loaded
  now."*
- **Session sidecar** — *"The saved session beside this dataset describes a region
  this file does not have."* and *"The whole file is loaded, and session saves are
  disabled so the sidecar's recorded view and results are not relabelled."*
- **Saved session sidecar** — the restored result listed as **DPC magnitude ·
  200×50 · float32 · detector_px · sampling 1 × 1 [pix]/px**, i.e. labelled with
  its **true** shape, beside a **Change…** remedy.

That is the row's whole expectation. **The owner should still drive F1.26** for
the three save-refusal paths, which this pass did not exercise.

**Now the part worth more than the result: I raised a false alarm and retracted
it.** Seeing a **50 × 200** DPC map badged **Quantitative** in a **128 × 128**
window, with **Origin & probe ✓ green, "Restored from session"**, I concluded I
had reproduced `core-data-02` ("Scalar session restoration lacks a scan-domain
shape check") at runtime — a confirmed-high review finding. **That was wrong.**
Every disclosure exists and is accurate. What was actually true is that I had not
scrolled far enough: the caveats sit **below Dataset, Preview, Dimensions, Current
scan position, Aperture and Performance**, in an inspector that is
**closed by default** (`showInspectorPane = false`, `App/AppState.swift:1014`).

**That is the finding, and it is now evidence-backed rather than asserted.** A
reader actively hunting for a shape-mismatch warning — knowing the review
predicted one, with the file open in a hex dump — concluded **twice** that the app
did not warn. The surfaces that reassure (a green ✓, a *Quantitative* badge, a
drawn map) are immediate and unmissable; the surfaces that qualify require opening
a pane and scrolling past six sections. **The information is all present and all
correct; the ordering is what misleads.** For a release whose claim is *"nothing
displayed can be misread as a quantitative claim the app isn't making"*, that is a
real S22 item — and note it is the same shape as the truncation finding above:
the app's honesty is implemented, and then placed where it loses the race against
its own reassurance.

**`ui-07` CONFIRMED ON SCREEN.** The inspector's Performance section reads
**"GPU budget    5461 MB"** while the load configurator reads **"GPU working-set
limit"** for the identical quantity (F1.39, same day). S9a renamed one surface and
not the other, exactly as the review predicted from source. **One word**; it is in
[the triage](v2-triage-2026-09-01.md) as the cheap pull-forward.

**Method, for the next drive:** two false findings were avoided today by the same
move — checking the source condition before believing the screen (F1.40's
`excludedFraction > 0.005`; the `DisclosureGroup` control test) — and one was
caught only by scrolling further. **Scroll every scrollable surface to its end
before reporting an absence.** Absence of a warning is a claim about a whole
surface, not about the part of it that happened to be visible.

### F1.40 driven on `Particle_1`, and what it turned up — 2026-09-01

**F1.40 PASSES.** On `Particle_1_Stack_1_45x90_ss30nm…bin8.h5` (45 × 90 scan),
after **Calibrate Origin**, the Prepare readiness row reads:

> *"Origin: Measured in app · Probe: 10.6 px (Measured in app) · **Fit RMS 18.47
> px over 73% of positions (27% excluded as outliers)**"*

**The 73% / 27% independently corroborates S12**, which measured the trim keeping
**72.7%** on this cube through a headless harness. Two routes, same number — the
kind of agreement worth recording, because S12's figure had never been seen on
screen.

**A NEW DEFECT, and it is on the caveats the release claim depends on: single-line
truncation in the readiness rows.** Three instances observed, all on the same
surface, all cutting the actionable half:

1. **F1.40's own clause** — renders as *"(27% excluded as…"*. The full string is
   *"(27% excluded as outliers)"* (`Core/Data/Calibration.swift:280`). **Still
   truncated with the sidebar dragged to 620 pt**, so this is not a
   narrow-sidebar artifact.
2. **The filename-vs-metadata warning** — renders as *"…File metadata takes
   precedence — check…"*. The full string ends *"— check which is right before
   trusting real-space scales."* (`UI/CalibrationReadinessView.swift:192`). **The
   half that tells the user what to do is the half that is cut.**
3. **Provenance** — *"Probe: 5.03 px (Measured in a…"* on Si_SiGe.

For a release whose claim is *"trust what's on screen"*, a provenance line that
truncates mid-word is more than cosmetic: the excluded-outlier fraction and the
scale-disagreement instruction are exactly the disclosures that make the claim
true, and both are unreadable at any sidebar width tried. **Finding, not fixed**
(eval-only). Recommend it joins Group A of
[the triage](v2-triage-2026-09-01.md) — it defeats disclosures that are already
implemented and correct.

**A STRENGTH worth naming, because it is the claim working.** Particle_1's
filename encodes `ss30nm`; the file's own metadata says **49.5 nm/px**. The app
imports the file value, marks R pixel scale ✓ *"Imported from file"*, **and warns
that the two disagree**, states which one it used, and says to verify. It neither
silently trusts the filename nor silently ignores it. This is also the honest
counterpart to review finding `ui-09` (the filename parser's false-positive
risk) — the same parser doing real work.

**Review finding on sidebar geometry CONFIRMED BY MEASUREMENT, not inspection.**
A **new** window opened with its sidebar/content divider at **exactly logical
x = 144.0** (measured by pixel-transition sampling), while `ContentView` declares
`navigationSplitViewColumnWidth(min: 250, …)` — **106 pt below the declared
minimum, and persisted into a fresh window.** At 144 pt the entire Calibration
section degrades to *"Ori… Missing"*, *"Elli… Missing"*, *"R–… Missing"*,
*"Q… Missing"* — the reader cannot tell **which** calibration is missing. The
divider drags back out normally, so it is recoverable; nothing signals that it
should be. This moves that finding from source-inspected to **observed with a
number**, which the review's own Limits section said it could not do.

**Also observed:** the app's minimum window width is 1080 pt
(`App/mac4DSTEMApp.swift:26`), and a new window opens at exactly that width.

### Free-form drive on `downsample_Si_SiGe_exp.h5` — 2026-09-01

Exploratory pass, scientific and design perspectives, on the owner's open
session (50 × 200 scan, 128 × 128 detector, uint64, 625 MB as f32). **No app
code touched.** Observations are separated from inferences on purpose.

**Two queued rows cannot be scored on the datasets we have been using, and their
rows do not say so.** Same class as the F1.42 / F1.8 corrections — a row that
cannot pass on the dataset in front of you costs a drive slot.

- **F1.40's outlier clause is conditional and Si_SiGe cannot trigger it.** The
  *"Positions used — N% (M% excluded as outliers)"* row renders only when
  `origin?.excludedFraction > 0.005` (`UI/CalibrationDetailsView.swift:64`). S12
  measured Si_SiGe as **broad measurement failure where trimming removes
  nothing** — so the row correctly does not appear, and its absence here is
  **not a defect**. The clause can only be exercised on **`Particle_1`**, S12's
  outlier-contamination case (trim keeps 72.7%). *This was nearly filed as
  "F1.40 fails"; the conditional in source is what stopped it.*
- **F1.41 needs a Q-from-crystal run.** The *"Q shell check"* row is conditional
  on `qCalibration.selfCheckSummary` (`:76`), which requires a phase model and
  **Calibrate Q from crystal**. It is absent on an untouched open, correctly.

**Both rows are also behind a collapsed disclosure.** *Fit diagnostics &
advanced correction* is closed by default and is the **last row in the sidebar**,
so the fit residual, the excluded fraction and the Q shell check are all one
deliberate expansion away from a reader who has just been told the calibration is
"Not quantitative". Whether that is right is a product judgement for S22, not a
defect — but it is where the numbers that justify the refusal live.

**Scientific read of the refusal chain — it works.** Origin fit residual
**11.655 px RMS** against a probe radius of **5.0 px**; aperture centre *"Fitted
by calibration"*; origin fit **Plane**. The app reports **Origin & probe — Not
quantitative**, **Q pixel scale — Missing**, **R pixel scale — Missing**, both
with *"lacks supported physical units ([pix])"*, and the diffraction scale bar
reads **`20 [pix]`** rather than inventing reciprocal units. This is S12's
documented Si_SiGe case refusing exactly as designed — **evidence for DC7, on a
second dataset**.

**A hypothesis raised and killed rather than filed.** The manual Q and R scale
fields are pre-filled with **`0`**, which looked like a zero-scale hazard.
`setManualQPixelSize` guards `value.isFinite && value > 0` and otherwise sets
`qPixelSize = nil` with provenance cleared (`App/AppState.swift:3156-3172`), so
committing the 0 **clears** the scale rather than setting a zero one. Not a
defect. The remaining point is cosmetic: `0` reads as a value in a field whose
valid domain excludes it.

**Design observations, for S22 rather than as defects.**

- **Strength — the help text names consequences, not just absence.** Hovering Q
  pixel scale gives *"Unlocks reciprocal units, physical orientation matching,
  and quantitative phase."* The excluded-fraction help is better still:
  *"Excluding nothing means there was no outlier tail to remove, not that every
  position measured well."* That is precisely the misreading §1 commits against,
  pre-empted in a tooltip.
- **Weakness — the readiness detail truncates where provenance lives.** The
  origin row reads *"Origin: Measured in app · Probe: 5.03 px (Measured in a…"* —
  the provenance parenthetical is clipped at the 250 pt sidebar width, and
  provenance is the part the row exists to carry.
- **Worth a designer's eye — a green ✓ beside two orange warnings.** *R–Q
  rotation ✓ −83.7° Measured in app* sits directly above *Q pixel scale Missing*
  and *R pixel scale Missing*. It is internally consistent (a rotation is
  scale-free, so it can be known while scales are not), but the tick may read as
  "this part is trustworthy" for a quantity nothing downstream can yet use.
  **Not filed as a defect** — it needs the owner's judgement, and possibly a
  microscopist who is not us.

**Method note for whoever drives this app next — the complement of the
2026-08-27 finding, and it cost time here.** That session recorded that System
Events' element-based `click at` silently does nothing on SwiftUI
`NSViewRepresentable` panes, so real `CGEvent` clicks are required. The reverse
is also true: **`CGEvent` clicks do not toggle SwiftUI `DisclosureGroup` rows**
(the sidebar is an `AXOutline`; the rows resolve as
`row N of outline 1`), while System Events' element click opens them
immediately. Verified with a control — the *Display* disclosure also refused
`CGEvent` and there is no defect in it. **An agent needs both mechanisms, chosen
by target type**, and four failed clicks on one disclosure is not evidence of a
hit-target bug.

### v2 vs v2.x triage of the confirmed review findings — 2026-09-01

[`docs/v2-triage-2026-09-01.md`](v2-triage-2026-09-01.md) groups the **39
confirmed** findings into six groups with a recommendation and a gate for each.
**It is a recommendation awaiting an owner decision, not a scope change.**

The short form: **Groups A (silent scientific misrepresentation) and B (data
integrity / unsafe file handling) are the v2 case**, because they are the
findings that make §1's fourth commitment false; **Group D (five green-but-
worthless tests) is cheap and should ride with them**, since it is what would
catch a regression in those fixes. Groups C (py4DSTEM parity deviations), E
(presentation → S22) and F (comments) are the v2.x case.

Two items are flagged for pulling forward regardless: `core-compute-shaders-01`
(a Fourier-frequency wrap in subpixel disk positioning — **measure whether it
biases strain before deciding it is parity-only**) and `ui-07` (the Performance
inspector still says "GPU budget" where S9a renamed the configurator row; one
word, and F1.39 verified the renamed row on screen the same day).

Cost, stated plainly: Groups A+B+D is roughly **5–7 sessions** at this repo's
gate discipline, most of Group A needing Gate D before any fix. Cutting C/E/F
does not shorten it — they were never the blocking set.

### The empty result pane gives the wrong instruction — found 2026-09-01

**Confirmed in source, seen on screen.** With `downsample_Si_SiGe_exp.h5` open in
Map ▸ Bragg disks, the right-hand pane is titled **"Bragg vector map"** and its
empty state reads:

> *"Adjust the aperture or pick a detector preset to generate an image"*

A Bragg vector map is not produced by adjusting an aperture or picking a detector
preset — it comes from **Detect All Disks**. A user who follows the instruction
on screen will change the aperture repeatedly and never produce the thing the
pane is named after.

**Cause, read from source rather than guessed:** `StemImageView.placeholder`
(`UI/StemImageView.swift:633-645`) is a single hardcoded string with exactly two
branches — `app.hasDataset` or not. It does not consult which result the pane is
waiting for, while the **title above it does**. So the virtual-detector
instruction is shown under every pending result kind.

Same class as the review's `app-rest`/UX finding that every error surfaces
through one alert titled *"Something went wrong"*: a generic string standing in
for a specific one, in the place where the user most needs the specific one.
**Cheap fix** — branch the placeholder on the pending result kind — but it is a
**finding, not a fix** (eval-only, no app code touched). S22 lead.

**Corroborations from the same screen**, each seen rather than inferred:

- **F1.34 holds on a genuinely non-square scan.** The sidebar card reads
  `200 × 50 scan (Rx × Ry)`, the inspector reads `Scan (Ry x Rx)  50 x 200`, and
  `Shape  50 x 200 x 128 x 128`. All three agree once the stated axis order is
  applied — which is the whole point of the row, now checked on the case that
  could actually fail.
- **DC7's refusal chain works on the dataset S12 characterised.** Origin fit RMS
  **11.655 px** against a probe radius of **5.03 px**; the app reports **Origin &
  probe — Not quantitative**, **Q pixel scale — Missing** (*"Reciprocal scale
  lacks supported physical units ([pix])"*), and the diffraction scale bar says
  **`20 [pix]`** rather than inventing reciprocal units. This is Si_SiGe's
  documented broad-measurement-failure case refusing exactly as designed, and it
  is the honest branch of review finding `ui-02` (which is about the case where a
  size exists *without* units).
- **`Not a result — cannot be exported or saved.`** is printed under the preview
  thumbnails — invariant I4 visible on screen.

---

## Skills — what worked and what was missing (closeout step 8)

- **`diagnose` earned its first instruction.** "Read what is already known before
  hypothesising" is the step that stopped a wrong Gate D: the colleague-sidecar
  fear was already refuted by evidence sitting in `open-items.md`, and the skill's
  own warning that this exact rediscovery happened in S1 is what sent me to grep
  for the symptom. Without it that prediction would have shipped as a finding.
- **`closeout` caught a real regression in my own work.** Its "check the tax"
  step measured the three-file total at **4237 lines**, up 786 on one session, all
  of it narrative — precisely the failure it warns about. 585 lines were archived
  in response. The instruction works because it demands a number, not a judgement.
- **`track-b` had a genuine gap: it said nothing about *how* to drive.** Two click
  mechanisms are needed depending on target type, and four dead clicks on a
  `DisclosureGroup` looked like a hit-target defect until a control test proved it
  was the input method. Closed by adding
  [`DRIVING.md`](../../.claude/skills/track-b/DRIVING.md), now linked from the skill.
- **No skill misfired or failed to trigger.** The friction that cost the most time
  was not a skill but the checklist: **five rows did not state their
  preconditions**, and two named affordances that do not exist. That is a
  documentation defect, now fixed in the rows themselves.
