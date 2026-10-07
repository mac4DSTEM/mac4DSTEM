# WP4 — Auto ID rules, built as registered and measured (lane L12, 2026-10-07)

**Independent refuter (Opus, read-only, 2026-10-07 16:05) — LAND WITH CORRECTIONS, applied by the supervisor:**
- **H1 is "not refuted; untested on its risk"**, not "holds": every one of the 31 true L/M picks in the sample has another element's Kα
  within 1,5 FWHM, and in every case that Kα happened to sit below L_D, so the test never met a true L/M element beside a PROPOSED K; the
  ladder is vacuous for R1 (its picks equal the baseline in all 8 regions). The beside-K half can drop a real element: the proposer keeps one
  group per element (no K fallback), and the line table holds Hf Lα 1,0 FWHM from Cu Kα (HfO₂ on a Cu grid), Pt Lα 1,2 from Ga Kα (every
  FIB lamella: file 1727 drops Pt at 12,5 L_D beside Ga at 6,6), Ta Lα 0,65 from Cu Kα, Pb Lα 0,04 from As Kα, Ag Lα 0,27 from Ar Kα.
  **Shipped: the Z ≥ 89 half only** (`ProposalRules.shipped.besideK = false`); the beside-K half waits for a registration on a set that
  holds a true L/M element beside a proposed K, with an evidence guard (drop only when the L/M net / L_D is at or below the K's).
- **H2 is "closed by its gate, untestable on this hold-out"**, not "refuted": the hold-out is 9 June files of one alloy (baseline 21 %),
  and R2 loses no hit there while lifting precision 21,1 → 38,7 % (more than on the fit set); the 45 % bar was an absolute number set
  against a 34 % baseline, which breaks the registration's own threshold rule. A new registration needs an independent set.
- **H3 confirmed**: 2 × Al Kα = 2,973 keV against Ar Kα 2,958; the Ar release is the pile-up.
- **H4 carries a selection bias**: pixels chosen by their Mg Kα window counts are then tested on the same counts, so "10 of 19" supports no
  mechanism without a control (a line-free window, or selection on an independent signal). Kept out of every claim.
- The replay is a valid measurement of the rules (`apply` is pure in the fields the replay restores; 88/88 and 39/39 equal) and hides four
  things named in the refuter's note: a listed Cu is never a candidate, suspect labels are not checked, the controller wiring was untested
  (a test added), 43 of the fit-set dates rest on copy dates. Swift and `analyse.py` agree (362 vs 363 is U Lα in file 1330: the draft's
  line had no Z cut).

Registration: `wp4-autoid-velox-preregistration-2026-10-07.md` (H1-H4). Measurement tool and truth: `autoid-velox-check-2026-10-07.md`. Built from seam commit 77088f52
plus lane L12 (the lane copy is not a git repository; nothing is committed here). Gate D; the supervisor's independent refuter is still owed. **Lane's verdicts (corrected by the refuter above): H1 holds; H2 misses
its hold-out bar (precision); H3 is refuted on the dose ladder; H4 misses its prediction and is not below its refutation line.** What the room applies: R1's actinide half
(`ProposalRules.shipped`). The `unvalidated` badge stays.

## What was built (exactly as registered)
`Core/Spectroscopy/Proposer/ProposalRules.swift`: `ProposalRules.apply(_ result, resolutionMnKaEV:) -> RuledProposal`, a separate post-selection step; `ProposalRules.registered`
names the cuts: R1 Z >= 89 never, and an L/M pick within 1.5 FWHM of another PROPOSED candidate's K alpha dropped (a held sum-peak K candidate counts as proposed, as
`analyse.py` counted it); R2 an L/M pick needs net / L_D >= 3 (K keeps the L_D bar); R3 a held sum-peak candidate at net / L_D >= 10 is released and then meets R1 and R2.
`RuledProposal` keeps the raw `ProposalResult` beside the picks, what each rule withheld (with the number) and released. `AutoIDPresentation.outcome(..., rules:)` (default nil =
unchanged behaviour) uses the ruled picks, puts "Rule R2 (L/M corroboration): ..." / "Rule R3 (sum-peak release): ..." into the pick's reason (the Found row's hover), and names every
withheld pick in the notes ("Withheld by the rules: Ho Lα (R2, 1.9 × L_D < 3)") so nothing vanishes silently. Nothing is changed in a threshold: no registered number was touched.

## Data, splits, and what could not be done
- Folder run on the owner's files, 2026-10-07, `tools/autoid-velox-check/run.sh --h4 --out $OUT /Volumes/PL_SSD_2TB/NAS_Backup/01_projects` (started 15:06): **the external drive left the Mac
  after about 38 files** (`/Volumes/PL_SSD_2TB` no longer mounted at 15:29; every later file "Could not open ... as an HDF5 file"). The live run scored 37 files (36 distinct) and wrote their dates and H4.
