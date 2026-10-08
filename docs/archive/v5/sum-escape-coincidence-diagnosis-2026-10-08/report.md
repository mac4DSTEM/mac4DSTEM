# Lane N report: does an exact pile-up sum equal to a non-sum column make Auto ID fail? (diagnosis only)

Copy: /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/27415fc8-785a-4cd2-93b8-7a7bf28311ae/scratchpad/laneN/mac4DSTEM (base 3f6636cd, no Core edit, no commit).
Gate D: diagnosis step only. No fix, no registration, nothing landed.

## Verdict

1. The claim as stated (a sum column coinciding with an ACTIVE, NON-claiming ALPHA line makes the design singular) is NOT reproduced. Of the 13 census coincidences, 6 need a refused or excluded parent (Be, Ne, Tc) and cannot occur in the pool. The other 7 have multi-line target groups, so their columns are never identical. Planted cases in the window L_C < net < L_D scored, with the sum column present beside the candidate.
2. A different mechanism IS reproduced. A candidate's ESCAPE column (Si-escape copy of its lines) is a separate design column. If the candidate's alpha is the only line of its group above the Si K edge, that escape column is one Gaussian. If it sits at a pile-up energy of two detected parents, the design has two identical columns and the run throws `rankDeficient`, at every amplitude tried (0, 100, 300, 1000, 3000, 40000 counts). The sum is not blocked because `sumColumns` compares sums only with alpha energies, never with escape energies.
3. Reachability: only on spectra whose axis top lies between about 5.01 and 5.43 keV (V K-alpha 4.9522 inside the axis, V K-beta 5.4273 beyond it). The 5.01 lower bound is my calculation from the pool rule (alpha must lie FWHM/2 inside the axis, FWHM about 0.12 keV), not measured. Example: V K-alpha escape 3.2125 keV = Tb M-alpha 1.2326 + Ir M-alpha 1.9799, on a 1024-channel 5 eV axis (top 5.115 keV). On the default test axis (0 to 14.99 keV) it is not reachable. No other target among the 7 reachable coincidences becomes a single Gaussian on any axis top 2 to 20 keV or axis low 0 to 1 keV (scan in coinc3.py). The Ti K-alpha escape (2.7712 = Ne K-alpha + Y L-alpha) needs Ne, which is excluded from defaultPool, so it is not reachable with the default pool.

## Code facts (Core read, not edited)

