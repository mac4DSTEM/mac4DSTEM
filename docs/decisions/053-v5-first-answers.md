# 053 — v5.0: the first five card answers; quantification goes to a design session

Dates: 2026-10-05

Status: **accepted** (owner, 2026-10-05, answering the v5.0 cards of `docs/archive/v5/owner-decisions-2026-10-05-v5.json`).
Builds on ADR 052. Nothing here is implemented yet.

## Decision

1. **V5-1, the science question: c, then a.** First, Si segregation at LPBF cell boundaries. It runs on the 104 existing
   Velox files with plain EDX plus a thickness input, and needs no joint method. The diffraction-regularised map (G) must
   not be used for it. Second, Mg/Si per precipitate class. That needs a registered pair, the Al-Mg-Si CIF set and a
   separability matrix before any arbitration table. Strategy S1 is built and S2 pre-registered.
2. **V5-2, the acquisition route: R4 first, then a STEMx test.** The owner books one sequential session: an EDX spectrum
   image at the 051 field and tilt (α −16.87°), full stream, two probe currents noted, plus an EELS t/λ map of the same
   field. In parallel he asks Thermo, Gatan and Bruker service whether GMS can drive Super-X, and what that costs. If they
   confirm, a small STEMx test (`.dm4` and `.dm5`) settles the file layout and the identity/lag check. The science numbers
   come from the R4 data. The same-file GMS reader stays conditional.
3. **V5-3: the window opens a spectrum image on its own, and the room mock shows it now.** The mock shows two layouts: EDX
   attached to a 4D cube, and EDX with no cube. Shortcuts: Spectroscopy ⌘6, Results ⌘7 (Results stays last). The window
   currently assumes a 4D cube (`hasDataset == is4D`), so this costs about 3–4 sessions. The frozen-shell rule (ADR 035)
   still applies: the room lands only against a mock the owner accepts, and only once "Unverified on screen" is empty.
4. **V5-4, the data model: two signals plus a registration record (M2).** The record allows reflections (det < 0).
   Spectra are pooled by transporting the masks onto the spectrum's native grid; there is no dense joint cube. A CSR cache
   stays optional until a Swift decode measurement decides it.
5. **V5-6, absorption on summed Super-X G1 data: the badged four-detector geometric correction.** The per-quadrant
   take-off spread and the thickness σ are propagated. The correction is refused only when geometry or tilt is unknown.
6. **V5-5 (k-factors) and V5-7 (parity and fit policy) are not answered. They move to one quantification design
   session**, and V5-8 (joint scope) and V5-10 (thickness/EELS) wait for it. The owner's steer, 2026-10-05:
   - An EDX suite that does not let the user choose the fit is a black box.
   - The app orients on the industry standard: how Velox and GMS do it, and how HyperSpy does it.
   - "No k source" was too narrow. Velox computes k from a choice of three cross-section models.

   The dossier's resolution "one science default, provenance names the estimator, no mode switch" (§5.1 "Modes") is
   therefore **reopened**, not adopted. The brief is `docs/archive/v5/quant-design-brief-2026-10-05.md`.

## Consequences

- The "no filler" rule (CLAUDE.md "What the app is") does not, on its own, remove a scientific choice that users of the
  standard tools expect to make. The design session tests each quantification control against that rule on the
  evidence. A control that changes the number earns its place if the reader needs it to judge the number.
- Parity and the UI are separate questions. The parity harness may still pin least-squares fits only, because
  HyperSpy's Poisson-ML output depends on the optimiser and the start. That is a test rule, not a limit on what the app
  offers.
- On the owner's side: book R4, ask service, and export the GMS help pages (EDS / Elemental Quantification, STEM SI) on
  a GMS PC. Those pages are the one source the design session cannot get any other way.