- To measure the rules on all 78 distinct files the tool got `--replay <earlier out>`: it rebuilds each `ProposalResult` from the candidates lane L10's run recorded (same numbers, no proposer run)
  and re-selects with the CURRENT Swift rule code through `AutoIDPresentation.outcome`. Check: the replayed baseline picks equal the recorded picks in 88 of 88 files, and the live run of this lane equals the
  recorded run (picks, every candidate's net, every rule set's picks) in 39 of 39 joined files, so the proposer is unchanged. `wp4.py <replay out> <ladder out> --real <live out>` prints every table below.
- Split by acquisition date (the file's own `AcquisitionStartDatetime`; the file-name date agrees in every dated file): **fit set (<= 2026-05-31): 69 files, hold-out (June 2026): 9 files** (78 distinct). Of the fit set 26
  are dated by metadata; 43 could not be read for a date once the drive was gone and are counted in the fit set (their copy dates, listed before the drive left, are all <= 2026-05-13 and an acquisition cannot be
  later than its copy; the June files are exactly the nine with a June date in the name). **The registration's "about 50 / 28" is wrong: June holds 9 files, not 28, and all nine are Al-Mg-Si files (one alloy, one operator, one detector), so the hold-out is not an
  independent dataset.** Also reported, not registered: Al-Mg-Si (26 files: truth holds Mg, Al, Si and neither C nor O; 21 + 3 + 1 + 1 of the lists) against every other file (52).
- H4 ran on 19 of the 26 Al-Mg-Si files (the rest were after the drive left). H3 ran fully (the ladder is in the repo's References).
- Date and command of every number: 2026-10-07; the commands above and `run.sh --replay $SP/lane10/out --out <dir>` (lane L10's recorded run of 2026-10-07), `run.sh --ladder <dir from ladder_prep.py> --out <dir>`.

## Predicted beside measured (78 distinct files, the registration's set; Swift implementation)
| rule set | predicted picks | predicted precision / recall | measured picks | measured precision / recall |
|---|---|---|---|---|
| R1 | 465 | 39.6 % / 45.5 % | 465 | 39.6 % / 45.5 % |
| R1 + R2 | 363 | 49.6 % / 44.6 % | 362 | 49.7 % / 44.6 % |
| R1 + R2 + R3 | 402 | 51.5 % / 51.2 % | 402 | 51.5 % / 51.2 % |

(363 vs 362: the registration's 49.6 % line was the draft's "F+H", which has no Z cut; with it 362 / 49.7 %.) In sample, the rules do what the draft said.

## Per rule, on both sets
All 78 distinct files:
| rule set | picks | hits | precision | recall |
|---|---|---|---|---|
| baseline (the proposer's own picks) | 539 | 184 | 34.1 % | 45.5 % |
| R1 alone | 465 | 184 | 39.6 % | 45.5 % |
| R2 alone | 366 | 180 | 49.2 % | 44.6 % |
| R3 alone | 579 | 211 | 36.4 % | 52.2 % |
| R1 + R2 | 362 | 180 | 49.7 % | 44.6 % |
| R1 + R2 + R3 (registered) | 402 | 207 | 51.5 % | 51.2 % |

Fit set, 69 files:
| rule set | picks | hits | precision | recall |
|---|---|---|---|---|
| baseline (the proposer's own picks) | 482 | 172 | 35.7 % | 45.6 % |
| R1 alone | 417 | 172 | 41.2 % | 45.6 % |
| R2 alone | 335 | 168 | 50.1 % | 44.6 % |
| R3 alone | 519 | 199 | 38.3 % | 52.8 % |
| R1 + R2 | 331 | 168 | 50.8 % | 44.6 % |
| R1 + R2 + R3 (registered) | 368 | 195 | 53.0 % | 51.7 % |

Hold-out, 9 files (June 2026, all Al-Mg-Si):
| rule set | picks | hits | precision | recall |
|---|---|---|---|---|
| baseline (the proposer's own picks) | 57 | 12 | 21.1 % | 44.4 % |
| R1 alone | 48 | 12 | 25.0 % | 44.4 % |
| R2 alone | 31 | 12 | 38.7 % | 44.4 % |
| R3 alone | 60 | 12 | 20.0 % | 44.4 % |
| R1 + R2 | 31 | 12 | 38.7 % | 44.4 % |
| R1 + R2 + R3 (registered) | 34 | 12 | 35.3 % | 44.4 % |

Not registered. Al-Mg-Si files (26):
| rule set | picks | hits | precision | recall |
|---|---|---|---|---|
| baseline (the proposer's own picks) | 166 | 36 | 21.7 % | 42.9 % |
| R1 alone | 140 | 36 | 25.7 % | 42.9 % |
| R2 alone | 98 | 36 | 36.7 % | 42.9 % |
| R3 alone | 174 | 38 | 21.8 % | 45.2 % |
| R1 + R2 | 97 | 36 | 37.1 % | 42.9 % |
| R1 + R2 + R3 (registered) | 105 | 38 | 36.2 % | 45.2 % |

Every other file (52):
| rule set | picks | hits | precision | recall |
|---|---|---|---|---|
| baseline (the proposer's own picks) | 373 | 148 | 39.7 % | 46.2 % |
| R1 alone | 325 | 148 | 45.5 % | 46.2 % |
| R2 alone | 268 | 144 | 53.7 % | 45.0 % |
| R3 alone | 405 | 173 | 42.7 % | 54.1 % |
| R1 + R2 | 265 | 144 | 54.3 % | 45.0 % |
| R1 + R2 + R3 (registered) | 297 | 169 | 56.9 % | 52.8 % |

## The refuting observations
- **H1: not refuted.** No file loses a hit under R1 (0 of 78). Precision 34.1 -> 39.6 %, recall 45.5 % unchanged (hold-out 21.1 -> 25.0 %, recall 44.4 % unchanged). Ships.
- **H2: refuted by its precision arm.** R1 + R2 on the hold-out: precision 38.7 % (the bar was 45 %), recall 44.4 % (bar 43 %, met). On the fit set 50.8 % / 44.6 %. It removes no hold-out hit and
  raises hold-out precision 21.1 -> 38.7 %, but the registration says it does not hold, so it does not ship as a rule: net / L_D already stands beside every pick (ADR 058). The 45 % bar was set when the
  baseline precision was 34 %; on this hold-out the baseline is 21 %, which is a property of that alloy. Turning R2 on is a new registration against a bar stated for that baseline.
- **H3: refuted.** Dose ladder (`References/demo-edx/AlMgSi_edx_ladder.hspy`, planted elements Al Mg Si O Cu): region 6 (matrix A at 100 counts/px) releases **Ar K alpha at 19.9 × L_D, absent from truth**: it is the Al+Al pile-up peak
  (2.97 keV), the very case the hold exists for. Region 8 (the pure Mg5Si6 pool) releases Si, which is in truth. On the owner's files R3 released 40 elements, 27 in Velox's list and 13 not; on the hold-out 3 releases, no hit.
| region | counts/px | planted elements | proposer picks | R1+R2+R3 picks | released | released and absent from truth |
|---|---|---|---|---|---|---|
| 1 | 0.3 | Al Cu Mg O Si | Al | Al | none | none |
| 2 | 1 | Al Cu Mg O Si | Al | Al | none | none |
| 3 | 3 | Al Cu Mg O Si | Al | Al | none | none |
| 4 | 10 | Al Cu Mg O Si | Al | Al | none | none |
| 5 | 30 | Al Cu Mg O Si | Al Si O Br | Al Si O Br | none | none |
| 6 | 100 | Al Cu Mg O Si | Al Si Cu | Al Ar Si Cu | Ar | Ar |
| 7 | 300 | Al Cu Mg O Si | Si Br Cu Rh O | Si Br Cu O | none | none |
| 8 | None | Cu Mg O Si | Mg O | Si Mg O | Si | none |
- **H4: prediction missed, refutation line not crossed.** Mg found on the Mg-richest 1 % of pixels (the room's Mg K alpha windows, ties by pixel index; 10 486-41 943 pixels pooled): **10 of 19** files, against 0 of 19 on the whole map. Predicted >= 20 of 26: unreachable
  (at most 17 of 26 even if the 7 unreached files all found Mg); refuted would be < 10 of 26: not met (at least 10). The median Mg window net per pixel is 4.4 counts on the top 1 % against -1.75 over all pixels (the window nets sit on Al's tail). The diagnostic stays a diagnostic; no UI.

## What ships and what is owed
`ProposalRules.shipped` = R1 only; the supervisor wires `ProposalRules.shipped.apply(result, resolutionMnKaEV: settings.resolutionMnKaEV)` into `SpectroscopyRoomController.runAutoID` and passes it as `outcome(..., rules:)`.
Owed: the independent refuter (Gate D); the 7 Al-Mg-Si files and the 43 dates when the drive is back (`run.sh --h4 --out <dir> <folders>`, then `wp4.py <replay out> <ladder out> --real <dir>`); a new registration if R2 is to be tried against an
independent hold-out (the owner's next microscope session is the cleanest one). Not touched: C below 0.45 keV, the four `rankDeficient` files, the beta-line check.
