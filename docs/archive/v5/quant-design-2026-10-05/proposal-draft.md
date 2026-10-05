# Quantification proposal — draft (lane D, Fable 5.1, 2026-10-05)

This is the agent's handback, saved by the session. **It is a draft.** The independent second opinion and the owner's
answers decide.

**How it is marked.**

- "Pin" = pinned against eXSpy `7185a4d1`.
- "§" = `../edx-dossier-2026-10-05.md`.
- **[inference]** = the agent's own reasoning, not in the cited files.

**What is already fixed (ADR 053):** the fit is option 3 (one default named on every result, the estimator behind an
expert disclosure), and absorption is the badged four-detector correction.

| Q | Proposal | Effort | Validation |
|---|---|---|---|
| **Q1 estimator** | **Default Poisson-ML** (IRLS, non-negative), named in every result's footer: estimator, iterations, converged. **Expert:** least squares. No Huber, no optimiser picker, no bounds: no vendor offers them, and on a fixed design the optimiser is not a scientific choice. **Why ML:** 25–85 counts/px, and Velox's own principles text says ML. The 2.9 % ML–LS gap is a FePt number, so it must be measured on the owner's data; showing the difference when the user toggles is [inference]. | 2 | LS pinned (closed-loop fit within 1e-4). ML is not pinnable: tested on a synthetic tier with a coverage band, and a mutation (ML→LS moves FePt by about 2.9 %). |
| **Q2 background** | **Visible:** "Physical continuum / Polynomial in windows / Windows only". Default is the physical continuum (espm-style, two columns, the app's own line table), like Velox's "Empirical" whole-spectrum fit and ESPRIT's "physical thin lamella". Windows are Auto, editable by dragging on the spectrum (ESPRIT); there is no numeric window table. Polynomial order 6 sits under Expert. | 2 | Windows and poly-6: pinned (FePt 3710/15872, 2754/15090). Continuum: synthetic tier. |
| **Q3 k source and at%** | **Visible row "k-factors"**, with four choices: **Computed — Brown-Powell** (default; Bote-Salvat second; Schreiber-Wims only if its rights clear) · **Typed** (k, σ_k, source required, date) · **ζ-factors** (+ probe current, prefilled from `ScreenCurrent`, marked unverified as probe current) · **None** (k-free only). at% is shown whenever a k source exists, so the app is never below the vendors. Every at% carries a k badge ("Brown-Powell, ±20 % assumed" / "typed ±σ_k, source") and `validation:"none"` until computed k passes on one truth dataset (YAlO₃ 1:1:3). **The k-free panel (net counts, Mg/Si ratio, enrichment over the matrix blank, intervals) always sits above at%:** it answers science question c with no k. A single-line "100 %" is refused. There is no cross-section (σ) mode, as in Velox and ESPRIT. | 3 | CL arithmetic is pinned. Computed k is not (eXSpy ships no table): it is checked against the papers' published tables and YAlO₃ truth. Cross-check against Velox's own at% on 190330 [inference]. |
| **Q4 data rights** | Brown-Powell and Bote-Salvat are implemented from the published papers [inference on rights]. Line weights and fluorescence yields come from NIST EPQ (public domain, notice kept). MACs come from EPQ `FFastMAC.csv` or xraylib (BSD-3). `K_Custom.csv` is never parsed. Rights inside EPQ for Bote-Salvat (Henke, Salvat) stay open (§10 item 12). | 0.5 | A rights memo, plus NOTICE hashes in `inventory`. |
| **Q5 line ID** | A manual element list. Each element is **Quantify / Fit only / Off** (Velox's four states minus "auto"). A Poisson-significant proposer offers candidates in a sheet, and nothing is added without a click. Li, Be, H and He are refused with the reason. Escape (E−1.74) and sum (2E; Al+Mg 2.740, Al+Si 3.226) positions are marked, and the Al-sum vs Ar collision is named. The Cu grid, Ar and sum/escape rows default to "Fit only". | 1.5 | Line energies and FWHM are pinned. The proposer is tested on a synthetic cube with planted nuisances. |
| **Q6 artefacts** | One Gaussian per line, width from the FWHM law, family weights tied (eXSpy, pinned). **Escape peaks** are fitted as tied Gaussians (Expert, on). **Sum and pile-up** are flagged, not fitted; dead time is read from the file (48–60 % on the owner's data). **The Al Kα tail under Mg Kα** is handled by the matrix-pool blank, and every such Mg number says "blank-subtracted against pool X". No tail-shape knob is offered. | 1 | The blank is validated on a Mg-free (Al-Si) region before an unbadged Mg number is shown. |
| **Q7 fit quality** | Data / Model / Background / Residual toggles (Velox). The residual is shown as (data−model)/√model, so a good fit is a flat band at ±1. One number: reduced deviance (ML) or χ²_red (LS), with a tooltip. No "re-measure" button: the fit reruns when any setting changes. | 0.5 | χ²_red is pinned. Deviance gets a unit test. |
| **Q8 errors** | Every pooled quantity shows **σ as a sum of named terms**, expandable: counting (Fisher covariance; Garwood exact below about 20 counts), k, absorption (take-off spread × thickness σ), thickness. The headline is the combined value in quadrature, e.g. "σ 1.3 at% = counting 0.4 · k 1.2 · absorption 0.3". Each pool also shows a Currie L_D and the dose needed. Per-pixel maps carry no σ (display only). | 2 | A coverage band on a synthetic cube (68–80 % at nominal 68 %), broken by shrinking the CI 2×. |
| **Q9 filtering** | The pre-filter (count-conserving, kernel shown, Velox) is a **display** operation on maps. PCA/NMF is a separate "Decompose" step, its outputs badged "reconstructed", and the vacuum mask is shown as a count threshold. **Quantification never reads a filtered or denoised cube;** the quant panel has no filter row. | 1.5 | Poisson-PCA against eXSpy's scaled SVD (a new pin). |
| **Q10 settings** | A named **`QuantificationMethod`** (Velox "Quantification Settings" / ESPRIT "method") holding Q1–Q9's parameters, element states included. It is stored in the sidecar and recorded as one step's parameter snapshot in the session record v2 (ADR 047), so rewind restores it. Export writes it beside the numbers. Shipped defaults: "Thin film (Brown-Powell)" and "k-free" [inference on names]. The result cites the method's hash. | 1.5 | A round trip; a replay reproduces the pinned number. |
| **Q11 parity** | **Pinned:** tables, FWHM, take-off, windows, CL, ζ, σ conversions, absorption, LS fit, Velox four-detector sums. **Tested, not pinned:** Poisson-ML, computed k, the continuum, the blank, the error terms. The owner's streams are diagnostics only. | 1 | — |
| **Q12 scope** | **V5-8:** v5.0 = plain SI + pooling per phase/region; B* and D stay staged. **V5-10:** thickness is typed ± σ; an EELS t/λ map import comes with the GMS run as a reader only; no EELS analysis in v5.0. | — | — |

## Inspector sketch (Quantify panel)

```
Method                 [Thin film (Brown-Powell) ▾]  save…     1
Elements               Al ● Mg ● Si ● Cu ○ Ar ◐  + propose     1
Background             [Physical continuum ▾]                  1
k-factors              [Computed — Brown-Powell ▾]             1
  k table (typed/ζ only)                                       0–4
Absorption             [on] 4-detector · TOA from file         1
Thickness              [  80 ] ± [ 15 ] nm   [from map ▾]      1
Fit quality            deviance 1.04 · residual ▸              1
▸ Expert                                                       1
    Estimator          [Poisson-ML ▾]                          1
    Escape peaks       [on]                                    1
    Assumed σ_k        [20] %                                  1
    Polynomial order   6 (LS/poly only)                        0–1
Results footer: Fit · k · badge · σ terms (expand)             2
```

That is about 9 visible rows, plus 3–4 when Expert is open.

## Cards the draft proposes

| # | Decision | Options (effort) | Draft recommends |
|---|---|---|---|
| C1 | Default estimator | a LS, pinnable (1) · b Poisson-ML (2) | b, LS under Expert |
| C2 | Cross-section models shipped | a Brown-Powell (1.5) · b + Bote-Salvat (2.5) · c all three (3+) | a now, b when the EPQ rights clear |
| C3 | at% in v5.0 | a yes, badged, k-free above (0) · b k-free only | a |
| C4 | Assumed σ_k | a Velox's flat 20 % · b per line from each paper | a, editable |
| C5 | Background default | a physical continuum (2) · b Velox-style polynomial windows (1) | a, b visible |
| C6 | Mg under the Al tail | a matrix-pool blank · b plain fit, badged | a, after an Al-Si control |
| C7 | Thickness in v5.0 | a typed ± σ (0.5) · b + EELS t/λ reader (1.5) | a now, b with the GMS run |
| C8 | Escape peaks | a fitted (0.5) · b flagged | a, under Expert, on |

## What the draft is least sure of

1. **Data rights for the cross-section tables** (Q4). The computed-k default rests on them.
2. **Whether ML beats LS on Al-rich spectra at these counts.** It must be measured on the owner's data first (the
   threshold rule).
3. **The matrix-pool blank.** In an Al-Mg-Si alloy the matrix itself holds Mg, so a rule is needed for what counts as
   the "matrix".
4. **Back-deriving Velox's k from its stored at%** may be impossible.
5. **The row count,** which is uncosted until the room mock exists.
