# Quantification design session — the comparison columns (2026-10-05)

Three read-only research agents (Sonnet 5.5) filled the columns of `../quant-design-brief-2026-10-05.md`, one tool each.
This file is their findings, condensed by the session.

**Where the sources are.**

- **Velox:** "line N" is a line of the Velox 3.15 User Manual, carved to text from the owner's installer (11 160 lines).
- **GMS and Bruker:** Gatan manuals and release notes from the GMS 3.6.1 installer, plus Bruker's `quantax_manual.txt`.
- **HyperSpy/eXSpy:** `H/` is hyperspy 2.4.0 and `E/` is eXSpy `7185a4d1`, both as `path:line`.

The vendor documents stay in the session scratchpad and are not committed (copyright; dossier "How claims are
marked"). The eXSpy and HyperSpy sources are public at the pinned versions.

**How claims are marked.** VERIFIED = read at the cited place. WEB = public web page. UNVERIFIED = nobody confirmed it.

## The comparison

| Q | Velox 3.15 | GMS 3.6 | HyperSpy / eXSpy | AZtecTEM · ESPRIT |
|---|---|---|---|---|
| **Q1 fit estimator** | **No estimator control.** The principles text says "maximum likelihood fit" with non-negativity, each family fitted whole (line 8087–8089). The how-to says the SI default is "least square (Empirical) fit without Background Correction" (9057–9058). The two are never reconciled. The user picks only the background model. VERIFIED | MLLS peak-family fit (release notes :422–427). Weighting and options UNVERIFIED | **The user picks** the loss (`ls`, `ML-poisson`, `huber`), the optimiser (lm … SHGO), bounds and weighting by variance. Default: `lm` + `ls`. Line areas are forced non-negative (`H/model.py:1772–1900`; `E/models/edsmodel.py`). VERIFIED | AZtec: filtered least squares, no estimator choice. ESPRIT: "series fit" as default, with deconvolution settings in a method editor (:3344) |
| **Q2 background** | Empirical (3-parameter Bethe-Heitler, whole spectrum) or multi-polynomial in windows, order 0–2. Windows Auto or manual. Rule: the residual in the windows should look like noise (2021–2075, 9078). VERIFIED | "Full background modelling", fitted jointly. Kramers shape (WEB). Controls UNVERIFIED | Windows (`estimate_background_windows`, scaled mean) or a polynomial in the model (order 6). No physical continuum (`E/signals/_eds.py:549–702`) | AZtec: inside FLS, no control. ESPRIT: physical bulk, physical thin lamella, or mathematical; windows automatic, preset or dragged (:3320–3330) |
| **Q3 k source** | Cliff-Lorimer, k computed from a **cross-section model dropdown: Brown-Powell (default), Bote-Salvat, Schreiber-Wims**. 20 % k error assumed. **The manual has no user-k, measured-k or ζ entry** (2103–2116, 9150–9201). `K_Custom.csv` / `MeasuredKfactor` stay UNVERIFIED hints outside the manual | UNVERIFIED (help pages needed) | **No table built in.** The user passes k, ζ or σ by hand. Method: CL / zeta / cross_section. Only ζ↔σ converters exist (`E/signals/_eds_tem.py:297–585`) | AZtec: modified CL with thickness and density, k theoretical **or user-defined**. ESPRIT: standardless or standards CL, **ζ** (beam current or system factor), bulk PB/ZAF |
| **Q3 absorption** | Tick, sample thickness, optional density. Super-X geometry with segments and tilt shadow. No fluorescence (2079–2092, 9116–9147) | UNVERIFIED | Iterative x/(1−e⁻ˣ), Chantler MACs, take-off from tilt, azimuth and elevation. Off by default (`E/utils/eds/_quantification.py:201–316`) | AZtec: automatic once mass thickness is known. ESPRIT: built in |
| **Q5 line ID** | Auto ID. A four-state periodic table, including **"Deconvolution only"** (fitted, excluded from at%) (1895–1986) | UNVERIFIED | Manual `add_elements` / `add_lines`. No auto-ID and no exclude state | — |
| **Q6 artefacts** | No escape, sum or pile-up handling in the manual. Shadowing handled by disabling segments (9319–9342) | UNVERIFIED | None (`validation.md:263`) | AZtec: pile-up correction on/off |
| **Q7 fit quality** | Spectrum / Background / Modelled / Residual toggles. No χ². "Use optimized spectrum fit" + Re-measure (951–958, 9204–9316) | UNVERIFIED | Residual plot; χ² and reduced χ² **for `ls` only** (`H/model.py:1800`) | — |
| **Q8 errors** | Fit error and at%/wt% error in the **Experiment Log**, combined with the 20 % k term. Export Quantification Details (1294–1304, 9188–9201, 9549–9575) | UNVERIFIED | **None from `quantification`.** Only the per-parameter `p_std` of a fit (`E/signals/_eds_tem.py:552–585`) | AZtec: σ per wt%. ESPRIT: user-selectable σ level |
| **Q9 filtering** | Count-conserving pre-filter (Average or Gaussian), with a "Counts" indicator recommending a kernel. Post-filter acts on the output only (2162–2275, 8770–8863) | MSA tool (PCA, denoise) since 3.4 (WEB) | Poisson-scaled SVD/NMF with a vacuum mask; quantifying the denoised cube is the user's choice (`E/signals/_eds_tem.py:631–752`) | — |
| **Q10 saved settings** | **Named "Quantification Settings" and "Element Settings" files.** Saved and loaded from the EDS menu, reusable in batch (9455–9601) | UNVERIFIED | No settings object. Metadata tree plus a stored model; fit choices and k are **not** recorded (`H/model.py:599–624`) | AZtec: Quant Settings templates. ESPRIT: named, savable methods (Default, Oxides, Standards, TEM) |
| **Q11 parity** | Not addressed | UNVERIFIED | Pinnable: windows, FWHM, CL, ζ, σ, absorption, `ls`+`lm` fits. **Not pinnable:** ML-poisson, huber, global optimisers, fd-gradient std | — |

## What the columns change in the brief

1. **The industry standard does not offer a fit-estimator switch.** Velox, AZtec and (as far as is documented) GMS each
   fit one way. The user tunes the *background model*, the *windows*, the *element states* and the *cross-section/k
   model*. Only HyperSpy exposes the estimator, and it is a library. This is the owner's call: "orient on the industry
   standard" and "let the user choose the fit" point in different directions here.
2. **The user always chooses the k source somewhere.** Velox has three cross-section models; AZtec and ESPRIT have
   theoretical or user k, plus ζ in ESPRIT. HyperSpy makes the user supply k. Shipping "no at% until a k source exists"
   would sit below every vendor.
3. **Errors and saved settings are where the vendors beat HyperSpy.** Velox has per-element errors in a log and named
   settings files. ESPRIT has named methods and selectable σ. HyperSpy has neither. The app's replay record (ADR 047) is
   the natural home for a named settings object.
4. **GMS is still the unknown column.** The installer documents describe features, not dialogs. The owner's GMS
   help-page export (the brief's evidence item 1) is the only way to fill it. The questions to look up are listed below.
5. **Corrections to the earlier sessions:**
   - "Velox probably accepts custom or measured k" (the session's reply, 2026-10-05): the manual shows no such entry.
     It is unverified.
   - The Velox LS-vs-ML contradiction is real but moot for the UI, because the user is never offered the choice.

## For the owner at a GMS PC (Help › Elemental Analysis (EDS), or the Elemental Quantification dialog)

1. Which methods are offered: Cliff-Lorimer/k, typed k, standards, ζ with beam current? Is the default k a theory table,
   and from where?
2. Is there an absorption or thickness correction, and what does it ask for?
3. Is the MLLS weighting Poisson or uniform, and which fit controls are shown?
4. What is the background model called, what are its parameters, and are the windows editable?
5. Is there auto element ID? How are escape, sum, pile-up and the Mg/Al overlap handled?
6. Is a residual or fit-quality number shown? Which errors are shown?
7. Can quantification settings be saved as a named object? Are they written into the `.dm4` tags?
8. Can quantification read a PCA-denoised SI? What are the units of a quantitative map?
