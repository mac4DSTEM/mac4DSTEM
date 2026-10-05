# EDX research, 2026-10-05 — the evidence behind the v5.0 dossier

One workflow (13 agents) on 2026-10-05: eight researchers, two Fable 5.1 design analyses, an independent second opinion, a
completeness critic and a Fable synthesis — [`../edx-dossier-2026-10-05.md`](../edx-dossier-2026-10-05.md). Read-only on the repo.

- `reports/` — `velox.md`, `gms.md` (the owner's Velox 3.15 and GMS 3.6.1 installers: documentation only, nothing executed or
  decompiled), `formats.md`, `market.md`, `ownerdata.md` (the owner's own files, header reads only), `repo.md`, `validation.md`,
  `v45.md`, `fable-input-paths.md`, `fable-methods.md`, `second-opinion.md`, `completeness-critic.md`.
- `scripts/` and `logs/` — the analysis scripts and the dated runs the reports quote (exspy `7185a4d1`, hyperspy 2.4.0,
  rsciio 0.14.0 in a scratch venv).
- `velox-emd-repro/` — the shipped `H5Reader` discovery on the public Velox test files (rsciio's registry), compiled from the
  `readers cube calibration` sources at the v4.5 cut: 9 of 10 open as a one-row cube from the HAADF stack.
- `../owner-decisions-2026-10-05-v5.json` — the v5.0 decision cards (the Board renders them).

Not committed (copyright, size, privacy): the vendor manuals and data tables carved from the installers, the upstream clones and
venv, the owner's full file listings and comparison images. Absolute paths are redacted (`<owner-ssd>`, `<scratch>`, `~`).
