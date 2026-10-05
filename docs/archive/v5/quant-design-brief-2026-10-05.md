# v5.0 quantification design session — brief (2026-10-05)

**Why this session exists.** The owner answered five v5.0 cards (ADR 053). He sent V5-5 (k-factors) and V5-7 (parity and
fit policy) back:

- "how can you design an EDX suite and not let the user choose the fit that was used??? this will turn it into a
  blackbox"
- "we should orient our app from this industry standard"

The dossier (`edx-dossier-2026-10-05.md` §5.1) had settled on one hidden science default with no switch. That settlement
is reopened. This session designs the quantification pipeline and the controls it shows, layer by layer, against
Velox, GMS and HyperSpy. **No code.** The output is a decision sheet and a panel mock.

## Fixed inputs (do not re-open)

ADR 052 and ADR 053:

- Science question c, then a.
- R4 acquisition.
- A spectrum-only window.
- Data model M2 with mask transport.
- Badged four-detector absorption.
- A port of eXSpy pinned at `7185a4d1`, with hyperspy 2.4.0 and rsciio 0.14.0.
- The k-free quantities (net counts, Mg/Si count ratio, enrichment over the matrix blank, with intervals) stay *available*
  whatever is decided about at%.

## The questions, one per pipeline layer

For each layer, the session fills in five columns: **Velox | GMS | HyperSpy/eXSpy | dossier draft | proposal**. The
proposal states which choice the user sees, the default, and what is recorded in provenance.

| # | Layer | What is open | Known so far (source) |
|---|---|---|---|
| Q1 | Fit estimator | Least squares vs Poisson-ML (vs weighted LS, Huber): a user choice, and which is the default? | Velox: "maximum-likelihood with non-negativity" in one place, "least square (Empirical) fit" as the SI default in another (UM p.230 vs p.262, `reports/velox.md`). GMS: MLLS peak-family fit (`reports/gms.md` :141). HyperSpy: the user picks loss and optimiser. LS vs converged Poisson-ML differ by 2.9 % on FePt (`second-opinion` C4). |
| Q2 | Background | Which models are offered: windows, polynomial, physical continuum (espm, Bethe-Heitler)? | Velox: "Empirical" (3-parameter Bethe-Heitler) or multi-polynomial in windows. HyperSpy: polynomial or windows. Dossier: espm continuum. |
| Q3 | k source | Which of these: cross-section models (Brown-Powell, Bote-Salvat, Schreiber-Wims as in Velox), user-typed or measured k, ζ, cross-section method? Is at% shown in v5.0? | Velox: three models, Brown-Powell by default, a ±20 % k rule, `K_Custom.csv` in the installer, `MeasuredKfactor` in its manifest (`reports/velox.md` :135–158). HyperSpy: the user supplies k, ζ or cross-sections, with no table built in. GMS: unverified. |
| Q4 | Data rights for Q3 | Can each cross-section model be implemented from its published papers? Can the EPQ tables be used? | Unverified. The installer's own `K_Custom.csv` is studied, never copied. |
| Q5 | Line ID | Manual-first, an auto-proposer, or Velox's "fit but exclude from at%" state? | Dossier §5.1. Velox: Auto-ID plus a four-state periodic table. |
| Q6 | Peak shape and artefacts | Escape peaks, sum peaks, pile-up, and the Al Kα tail under Mg Kα: which are modelled, flagged, or handled by the matrix blank? | Dossier §5.1. |
| Q7 | Fit-quality display | Residual view, χ² or deviance, and the Velox tuning rule ("residual should look like noise") | Velox UM p.263. |
| Q8 | Errors | Which σ terms are shown and how: counting, k, absorption, thickness, reported separately or combined? | Velox: errors in an Experiment Log. HyperSpy: no error bars from `quantification`. Dossier §5.2: statistics layer. |
| Q9 | Filtering and decomposition | Pre-filter kernel, PCA or NMF; quantification never reads a denoised cube? | Velox: count-conserving pre-filter and post-filter. HyperSpy: Poisson-scaled PCA. |
| Q10 | Settings as an object | Is there a saved, named "quantification settings" (as in Velox) that replay and provenance carry? | Velox saves Quantification Settings files. The app has a replay record (ADR 047). |
| Q11 | Parity | Which paths are pinned against eXSpy (the dossier says LS only, windows, CL, absorption, ζ), and how are the app's own estimators tested where eXSpy cannot pin? | `reports/validation.md` §1b, dossier §7. |
| Q12 | Scope knock-ons | V5-8 (joint scope) and V5-10 (thickness/EELS), re-asked in light of Q1–Q11 | Cards in `owner-decisions-2026-10-05-v5.json`. |

**The test every control must pass** (CLAUDE.md "What the app is", ADR 053): it changes the number, and the reader needs
it to judge the number, or a user of the standard tools would look for it. Otherwise it goes. Expert-only controls may
sit behind a disclosure. The session proposes, for each control, whether it is visible, disclosed or absent.

## Evidence still missing

1. **The GMS help pages.** EDS / Elemental Quantification and STEM SI. They exist only inside GMS's installer or on a GMS
   PC. **Owner:** export them on a GMS PC. If they are missing, the GMS column says "unverified" and the session carries on.
2. **Velox in use.** The manual contradicts itself on the default fit. One look at the Velox quantification panel on the
   acquisition PC (2.15) settles it, through a screenshot or the owner's word.
3. **Oxford and Bruker quantification options.** From `reports/market.md` only. No new vendor material is needed unless a
   question cannot be decided without it.

## How the session runs (ADR 050 sheet format)

1. **Research, about 1 hour of agents, no code.** One agent per column (Velox, GMS, HyperSpy/eXSpy), all reading the
   committed reports. The HyperSpy agent also reads the pinned eXSpy source, and the Velox agent also reads the manual in
   the scratchpad if it still exists; otherwise it uses `reports/velox.md`. A fourth agent drafts the proposal column.
2. **An independent second opinion** on the proposal column (a different model, which sees the evidence but not the
   draft's reasoning).
3. **A quantification panel mock** inside the Spectroscopy room mock (V5-3): label left, control right, flat stack, and
   the expert block behind a disclosure. Each row is costed in points before it is drawn.
4. **The owner's sheet**: Q1–Q12, each with options, effort, risk, a recommendation and the second opinion. It is rendered
   on the Board and committed beside the v5 cards.

## Output

- Answers to V5-5, a recast V5-7, V5-8 and V5-10, recorded as an ADR.
- Dossier §5.1 amended: the "Modes" paragraph replaced by the decided controls.
- Then the v5.0 pre-registration (ROADMAP § How a feature is done) and the first `/pickup` work package: P0, the tables
  and readers.
