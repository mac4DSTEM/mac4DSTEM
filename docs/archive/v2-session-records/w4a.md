# W4a — S14 + S15 merged: the WS₂ crystal model (2026-08-31)

Run under the owner's four recorded decisions (§9, 2026-08-31): W4 runs in v2;
the lattice is the literature cell; S14+S15 merge as one session with TWO
refuters; mid-session issues take safe defaults (measure, report, file — never
fix out of scope).

## The lattice, from the primary source

The session fetched and read the actual paper — W. J. Schutte, J. L. de Boer,
F. Jellinek, *J. Solid State Chem.* **70**, 207–209 (1987),
doi:10.1016/0022-4596(87)90057-0 — not a database transcription of it.
Table I, 2H-WS₂ column: **a = 3.1532(4) Å, c = 12.323(5) Å, z(S) = 0.6225(6)**;
Results: W at 2(c) ±(⅓,⅔,¼), S at 4(f) ±(⅓,⅔,z; ⅓,⅔,½−z). The brief's
uncited "a ≈ 3.153, c ≈ 12.323" is exactly this refinement. The four staged
`WS2_mp-224_*.cif` are DFT (c = 14.2024, the missing-vdW artifact) and are
recorded as NOT the matching reference.

## Shipped

- `Crystal.tungstenDisulfide` — six explicit sites, the paper's own setting,
  full citation and the mp-224/Kalikhman warnings in the header
  (`Core/Crystal/Crystal.swift`).
- `ws2_2h` registered in `CrystalModelLibrary` (`Core/Crystal/CrystalModel.swift`)
  — built-in rather than import-only because the replay record stores only a
  `materialModelID` and imported models do not survive sessions; the library
  entry is what makes a WS₂ recipe replayable.
- `cif-symmetry-test`: the `ws2_2h_schutte1987` case — six explicit sites, no
  symmetry loop, so detection must find the 6₃ screw over a TWO-species basis
  (W→W, S→S at different z), which no other admitted case exercises.
- **`tools/ws2-crystal-test`** — new gated harness, joined `scientific`.
  Analytic ground truth (closed-form hexagonal metric): six |g| checks, the
  6₃-screw extinctions, the c/a = 3.91 shell-order inversion (WS₂ first shell
  is (0002); Mg's is (10-10) — the axis a near-ideal-hcp fixture cannot see),
  a re-derived phase sum, the {10-10} star, **two absolute intensity anchors**,
  and **four negative controls** (z(S) Kalikhman, the mp-224 c, a species swap,
  occupancy consumption), each naming the model line it breaks.
- The **(0002) reference-shell measurement**: the current Q-calibration rule
  (first distinct |g|, no l-filter, no visibility filter) selects (0002) at
  0.16230 Å⁻¹ on WS₂; first in-plane is (10-10) at 0.36621; predicted silent
  mis-scale **2.2563×**. Filed in `docs/open-items.md` per the safe-defaults
  decision — measured and reported, not fixed (W3 territory).

## Gates

**Break-every-new-test:** 7 author mutations, 7/7 caught, each by a distinct
check (one surprise: `validationIssues` itself refuses a broken hexagonal
metric — `hexagonal_symmetry_mismatch`).

**Gate B — two refuters, per the owner's split (one on lattice/import, one on
the fixture), both sandboxed while the unit gate ran:**

*Refuter 1 (lattice/import)* — the model **held** under stronger verification
than it was built with: the Wyckoff expansion re-derived independently and
confirmed by computing every Table II interatomic distance from the shipped
sites (W–S 2.4048 ×6, S–S ∥c 3.1424, interlayer 3.5255 — all within the
paper's σ; this is what pins the ± convention); the numbers checked against
the right Table I column (not WSe₂, not 3R); **py4DSTEM parity verified by
execution** — the vendored py4DSTEM run on the identical basis matches all 638
reflections to ≤1e-7, so no DEVIATION note is owed; the CIF admission traced
to the screw specifically (the pure-rotation candidate fails). One confirmed
defect, comment-only: "inflates the inter-layer gap ~15%" attached the number
to the wrong quantity — c inflates 15.25%, the S-plane gap 31.0%. Fixed.
Bonus measurement: the cube's mean pattern is **pure hk0** (ratios
1 : √3 : 2 : √7 : 3, no (00l) ring, inner-annulus mass 350× below ring 1) — so
c is invisible to this dataset and the operative mp-224 error for W4b's
matching is **a, +1.19%**, not c.

*Refuter 2 (fixture)* — found the review's decisive hole: **six
screw-preserving site errors left the entire fixture green** (2×–200×
intensity distortions), including the most plausible real error, the wrong 2H
polytype (W on 2a, NbS₂-type). Structural cause: every check was metric-only,
parity-only, an invariant, or recomputed from the sites themselves — the
fixture pinned a and c to 1e-12 and the sites to almost nothing. Also: deleting
the occupancy factor from `Crystal.reflections()` was green across the entire
gate (all shipped models fully occupied). **Both closed in-session:** two
absolute intensity anchors (I(0002)/I(10-10) = 2.38277,
I(10-13)/I(10-10) = 1.72056, rel 1%) and an occupancy-consumption control.
All seven of the refuter's surviving mutants re-run: **7/7 now red.** The
fixture's scope header was rewritten to say what each check can and cannot
catch, replacing a claim the review refuted.

## Track A on the final tree

`unit` **391 passed / 2 skipped / 0 failed, exit 0** (the documented bookmark
probe + S17 quarantine skips). `scientific`: see §9's stub for the number from
the closeout run. Directly-affected harnesses each green standalone:
`ws2-crystal-test`, `cif-symmetry-test` (29 cases), `acom-matching-test`
(8 models).

## Deviations

1. S14 and S15 ran as one session on the owner's recorded decision — two
   refuters replaced the session boundary, which the feasibility analysis
   showed bought no independent oracle.
2. The expected-orientation fixture is `ws2-crystal-test`'s shell/plan
   coverage plus `acom-matching-test`'s catalog sweep, not a widened
   `acom-groundtruth` — that harness is CI-excluded and gates nothing, so
   widening it would have satisfied the letter of Gate B with a fixture that
   never runs (feasibility critique, item 3).

## Not verified

- **On screen: everything.** F1.44 queued (the model in the picker; Track B).
- ACOM matching on the real cube — that is W4b (S16), deliberately separate.
- The (0002) mis-scale end-to-end in the app: the fixture pins a
  character-identical replica of the selection rule, not the `AppState` code
  path itself; an AppState-only change cannot turn it red (stated in the
  check).
- The scattering-factor table's own values (py4DSTEM-ported, gated elsewhere).
- Whether the cube was simulated from py4DSTEM's own `WS2.cif` — that file is
  a Google Drive download, not on this machine; the owner's go-ahead would be
  needed to fetch it (refuter 1 showed the question is nearly moot for this
  dataset: pure hk0, uncalibrated).
