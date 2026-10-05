# Second opinion on the quantification and room drafts (Opus 5.5, 2026-10-05)

This is the independent reviewer's handback, condensed by the session. The reviewer read ADR 053, the brief,
`columns.md`, both drafts and dossier §1, §5–§10. **[inf]** = the reviewer's own reasoning, offered to be checked.

## On the draft's cards

| Card | Verdict | Why |
|---|---|---|
| **C1 Poisson-ML default** | **Amend: LS until measured** | Quoted numbers come from pooled spectra (10³–10⁶ counts in the peaks), where LS ≈ ML [inf]. The 2.9 % is a FePt figure (threshold rule). Velox's working SI default is "least square (Empirical)" (Velox 9057–9058). LS is pinnable and comes first in the port order. Pre-register an LS-vs-ML measurement on pooled Al-Mg-Si spectra; switch only if the gap exceeds about ½ of the counting σ of the Mg/Si ratio. |
| **C2 Brown-Powell first** | **Agree, with a missing input** | A computed k = cross-section × fluorescence yield × line weight × **detector efficiency ε(E)**. The Super-X G1 ε is named nowhere. It must be a sourced input shown in the k badge. Copying the Bote-Salvat coefficient tables may raise EU database rights [inf, not legal advice]. |
| **C3 at% on day one** | **Agree, if the badge is on the number** | The badge must show on screen and in every export, and at% is computed on pooled regions only (an at% map at 10–18 counts/px is noise: dossier §6, ±22–28 wt%). Science question c is a ratio of ratios, so k cancels in it [inf]. **Cut ζ from the visible list:** there is no ζ for this instrument, and `ScreenCurrent` is uncalibrated (GMS writes 0.0). |
| **C4 flat 20 % σ_k** | **Agree** | The Mg/Si error enters once, through k_Mg/k_Si. ±20 % on it swamps the β″ composition question, so lead with the k-free ratio. |
| **C5 physical continuum default** | **Disagree** | It inherits the missing ε. The Al K edge (1.56 keV) puts a step between Al Kα and Si Kα. Velox's "Empirical" is a *fitted* Bethe-Heitler, not a computed physical continuum. Windows barely fit between Mg, Al and Si (peaks about 240 eV apart at 80–100 eV FWHM) [inf]. **Default instead:** a fitted whole-spectrum empirical continuum with the Al-edge step. Polynomial windows go under Expert and serve parity; espm comes later. Acceptance: the residual over 1.1–1.9 keV on a pooled matrix spectrum is flat within ±1. |
| **C6 matrix-pool blank** | **Amend** | The matrix holds Mg and Si in solution. Subtracting it gives "Mg excess over the matrix", which must be labelled. A Mg-free control region does not exist in these alloys [inf]. **Instead:** measure the Al tail (and the Si internal fluorescence) once on a pure-Al reference on the same Super-X, and fit the tail as a component tied to Al Kα. Keep the blank for enrichment. |
| **C7 thickness typed ± σ** | **Agree** | An EELS t/λ → nm conversion needs a mean-free-path model, which is one more named choice. |
| **C8 escape peaks** | **Amend: always fitted, no control** | Escape needs lines above 1.84 keV, so Mg, Al and Si have none. A control nobody needs is filler; name it in the footer. |

**Two more factual errors in the draft:**

- Cu should default to **Quantify**, not "Fit only", because the Q phase holds Cu. Check stray Cu on a hole region.
- Whether dead time is stored per pixel or per frame is unverified.

## Reconciling the two drafts

| Conflict | Call |
|---|---|
| k / cross-section | **Visible.** It moves at% by tens of %, and Velox shows it in its SI panel. |
| Absorption | **Visible.** It moves Mg/Si by 3–19 %. |
| σ and at/wt | σ sits in the results table. at/wt is a segmented control in the table header, not an inspector row. |
| Structure | **One inspector per sidebar step.** The 22-row single inspector repeats AZtec's "one task over eight fields" vertically. The 9-row panel omits the energy axis and regions. |

**Merged layout: five steps, no screen over 7 rows, about 22 rows in all.**

| Step | Rows |
|---|---|
| **Spectrum image** | Source and registration (scan-shape mismatch named) · frame range · energy axis (file vs refined) · counts/px with histogram · live/dead time · geometry. Five of the six are readouts. |
| **Elements & maps** | Element list (Quantify / Fit only / Off) · suggestions · map shows net counts or at% · display smoothing (kernel shown) |
| **Regions** | Source (drawn / phase / object, badge inherited) · pixels · counts · live time · line width (lines only) · compare, normalised to Al Kα |
| **Quantify** | **Visible:** method preset · background · k-factors · absorption · thickness ± σ · fit quality · Expert. **Expert:** estimator · σ_k · polynomial order · energy-axis lock. |
| **Export** | Format · include method and σ terms |

**Cut under the no-filler rule:**

- Overlay, residual and axis toggles move onto the canvas and the plot.
- Region names are edited in the sidebar.
- "Normalise" becomes a fixed footer.
- "Save method" moves to the menu, as Velox does.
- The visible ζ option and the escape control go.
- "Windows only" moves under Expert.

**The toolbar verb is Quantify.** It records the result as a replay step (ADR 047) and computes fitted maps. The pooled
fit itself reruns live (milliseconds), which avoids Velox's "Apply to SI" trap. Selecting a region already pools it, so
no "Pool" verb is needed.

## What both drafts missed

1. **Live-time and dose normalisation between regions.** Dead time runs at 48–60 %. Approach E specifies a
   live-time-weighted pool. Is per-pixel live time in the stream? Unverified. The fallback is the Al Kα internal
   reference, stated on the result.
2. **Energy-axis offset, gain and resolution.** Fixed centres and widths misfit the Mg/Al overlap at a 5–10 eV error;
   the four detectors may differ in gain [inf]. Refine on the pooled spectrum and show file vs refined.
3. **Si internal fluorescence.** It adds Si in proportion to total counts, which are mostly Al Kα. That **compresses
   the Si enrichment ratio toward 1**, and a blank does not remove it from a ratio [inf]. This is the first science
   question.
4. **Stray peaks:**
   - Ga L (1.098 keV, from FIB) sits next to Mg Kα.
   - Cu comes from the grid or from the Q phase.
   - The Ar in the owner's 190330 element list is probably the Al sum peak, which argues against Auto ID on by default.
   - Fe/Co (pole piece) and Mo (holder) should be checked [inf].
5. **Map units.** Pixel-wise net counts go negative. A smoothed map is counts per kernel. The legend must give the
   unit, the live-time basis and the kernel.
6. **Beam damage:** compare the first and last frames (the frame-range row).
7. **The cheapest k check:** the owner quantifies one pooled matrix spectrum in Velox (Brown-Powell) and reads off the
   at%. That checks the app's computed k, including ε.
8. **YAlO₃ as truth for Mg/Si is weak:** O K is in NIST's high-uncertainty band. Only Y:Al tests the k chain [inf].

The nine owner cards the reviewer proposes are the sheet in `../owner-decisions-2026-10-05-v5.json` (ids V5-Q1…V5-Q9).