- A candidate group column is the alpha line plus its weighted family lines in the axis range (EDSModel.swift:85-93, LinearDesign.swift:78-89). Escape copies are separate design columns (LinearDesign.swift:90-94, EDSModel.swift:85-92). So "identical to a sum column" needs a single-component group, or a single-component escape list with weight 1.
- Sum columns are one Gaussian with weight 1 at the sum energy, FWHM from the same law (ElementProposer.swift:288). Identity is therefore exact when a candidate's single component sits at exactly the sum energy (exact 4-decimal table sums).
- `claimed` (ElementProposer.swift:270-271) holds only current-group and claiming-pool ALPHA energies. A sum is blocked only if it lies within 0.06 keV of one of those. An escape energy is never checked.
- The settle design (ElementProposer.swift:301) and the forward single-candidate test (ElementProposer.swift:352, which adds the tested candidate's id to the claimers) both include sumColumns. The forward test is where a pruned candidate's own escape column meets the sum column.
- Rank failure: FitNullVariance.compute returns nil on a pseudoInverse failure (FitLinearAlgebra.swift:138, column-normalised QR diagonal ratio below 1e-10), and ElementProposer.swift:218 turns that into `rankDeficient`.

## The 13 census coincidences (census script run on this copy; coinc2.py for parent validity)

Parent validity uses defaultPool: pool elements minus H, He, Li, Be (refused) minus the defaultExcluded set (Tc, Pm, Po, At, Rn, Fr, Ra, Ac, Pa, Np, Pu, Am, Ne, Kr, Xe). "On 0-14.99 axis" uses the test axis (offset 0, scale 0.01, 1500 channels, beam 200, res 130 eV).

| # | Coincidence (sum = target) | Parents valid in defaultPool? | Target on 0-14.99 axis | Identical column possible? | Observed |
|---|---|---|---|---|---|
| 1 | Re M-alpha 1.8423 = Be+Si | no (Be refused) | 7 lines, 6 escapes | no | not run |
| 2 | Hg L-alpha 9.9890 = Be+Ge | no (Be) | 9 lines | no | not run |
| 3 | Sm M-alpha 1.0428 = Be+Nd | no (Be) | 5 lines | no | not run |
| 4 | Rb L-alpha 1.6941 = Ne+Ce | no (Ne excluded) | 6 lines | no | not run |
| 5 | Ba L-alpha 4.4663 = Zr+Tc | no (Tc excluded) | 9 lines | no | not run |
| 6 | Ti K-alpha escape 2.7712 = Ne+Y | no (Ne excluded) | Ka+Kb; single only if axis top in [4.55, 4.93) | only on that axis | not run |
| 7 | Hg M-alpha 2.1964 = Se+La | yes | 7 lines, 6 escapes | no | structure only |
| 8 | Te L-alpha 3.7693 = K+Ti | yes | 9 lines | no | structure only |
| 9 | I L-alpha 3.9377 = Pd+Eu | yes | 9 lines | no | structure only |
| 10 | Tb L-alpha 6.2728 = Sr+Ba | yes | 9 lines | no | Case A: scored (see below) |
| 11 | Lu L-alpha escape 5.9159 = Ti+Er | yes | 9 lines, 9 escapes | no | Case B: scored |
| 12 | Au L-alpha escape 7.9733 = Mg+Ho | yes | 9 lines, 9 escapes | no | Case C: scored |
| 13 | V K-alpha escape 3.2125 = Tb+Ir | yes | Ka+Kb: not identical | YES on axis top in about [5.01, 5.43) keV | Case D: THREW rankDeficient |

Case probes (throwaway test NonSumCoincidenceProbeTests, test-host stdout written to a file; every value below is from log probe-out.txt):

- Case A, Tb L-alpha (sum Sr+Ba). Tb net 5.7 at amp 0 (L_C 189, L_D 381, not proposed); net 106.9 at amp 100 and 306.6 at amp 300, both in the window. The settled fit held the Ba+Sr sum column at 6.2728 keV beside the Tb group column: SCORED, passes 2-3. At amp 1000 and above Tb is proposed and the Ba+Sr column is blocked (claiming): SCORED.
- Case B, Lu L-alpha escape (sum Ti+Er, 5.9159). Lu net 86.9 at amp 100 and 288.2 at amp 300 (window): the Er+Ti sum column (net 134.8 and 138.6) is present beside Lu: SCORED. Lu proposed at amp 1000 and above: SCORED. The sum is never listed as a sum-peak question for Lu (sumQ false), see side finding.
- Case C, Au L-alpha escape (sum Mg+Ho, 7.9733). Au pruned (net 69.9 and 270.9, below L_C 307) at amp 100 and 300; Ho+Mg sum present at net 0.0; SCORED. Au proposed at amp 1000 (net 983) with Ho+Mg present, SCORED.
- Case D, V K-alpha escape with the axis top at 5.115 keV (size 1024, scale 0.005). V_Ka group = [V_Ka] alone, escape = [V_Ka_esc at 3.2125]. Parents Tb_Ma and Ir_Ma at 40000 each. Result: THREW rankDeficient at amp 0, 100, 300, 1000, 3000 and 40000 (all six).
- Controls, same axis top 5.115 unless stated:
  - E1: no parents planted (no sum possible), V at 40000: SCORED, no sum columns.
  - E2: parents planted, V not in pool, V at 40000: SCORED, Ir+Tb sum at 3.2125 present (net 24.4).
  - E3: axis top 5.495 (V K-beta included, V group two lines), V at 40000: SCORED, Ir+Tb at 3.2125 present (net 65.1).
  - E3b: axis top 5.495, V at 0: SCORED.

Reading of D: the throw is independent of V's amplitude. At 40000 V is claiming, but the claimed list holds its alpha energy 4.9522, not the escape energy, so the sum is not blocked. At amp 0 V is pruned after pass 1, so the throw there comes from the forward single-candidate test (ElementProposer.swift:352), which adds the tested candidate's column with the same sums. The forward call site is inferred from code for amp 0 (not observed as a stack trace). The amp 40000 throw is likely from settle (line 301) by the same reasoning, also not observed directly.

## Side finding (not a failure, not registered)

The escape-to-sum ambiguity is not raised. In Case B and Case C, a strong candidate (Lu, Au) sits beside a sum column at the same energy, and the candidate's conflicts carry no sum-peak question (sumQ=false), because `LineConflicts.conflicts` also compares alpha energies only. The fit therefore shows a sum column and a candidate at one energy without the question the room asks for alpha coincidences.

Also seen, not investigated: Case C at amp 0 gives "no candidate" for Au (its net exactly 0), while Case B at amp 0 gives a Lu candidate with net 0.0. The cause is not established.

## Proposed registration (for the sheet; not written, no docs edited)

New item, not an amendment of the sum-dedup item (the registered exact-duplicate rule is sum-to-sum only, and this failure is sum-to-escape). Options for the owner:
- (a) Block a sum whose energy lies within tolerance of any candidate's escape column as well as its alpha, for claiming candidates. Effort low to medium. Risk: it changes which sums appear in short-axis fits (only for the coincidence energies), so a dated before/after run is needed.
- (b) Treat an escape-sum coincidence as a sum-peak question on that candidate (as for alpha coincidences), so the sum is kept and labelled, with the identical-column case merged by the registered dedup rule. Effort medium. Risk: adds a visible question on screen (a UI change: Gate D presentation, plus Drive first).
- Either option needs a regression test with the Case D planted spectrum (5.115 keV axis), which is reproduced here.

## Logs and files

- Final run: $LANE/filt-probe.log (xcodebuild, filtered -only-testing:mac4DSTEMTests/NonSumCoincidenceProbeTests, heavy slot 2, EXIT=0, "TEST SUCCEEDED", 5 test methods passed). Results: $LANE/probe-out.txt (29 NSPROBE lines). Earlier runs: $LANE/probe-out-run1.txt (cases A to C), $LANE/probe-out-run2.txt (adds Case D).
- Census and validity scripts: $LANE/coinc.py (first census listing), $LANE/coinc2.py (defaultPool validity, 130 eV, resolution scan 50-250 eV), $LANE/coinc3.py (axis-top and axis-low scan). Run with python3 -I <script> <copy root>.
- Probe test file (throwaway, untracked, not to be landed): $LANE/mac4DSTEM/mac4DSTEMTests/NonSumCoincidenceProbeTests.swift. Lane git status: only that file is untracked; no commit.

## Cleanup not done

A safety check refused an `rm -rf` on $LANE/tmp/* (the command was refused and not run). So $LANE/dd (about 800 MB, the probe DerivedData) and $LANE/tmp/ (the runner script run-probe.sh, plus small leftovers) remain. The supervisor should remove $LANE/dd when convenient. The lane's heavy slot was released (heavy.2 removed; heavy.1 belongs to another session).

## Needs verification

- (For the sheet, not a drive.) On a real spectrum with an axis top in [5.01, 5.43) keV and V plus Tb and Ir detected, the Auto ID run should fail with rankDeficient. Check the dataset's energy axis first; no app drive was done, and nothing was seen on screen.
- Whether the rankDeficient throw at amp 0 comes from the forward step or from settle is by code reading only. A stack trace or a counter in a scratch build would settle it.
