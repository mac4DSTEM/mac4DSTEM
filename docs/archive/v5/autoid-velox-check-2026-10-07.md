# Auto ID against Velox's own element selection (lane L10, 2026-10-07)

Owner, after the drive: "Auto ID doesn't really work, why can't we do it like Velox?" This lane MEASURES. Nothing in `Core/Spectroscopy/Proposer`
changed; the section "Three candidate rules" is a pre-registration DRAFT for the supervisor's Gate D, not a fix.

## What Velox gives us, and what it does not

There is no Velox code to compare with; the manual says only that Auto ID "matches peaks in a spectrum plot to spectral lines". What the owner's files
do carry is Velox's session state: `Operations/ImageQuantificationOperation/<uuid>` (EMD < 11) or
`SharedProperties/EDSSpectrumQuantificationSettings/<uuid>` (EMD >= 11), a JSON string whose `elementSelection` lists the atomic numbers selected in the
session (rsciio `_convert_element_list`). `VeloxEMDReader.storedElementSelection()` reads it (new, additive). `elementsIdentified` is empty on every file.

**The truth set is the owner's hand selection, not a detection result.** It lists what he meant to quantify (Mg Al Si for an Al-Mg-Si alloy), not what
the spectrum proves. So (a) "recall" is capped by what is visible at all, and (b) a "false" pick can be a real peak he did not select (Cu from the
grid or column, O from an oxide). Precision below is therefore a LOWER bound on the physical precision and is the right quantity only for "does the
list agree with what a microscopist picked".

## The run

