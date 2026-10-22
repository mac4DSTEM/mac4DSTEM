# Parity with the published references (app level)

The kits' own parity tables are `../<Kit>/docs/parity.md`. This file lists what the app has been checked against as a whole.
Numbers match the reference within its own spread, never stricter (suite rule D17).

## Precipitation workflow: Thronsen et al., Ultramicroscopy 255 (2024) 113861 (Al-Cu-Li, T1 + θ′, SPED)

Data: Zenodo 10.5281/zenodo.6645396 (CC BY 4.0, kept outside the repo in `References/mac4DSTEM/thronsen-datasetA`). Dataset A, 512 × 512
(PDF page 3), stride 3 here (171 × 171; the full cube is not on this disk). Facts, page and table per number: `mac4DSTEMTests/Fixtures/thronsen-parity/truth.json`.
Run (heavy, real data, skipped unless asked; 8 GB cap): `../tools/memcap.sh --gb 8 -- env TEST_RUNNER_MAC4DSTEM_THRONSEN=1 MAC4DSTEM_UNIT_ONLY=ThronsenParityTests tools/run-tests.sh unit`
(`mac4DSTEMTests/ThronsenParityTests.swift`, 8 s after the build).

| Check | Reference | Ours | State |
|---|---|---|---|
| Phase map accuracy, the paper's metric (share of positions equal to the manual ground truth, all classes counted) | Table 3 (PDF page 11), full resolution: NMF 98.50, vector matching 98.46, template matching 98.25, ANN 99.04 % | **98.69 %** at stride 3 (383 of 29 241 positions differ; 774 243 peaks) | inside the paper's spread (98.25 to 99.04); the published maps at stride 3 are 98.44 / 98.49 / 98.30 / 99.05 % (computed by us from the Zenodo maps, not published) |
| Same, as the adopted T4 bar (ADR 040, 041) | per-position error 1.31 % | 1.31 % | reproduced; pinned in the test (±0.05) |
| Object statistics: count, Feret length, edge-corrected areal density (tasks 39 and 41) | none in the paper; derived from the truth map, **not published** | see below | exercises the pipeline end to end; unvalidated |
| The four published maps against the truth at full 512 × 512 with the paper's scorer (`determine_accuracy.ipynb`: share of positions with label ≠ truth, every class and the four "not indexed" truth positions counted) | Table 3: 98.50 / 98.46 / 98.25 / 99.04 % | **98.5020 / 98.4570 / 98.2521 / 99.0391 %** | reproduced to 0.01 pp (`testThePublishedMapsReproduceTable3AtFullResolution`, runs when the maps are on disk); at stride 3 the same maps score 98.44 / 98.49 / 98.30 / 99.05 % |
| N_V, composition, strain | none (no thickness, no EDS in the dataset) | not checkable here | said so, not scored |

**The scan step (2026-10-22, flagged for Paul).** Everything below uses the paper's **4.6 nm per position** (PDF page 3; 13.8 nm at stride 3). The file's 2.4943 nm
(settled 2026-09-28 on the belief that Fig. 7's scale bar agreed) does not: on PDF page 8 the three 400 nm bars are 82, 82 and 81 px, panel (c) is registered to
`ground_truth.hspy` (99.8 % of its classified pixels equal the truth class) and is 487 px for 512 positions, so the step is 4.66 ± 0.06 nm, 1.87 times the file's. With
the file's step lengths read 1.87 times too short and densities 3.5 times too high (the earlier version of this table: 7.48 nm per position at stride 3). `truth.json`
(`datasetA.scale`) holds the measurement; the decision is reversible by one constant (`ThronsenParityTests.stridePixelNm`).

**Objects, the spread.** Count of counted objects (edge-touching ones are listed, not counted), median Feret length (nm) and edge-corrected areal density (/µm²) per class,
at stride 3 (13.8 nm per position), through the app's pipeline (`classObjects`, `PrecipitateObjectReport`). The truth and the four published maps are the Zenodo maps
[::3, ::3]; "ours" is the T4 run. **Derived, not published** (the paper reports no object statistics). "Inside" means inside the range of the four published maps.

Every object kept (minimum size 1):

| class | truth | NMF | vectors | template | ANN | ours | ours vs the four |
|---|---|---|---|---|---|---|---|
| θ′ edge-on, count | 70 | 77 | 48 | 39 | 47 | 75 | inside |
| θ′ edge-on, median Feret | 13.8 | 13.8 | 87.3 | 100.5 | 56.9 | 27.6 | inside |
| θ′ edge-on, density | 13.3 | 14.5 | 9.4 | 7.7 | 9.1 | 14.2 | inside |
| θ′ face-on, count | 3 | 113 | 35 | 21 | 10 | 35 | inside |
| θ′ face-on, median Feret | 323 | 13.8 | 13.8 | 13.8 | 13.8 | 13.8 | inside |
| θ′ face-on, density | 0.7 | 21.0 | 6.6 | 4.0 | 2.0 | 6.6 | inside |
| T1, count | 21 | 39 | 22 | 28 | 22 | 26 | inside |
| T1, median Feret | 187.7 | 138.7 | 187.7 | 148.0 | 194.3 | 148.0 | inside |
| T1, density | 5.0 | 8.6 | 5.2 | 6.4 | 5.2 | 5.9 | inside |

Single-position objects dropped (minimum size 2):

| class | truth | NMF | vectors | template | ANN | ours | ours vs the four |
|---|---|---|---|---|---|---|---|
| θ′ edge-on, count | 32 | 29 | 37 | 31 | 30 | 40 | **above** (29 to 37) |
| θ′ edge-on, median Feret | 87.3 | 87.3 | 117.9 | 148.6 | 142.4 | 56.9 | **below** (87 to 149) |
| θ′ edge-on, density | 6.3 | 5.7 | 7.3 | 6.2 | 6.0 | 7.8 | **above** (5.7 to 7.3) |
| θ′ face-on, count | 3 | 38 | 8 | 5 | 3 | 5 | inside |
| θ′ face-on, median Feret | 323 | 27.6 | 34.5 | 297.9 | 314.7 | 284.5 | inside |
| θ′ face-on, density | 0.7 | 7.2 | 1.7 | 1.1 | 0.7 | 1.1 | inside |
| T1, count | 20 | 26 | 20 | 20 | 21 | 20 | inside |
| T1, median Feret | 242.0 | 302.4 | 242.0 | 293.1 | 200.9 | 239.4 | inside |
| T1, density | 4.8 | 6.2 | 4.8 | 4.9 | 5.0 | 4.8 | inside |

Where it matters: T1 and θ′ face-on are inside the published spread however they are counted. θ′ edge-on is inside only with every speckle kept; once single positions are dropped our
thin needles are cut into more, shorter objects (40 against 29 to 37, median 57 nm against 87 to 149). That is the object-level face of the map's one failure (T1 patterns read as Al,
204 of 383 positions) and of the 55 Al → θ′ edge-on positions. Full resolution, published maps only (ours exists at stride 3 only; step 4.6 nm; count / median Feret / density):
truth 33 / 166.7 / 6.6 (edge-on), 3 / 312.8 / 0.7 (face-on), 25 / 266.8 / 6.0 (T1); NMF 32 / 167.9 / 6.4, 514 / 4.6 / 94.0, 76 / 12.0 / 15.6; vectors 51 / 86.4 / 9.9, 246 / 4.6 / 45.0, 39 / 139.9 / 8.5; template
52 / 62.9 / 10.1, 152 / 4.6 / 27.8, 82 / 4.6 / 16.3; ANN 35 / 148.6 / 6.9, 60 / 4.6 / 11.1, 35 / 148.6 / 7.7. Single positions dropped at full resolution: truth 32 / 168.8 / 6.4, 3 / 312.8 / 0.7, 25 / 266.8 / 6.0;
NMF 31 / 169.1 / 6.2, 222 / 14.5 / 40.9, 50 / 124.9 / 10.9; vectors 32 / 170.0 / 6.5, 63 / 10.3 / 11.7, 36 / 151.5 / 8.0; template 32 / 170.0 / 6.4, 11 / 14.5 / 2.2, 38 / 122.3 / 8.3; ANN 32 / 168.8 / 6.4, 5 / 287.6 / 1.1, 25 / 232.7 / 5.9.