Tool: `tools/autoid-velox-check/run.sh` (diagnostic, needs the owner's files; read in place, nothing written beside them) and `analyse.py` (numpy only).
It opens each `SI *.emd` with `SpectrumImageOpener`, pools the whole map (`source.sum(mask: nil)`) and runs `ElementProposer` as
`SpectroscopyRoomController.runAutoID` does: `FitSettings.standard`, no listed elements (a fresh room), the file's axis and beam, 130 eV Mn Kα; the picks
are `AutoIDPresentation.outcome`'s suggestions, the ones the room applies at once.

- Date 2026-10-07, built from seam commit 77088f52 plus lane L10; Apple Silicon, one process, 35 min wall for the whole folder (the brief's 20 min was exceeded: 95 files carry a selection, not 41).
- `tools/autoid-velox-check/run.sh --out $OUT /Volumes/PL_SSD_2TB/NAS_Backup/01_projects`, then `tools/autoid-velox-check/analyse.py $OUT [--dedupe]`.
- 112 `SI *.emd` found; 17 carry no stored selection (skipped); 1 refused ("not a Velox EMD spectrum image"); **4 distinct files (6 with their copies) make the proposer throw `rankDeficient`** (1253, 1140, 0944, 1121: the room would say "Auto ID could not fit this spectrum"); **88 scored**.
- The "41" of the brief is the number of DISTINCT selections (41 different lists), not files. 10 of the 88 are copies of an acquisition counted twice (same name, same pooled counts); the numbers below are on the 78 distinct ones, the all-88 figure beside it.
- 26 of the 78 are Al-Mg-Si files (Mg Al Si, 84 of the 404 truth entries), so those dominate.

| | all 88 | 78 distinct |
|---|---|---|
| Velox elements / app picks / hits | 462 / 611 / 206 | 404 / 539 / 184 |
| precision (hits / picks) | 33.7 % | 34.1 % |
| recall (hits / Velox elements) | 44.6 % | 45.5 % |
| files whose set is exactly Velox's | 0 | 0 |
| files with every Velox element found | 3 | 2 |

The Auto ID fit is far from a statistical fit on these spectra (median χ²ᵣ 212, 21 of 78 not settled): the proposer reads fit residuals.
Recall ceiling (78 files) at the proposer's own bar (every proposed candidate picked, none held back): 226 of 404 = 55.9 %.

## False picks (355 on the 78 files)

Not in Velox's list. 163 K, 144 L, 48 M. Picks by family: K 316 picks / 153 hits (48 %), L 169 / 25 (15 %), M 54 / 6 (11 %).

| # | element, group (energy) | n | what it is |
|---|---|---|---|
| 1 | Cu Kα (8.05) | 41 | a real peak (median net/L_D 27; 38 of the 51 false picks above 10 L_D); grid/column Cu the owner did not select. Not a defect of detection; a scope question. |
| 2 | Ho Lα (6.72) | 33 | same energy in every file, net/L_D median 1.9, never beside a selected line: a fixed residual (11 times on a Si+V or C+Fe sum energy) |
| 3 | O Kα (0.52) | 27 | a real peak (oxide), median 3.3 L_D; V Lα (0.51, a further 17 false picks) is picked beside it in 17 files |
| 4 | Zr Kα (15.78) / Lα | 24 | weak (median 2.0 L_D) |
| 5 | Hf Lα (7.90) | 24 | median 1.4 L_D; 7 times within 1.5 FWHM of Cu Kα |

Next: Ta Mα (1.71, 20 times, 17 on Si Kα 1.74), V Lα (18), Ga Kα (15). 180 of the 355 sit below 2 L_D; 103 sit within 1.5 FWHM of a line of a selected element; 62 on a
sum energy of two selected or picked α lines; 9 are Z >= 89 (Th, U; Velox itself marks Z >= 89 `includeInAutoPeakId: false`). L/M false picks have net/L_D
percentiles 10/25/50/75/90 of 1.1/1.2/1.5/2.1/3.6; the 31 L/M hits 2.8/6.8/11.7/34.5/45.5 (In Lα 11, Ag Lα 7, Pt Mα 5).

## Misses (220 of the 404)

By reason: 104 below the critical level, 44 possible only (L_C < net < L_D), 42 held back as a sum-peak question, 30 not tested at all (C 24, B 3, N 2, Kr 1: no line above 0.45 keV or an excluded noble gas).

| # | element | missed | of | why |
|---|---|---|---|---|
| 1 | Mg | 37 | 38 | net 0 in the fit (36 below L_C); the raw Mg Kα / Al Kα window ratio has a median of 0.002: at most a trace in the pooled spectrum. Not shown to be a proposer fault; check by hand on one Al-Mg-Si file |
| 2 | Si | 27 | 61 | 18 possible only (median 0.7 L_D), 6 held as sum-peak questions |
| 3 | C | 24 | 24 | never tested (Kα 0.277 keV) |
| 4 | Al | 20 | 52 | 18 below L_C (median 0.17 L_D) |
| 5 | Ti | 20 | 26 | 12 below L_C, 8 held as sum-peak questions |

Then O (18 of 40), Sn (12 of 12), Cu (9 of 31, all held as sum-peak questions at a median 27 L_D), Ca, Ni, Fe, Pt. The sum-peak hold withholds 42 Velox elements:
their net/L_D has percentiles 3.0/7.7/17.1/39.8/47.9 (10/25/50/75/90); the 183 held candidates that are not in Velox's list 1.2/1.5/2.0/3.2/8.0.

## Three candidate rules (pre-registration DRAFT, no code changed)

Every figure is a re-selection among the candidates the proposer already returned, on the 78 distinct files, **in sample**: the thresholds were read off this
set (Al-Mg-Si heavy, one detector, one operator). CLAUDE.md: a threshold is a property of the dataset until measured on every dataset it will touch, so the
quantity (net/L_D by class, above) is printed and the cut is illustrative. Baseline 539 picks, 184 hits, precision 34.1 %, recall 45.5 %.

**R1, hygiene with no measured recall cost.** Never Z >= 89 (Velox's own flag) and prefer K over L/M at equal energy: drop an L/M pick that sits within 1.5 FWHM of another *proposed*
candidate's K α. Predicted: 465 picks, 184 hits, precision 39.6 %, recall 45.5 % (all 88: 525 / 206, 39.2 % / 44.6 %). Removes V Lα on O Kα, Ta Mα on Si Kα, Hf Lα on Cu Kα.

**R2, an L/M pick must be corroborated.** L and M picks have 15 % / 11 % precision against 48 % for K. A pick on an L/M group needs net/L_D >= 3 (K keeps the L_D bar). Predicted: 366 picks, 180 hits,
precision 49.2 %, recall 44.6 %; with R1: 363 / 180 / 49.6 % / 44.6 %. A "needs a K-less reason" rule (L/M only when the K α is above the fit range) was measured and is NOT recommended: 356 / 176 / 49.4 % / 43.6 %, it costs hits for nothing R2 does not already remove.

**R3, a strong sum-peak hold is released.** The hold is the largest single cause of lost recall among visible elements (42 held Velox elements, 183 held others, medians 17 vs 2.0 L_D). Release held candidates with net/L_D >= 10:
579 picks, 211 hits, precision 36.4 %, recall 52.2 % (alone). All three with Z < 89: 402 picks, 207 hits, **precision 51.5 %, recall 51.2 %** (R1 + R2 alone: 362 / 180 / 49.7 % / 44.6 %). Risk: the hold exists to stop pile-up peaks becoming elements; this set cannot tell a pile-up from an element, only Velox's list can. The experiment
that would refute R3 is on a spectrum with truth and pile-up (the demo-edx dose ladder, T4): releasing >= 10 L_D must add no element absent from truth.

Not predictable here: a **β-line ratio check** (the proposer fits the family tied, so a β peak is never a free amplitude). Measured on the pooled spectrum with window sums it is useless as built:
unrestricted, on the 88 files it removed 48 of 206 true picks (another element's line pollutes the windows: Ni Kβ beside Cu Kα, In Lβ beside Ag L); restricted to lines clear of every other proposed line it can be applied to 35 of 539 picks (hits ρ median 0.96, false 1.15: no separation).
A real β check needs the joint fit with the β amplitude freed, which means a proposer change, outside this lane.

What no rule here fixes: C (24 files) is never tested; Mg and much Si/Al are at or under noise in the pooled fit; four files make the proposer throw.

## Reproduce

`run.sh --out $OUT <folder>` writes `<n>.json` (axis, beam, every candidate with net, σ, L_C, L_D, conflicts, picked, beside), `<n>.spectrum.u64` (pooled counts) and `summary.json`; `analyse.py $OUT --dedupe` prints every table above.
Per-file result of the run (file number, Velox, app, hits; the same file name can sit in two folders):

```
1508 | velox: Al Si Ca Cr Fe Cu | app: Al Cu Si Rh Ru Bi | hit 3/6 | extra 3
1647 | velox: C Al Ni Pt | app: Fe W Cu Ga Al Zr Rh Y Ce | hit 1/4 | extra 8
1726 | velox: C Al Cr Fe Ni | app: Fe W Al Ga Cu Ru Ce Ta Rh Zr | hit 2/5 | extra 8
1735 | velox: C Al Cr Fe Cu | app: Fe W Al Ga Zr Ru Rh Ce Rb | hit 2/5 | extra 7
1738 | velox: C Al Cr Fe Cu | app: Fe W Cu Ga Tm Zr Ru Rh Ce | hit 2/5 | extra 7
1610 | velox: C O S Fe | app: Fe Ca K S Cu | hit 2/4 | extra 3
1615 | velox: O Na Al Si S Ca Fe Cu | app: Fe Ca Au Cu | hit 3/8 | extra 1
1151 | velox: C O Ca Cu As Kr Zr | app: Zr Cu Mo Si Hf Ho | hit 2/7 | extra 4
1315 | velox: C O Mg Zr | app: Cu Zr F Hf Mo Th Si Y Ho O | hit 2/4 | extra 8
1339 65000 x 20260508 | velox: Mg Al Si | app: Cu Al O Eu Hf Co Ho | hit 1/3 | extra 6
1840 23000 x 20260506 | velox: Mg Al Si | app: Cu Al O Ho Ta Ru | hit 1/3 | extra 5
1909 11500 x 20260506 | velox: Mg Al Si | app: Cu Al O Ho Ta Ru | hit 1/3 | extra 5
1949 91000 x 20260506 | velox: Mg Al Si | app: Cu Al Ru O Ho Ta | hit 1/3 | extra 5
1312 11500 x 20260508 | velox: Mg Al Si Pt | app: Cu Al Eu Ho Hf Mn | hit 1/4 | extra 5
1312 11500 x 20260508 | velox: Mg Al Si Pt | app: Cu Al Eu Ho Hf Mn | hit 1/4 | extra 5
1402 23000 x 20260605 | velox: Mg Al Si | app: Cu Al O Ta Hf V Eu | hit 1/3 | extra 6
1438 33000 x 20260605 | velox: Mg Al Si | app: Cu Al O Ho Si V | hit 2/3 | extra 4
1509 65000 x 20260605 | velox: Mg Al Si | app: Cu Al O Si Ho V | hit 2/3 | extra 4
1534 16500 x 20260512 | velox: Mg Al Si | app: Cu Al O Ta Hf V | hit 1/3 | extra 5
1537 91000 x 20260605 | velox: Mg Al Si | app: Cu Al O Si Ru Ho V | hit 2/3 | extra 5
1549 11500 x 20260512 | velox: Mg Al Si | app: Cu Al O Ta Hf Eu | hit 1/3 | extra 5
1606 130 kx 20260512 | velox: Mg Al Si | app: Cu Al O Ho Ta V | hit 1/3 | extra 5
1623 91000 x 20260512 | velox: Mg Al Si | app: Cu Al O Si Hf | hit 2/3 | extra 3
1633 46000 x 20260512 | velox: Mg Al Si | app: Cu Al O Ta Ho Th | hit 1/3 | extra 5
1006 65000 x 20260603 | velox: Mg Al Si | app: Cu Al O Hf Ta Ho Cs | hit 1/3 | extra 6
1038 91000 x 20260603 | velox: Mg Al Si | app: Cu Al O Hf Ta Cs Ho | hit 1/3 | extra 6
1052 33000 x 20260605 | velox: Mg Al Si | app: Cu Al O Ta Ho V | hit 1/3 | extra 5
1122 130 kx 20260603 | velox: Mg Al Si | app: Cu Al O Ho Ta | hit 1/3 | extra 4
1129 23000 x 20260605 | velox: Mg Al Si | app: Cu Al O Ta Ho V | hit 1/3 | extra 5
1653 33000 x 20260423 | velox: O Al Si In Pt | app: In Cu Si O Ti Rb V Ho Re | hit 3/5 | extra 6
1727 46000 x 20260422 | velox: B Al Si Ti Ni Zn | app: Cu Pt Si Ga O Ta Hf V Ba | hit 1/6 | extra 8
1742 23000 x 20260422 | velox: B Al Si Ti Ni Zn | app: Si Ti Ni Pt Zn O Rb Ba Hf | hit 4/6 | extra 5
1759 185 kx 20260422 | velox: O Al Si Ti Zn | app: Cu Si O Ga Zr V Ba Cs | hit 2/5 | extra 6
1804 23000 x 20260423 | velox: O Al Si Ti Ni Zn | app: Si K Pt O Zn V Fe | hit 3/6 | extra 4
1441 71000 x 20260420 | velox: O Si Ti Ni Ge In Sn | app: In Ge Ni Gd Ce O Zr Yb | hit 4/7 | extra 4
1456 77000 x 20260420 | velox: O Si Ti Ni Ge In Sn | app: Ge In Ni Gd Ce O Yb V | hit 4/7 | extra 4
1549 | velox: C O Ti Cu Pt | app: Ti Cu Zr O Pt Cs Nd | hit 4/5 | extra 3
1206 33000 x | velox: Mg Al Si | app: Cu Al Tb O Fe Ho | hit 1/3 | extra 5
1211 23000 x | velox: Mg Al Si | app: Cu Tb O Cl Al Ca Mg Ru Hf K As | hit 2/3 | extra 9
1425 16500 x | velox: Mg Al Si Ca Cu | app: Al Ca O Tb Ba Fe Sb V | hit 2/5 | extra 6
1138 | velox: C O Mg Al Si Ca Ti Fe Cu | app: Cu Si Hf | hit 2/9 | extra 1
1318 | velox: O Mg Al Ca Ti | app: Cu S Ca Cl Zr Si Ho Au K | hit 1/5 | extra 8
1432 | velox: O Mg Al Ca Ti | app: Cu Cl S Si Ho Zr Bi | hit 0/5 | extra 7
1436 | velox: O Mg Al Ca Ti | app: Cu Cl Si S Ho Zr | hit 0/5 | extra 6
1437 | velox: C O Mg Al Si P S Cl Ca Ti Cu | app: Cu Cl S Si Ho Zr Ca K | hit 5/11 | extra 3
1448 | velox: C O Na Mg Al Si S Cl K Ca Ti Fe Cu Zr Pb | app: Cu Si Mo Cl Ho Zr | hit 4/15 | extra 2
0912 | velox: C O Al Si Ti Fe Cu | app: Cu Si Fe Ho Hf Nb | hit 3/7 | extra 3
1024 | velox: C O Na Mg Al Si S Cl K Ca Ti Fe Cu Zr Pb | app: Cu Ca O Si P Hf Sb Ho | hit 4/15 | extra 4
1038 | velox: C O Al Si S Cl Ca Ti Fe Cu Zr Pb | app: Cu S Cl Si Zr Ca Ho | hit 6/12 | extra 1
1020 | velox: C O Si Ti Ni Cu Ge | app: Ni K O Ge Cu | hit 4/7 | extra 1
1100 | velox: C O Si Ti Ni Ge In Sn | app: Ge Gd K Cu Ni O Ce Zr | hit 3/8 | extra 5
1253 | velox: C O Si Ti Ni Ge In Sn | app: Cu Ga Ta Ge Eu In | hit 2/8 | extra 4
1020 | velox: C O Si Ti Ni Cu Ge | app: Ni K O Ge Cu | hit 4/7 | extra 1
1100 | velox: C O Si Ti Ni Ge In Sn | app: Ge Gd K Cu Ni O Ce Zr | hit 3/8 | extra 5
1253 | velox: C O Si Ti Ni Ge In Sn | app: Cu Ga Ta Ge Eu In | hit 2/8 | extra 4
1312 | velox: O Si Ti Ni Ge In Sn | app: Ge Gd Ce O K | hit 2/7 | extra 3
1633 | velox: O Ti Ni | app: Ti Cu K Si Ni Ca Zr Cl Fe S Pb | hit 2/3 | extra 9
1105 | velox: O Ti Ni Cu | app: Ti Ta Ni Ir O V Hf Nb | hit 3/4 | extra 5
1146 | velox: O Ti Ni Cu | app: Ti Ni P O Ta Si Hf V Th | hit 3/4 | extra 6
1248 | velox: O Si Ag In Sn Pt | app: Si Pt Ag Ga O In Dy Nd I Th Pd | hit 5/6 | extra 6
1304 | velox: O Si Cu Ag In Sn Pt | app: Si Pt Ag Ga In O I As Th Pd Ca | hit 5/7 | extra 6
1408 | velox: C O Si Cu Ag In Sn | app: Si Cu In Ag O Th Mo | hit 5/7 | extra 2
1221 | velox: C O Si Ag In Sn Pt | app: Ag Cu Pt In Ga Si Hf O Ta | hit 5/7 | extra 4
1225 | velox: C O Si Ag In Sn Pt | app: Ag Cu Si In Pt Ga Hf | hit 4/7 | extra 3
1420 | velox: C O Si Ag In Sn Pt | app: Si In Cu Ga Ag Hf | hit 3/7 | extra 3
1435 | velox: C O Si Ag In Sn | app: Ag Cu Si In Ga Hf Cd O | hit 4/6 | extra 4
1658 | velox: Mg Al Si Cu | app: Cu Al Si Zr Ho O | hit 3/4 | extra 3
1708 | velox: C O Mg Al Si Cu | app: Cu Si Al Zr Ho | hit 3/6 | extra 2
1721 | velox: Mg Al Si Cu | app: Cu Si O Ho Te Hf Eu | hit 2/4 | extra 5
1729 | velox: Mg Al Si Cu | app: Cu Zr Ho | hit 1/4 | extra 2
1755 | velox: C O Mg Al Si Cu | app: Cu Si Zr Al Ho Br | hit 3/6 | extra 3
1552 | velox: Mg Al Si | app: Cu Si Al O Ho Fe U Ba | hit 2/3 | extra 6
1618 | velox: O Mg Al Si Cu | app: Cu Al Si | hit 3/5 | extra 0
1637 | velox: O Mg Al Si Cu | app: Cu Al Si O Zr Er | hit 4/5 | extra 2
1151 | velox: C O Ca Cu As Kr Zr | app: Zr Cu Mo Si Hf Ho | hit 2/7 | extra 4
1315 | velox: C O Mg Zr | app: Cu Zr F Hf Mo Th Si Y Ho O | hit 2/4 | extra 8
1432 | velox: Au | app: Au Cu Zr | hit 1/1 | extra 2
1352 | velox: O Ni Cu | app: Ni Zr Si O | hit 2/3 | extra 2
1410 | velox: O Ni Cu | app: Ni Zr Si O Rh | hit 2/3 | extra 3
1555 | velox: O Si Ni Cu | app: Ni Si O Zr W Rh | hit 3/4 | extra 3
1016 | velox: N Al Si Ti Cu Nb Pt | app: Cu Si Zr Pt Ga S Ce | hit 3/7 | extra 4
1102 | velox: N Al Si Ti Cu Nb Pt | app: Ga V Sb U Bi Fe S Pr | hit 0/7 | extra 8
1016 | velox: N Al Si Ti Cu Nb Pt | app: Cu Si Zr Pt Ga S Ce | hit 3/7 | extra 4
1102 | velox: N Al Si Ti Cu Nb Pt | app: Ga V Sb U Bi Fe S Pr | hit 0/7 | extra 8
1029 | velox: Si | app: Cu Si O Rb V Hf Mo | hit 1/1 | extra 6
1330 | velox: B Si Ti Cu Nb | app: Nb Cu Ti U Si Zr Se Ba Ta | hit 4/5 | extra 5
1330 | velox: B Si Ti Cu Nb | app: Nb Cu Ti U Si Zr Se Ba Ta | hit 4/5 | extra 5
1029 | velox: Si | app: Cu Si O Rb V Hf Mo | hit 1/1 | extra 6
```