**Edge check.** Share of wrong positions within 2 positions of a truth boundary (the paper's statement is that most errors sit on interfaces): ours at stride 3 **96.6 %** (370 of 383); the published maps
at stride 3 91.9 / 93.9 / 98.6 / 98.9 % (NMF, vectors, template, ANN) and at full resolution 87.0 / 85.3 / 93.5 / 93.3 %. Ours is inside the published range at either resolution.
Isolated one-position objects (all precipitate classes): truth 1 at full resolution (40 at stride 3, the truth's thin needles); published full 321 / 207 / 208 / 69, stride 3 141 / 42 / 34 / 27; ours at stride 3 75.

**Variants and morphology** (from the winning library entries of our run, not from the variant map: its relationship preset is beta'' in Al; presets for T1 and θ′ do not exist yet). In-plane rotations of
the winning entries per class: T1 (6151 positions): 176° and 178° and 184° (about 3300) against 86° and 88° (about 1800), two families 90° apart, the paper's two; θ′ edge-on (465): 60° / 62° / 240° against
150° / 152° / 330°, two families 90° apart (the opposite pair of each is the same variant by the 180° symmetry), the paper's two; θ′ face-on (1000): 150°, 240°, 60° / 62°, 330°, one family up to the cell's 90° symmetry, the paper's one.
Scan-versus-diffraction offset: our matrix entry sits at 150.0° in-plane; the paper rotated its stack by φ_A = −29.65° (PDF page 7), which is 150.35° modulo 180°, 0.35° from ours (our grid step is 2°).
Feret-angle families of the counted objects (minimum 4 px, image frame, positive clockwise on screen; truth / ours): θ′ edge-on −30..−15°: 9 / 11 and +60..+75°: 7 / 9 (families 90° apart); T1 −90..−45°: 8 / 8 and 0..+45°: 9 / 9 (90° apart); θ′ and T1 families sit 45° from each other,
as the paper's text says (T1 along [110] and [1-10] of Al, θ′ along [100] and [010]); our map reproduces the truth's families.

**Read, not tested.** Table 2 (PDF page 3) against our three structures (`ThronsenReference`): θ′ the same (a 4.04, c 5.80, I-4m2, Al and Cu positions); T1 the same lattice (a 4.94775 against the table's 4.95, c 14.14499 against 14.15: the cell compressed to the paper's
a_Al = 4.04 Å) and the same Cu, Li and Al (1/3, 0, 0) positions, **but the table's Al at (0, 1/2, 0.406) is (0, 0, 0.4062) in our structure**: not explained, to be tested by building the other and comparing the T1 ⟨0-41⟩ spot list; Al a = 4.04 in the table against the kit preset's 4.0495 (0.23 %, below the pair radius).
Fig. 2 (PDF page 4) shows the same four zone axes our library samples (Al ⟨001⟩, θ′ ⟨001⟩ and ⟨100⟩, T1 ⟨0-41⟩); the spots were not compared one by one, and the max{s} of 0.030 / 0.050 / 0.030 / 0.022 Å⁻¹ belong to the template and ANN simulations. Section 3.5's vector matching against ADR 044 and the kit's matcher:
same: reference vectors from a thin slab (0.030 Å⁻¹ for T1, 0.300 Å⁻¹ for θ′, which our per-phase excitation slab carries), lattices rotated in-plane to the matrix's rotation, the matching score Σ|u − v| / N_v over unique reference vectors, patterns with too little left read as the matrix;
different: the peak finder (theirs Laplacian of Gaussian plus centre of mass, ours the probe-kernel disk detector at a 0.15 % floor, ADR 041, because one detector serves strain, orientation and phase), the Al removal (theirs from one Al-only pattern, ours from the fitted matrix entry), and the not-indexed cut (theirs a score above 0.07 Å⁻¹, ours the known-variants rule and the chance-match guard);
why: the app has one disk set for strain, orientation and phase (ADR 044), and the 2026-09-28 comparison ran at the same reported accuracy. (The comment in `PhaseDefinition` that cites the slab values as "their Table 2" means Section 3.5.)

**Side by side.** The pictures are offline renderings, not screenshots of the app: Fig. 7(c), the truth at stride 3, our map and the 383 positions where they differ
(`thronsen-maps.png`, sent to the thread and not kept in the repo; unverified on screen in the app). Not done: our VDF with the aperture of Fig. 7(d) against 7(b), and our patterns at the four coloured rectangles of 7(b) against 7(d) to 7(g) (they need the app on the full cube or a drive).
Not claimed: dataset B (no truth known), N_V, composition and strain (not in the paper); Supplement S1 to S4 is not on disk.

Where the maps differ (positions, truth to ours): T1 to Al 204, Al to θ′ edge-on 55, θ′ face-on to Al 26, Al to face-on 25, Al to T1 24. More than half of all disagreeing positions are one failure: T1 patterns read as Al (204 of 383 positions, 0.7 % of the scan).
