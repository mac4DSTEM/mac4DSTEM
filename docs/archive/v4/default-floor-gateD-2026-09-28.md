# The default disk-detection floor, 0.5 % → 0.15 % — Gate D, 2026-09-28

The owner, after the T4 scored run: "we could also just change the default to 0,15". The change is
one line: `DiskDetectionParams.minRelativeIntensity` 0.005 → 0.0015. It moves every analysis that
detects disks with the default, so it goes through Gate D. The board's recommendation was to
measure on every dataset it touches first (the threshold rule in CLAUDE.md).

## Diagnosis (registered before any code change)

On Thronsen dataset A, scored under the adopted T4 bar (`t4-first-scored-run-2026-09-28.md`), the
0.5 % default gives **11.42 %** per-position error: θ′ face-on vanishes after cleanup, and T1 loses
area (0.63). At 0.15 % the error is **1.31 %**, and every object metric but one is within the
published range. The mechanism: T1's and θ′'s weak reflections sit below 0.5 % of the reference peak.
They are the evidence the matcher needs (the 2026-09-21 finding: T1's reference dropped weak
reflections under a 5 % floor; the floor sweep 0.1 / 0.15 / 0.2 % gave 1.81 / 1.45 / 4.07 %).

**What 0.5 % is:** py4DSTEM's own default (`find_Bragg_disks`, `diskdetection.py:34`). The app
matched it for parity. **0.15 % is therefore a `DEVIATION`**, noted where the default is defined.

**What the floor touches:** every disk detection that starts from the default. That includes
Bragg maps, strain, ACOM, phase mapping and Q-from-crystal calibration, on every dataset.
- Saved work is unchanged: replayed recipes restore their recorded floor (`ReplayPlan.swift:756`),
  and sidecars carry theirs.
- The user can still set any value.

**Refuting observation:** if a dataset with truth came out worse at 0.15 % than at 0.5 %, the
default should not move on this evidence.

## What is measured, before and after (same build, only the default changes)

1. **Thronsen A (phase-map truth):** already measured at both floors with explicit flags
   (`t4-first-scored-run`): 11.42 % → 1.31 %.
2. **The demo cube (truth for phase mapping, ACOM grains and the strain stripe):**
   `tools/phase-map-probe --truth` uses the shipped defaults, so it is run before and after.
3. **Real-data acceptance** (`tools/real-data-acceptance`: disk counts, probe radius and virtual
   images on the checked-in real datasets, against golden values measured by the app at the old
   default). There is no truth there, only the size of the change: how many more disks per dataset.
4. **Not measurable here:** the frozen hand-labelled disk set (306 centres), whose label JSON is no
   longer on disk. The classical detector's recall/precision trade-off at the two floors is
   therefore unmeasured.
5. **The full gates:** unit, scientific (48), core, inventory.

## Predictions

- **P1 demo cube:** the phase map's confusion against truth is **no worse** at 0.15 %: the
  204 planted precipitate positions stay labelled, and no new false precipitate positions appear,
  or very few. The demo cube is synthetic with strong disks, so the floor matters little there.
- **P2 real data:** disk counts **rise** on every real dataset, most on the ones with a dominant
  central beam (for example 20–100 % more peaks). The probe radius and the virtual images are
  unchanged, because they do not depend on the floor. `expected.json`'s disk counts are re-pinned
  deliberately, with the old and new values recorded.
- **P3 gates:** any harness or unit test that uses the default and compares with py4DSTEM's 0.005
  will fail. Those checks test the port, not the product default, so they must pass 0.005
  explicitly; each one is named. Anything else failing refutes "only the floor moved".
- **Decision rule:** the default moves if P1 is not worse. P2 is recorded, not judged, since there
  is no truth.

## Outcome, same day (every log exits 0 on its own line unless stated)

- **P1 held: the demo cube is not worse** (`demo-before.log`, `demo-after.log`, the probe in truth mode with the
  shipped defaults). The confusion is identical: every truth class is labelled 100 %, with 0 false
  precipitate positions. Peaks rose from 90 747 to **93 635** (+3.2 %, per-pattern maximum 50 → 70), which proves
  the new default was in force. The demo's disks are strong and synthetic, so this check is weak.
- **P2 held: disk counts rise on every pinned real dataset** (`rda-before.log`; `rda-after.log` fails as
  expected; `rda-report-after.json`). Peak counts summed over the three sample positions:

  | dataset | before | after |
  |---|---|---|
  | Particle_1 | 22 | 23 |
  | sim_Au | 25 | 31 |
  | WS₂ | 3 | 6 |
  | Si-SiGe | 36 | 61 |
  | bullseye calibration | 24 | 52 |

  The probe radius is unchanged. `expected.json`'s three disk arrays are re-pinned for the five datasets (old
  file in `expected.before.json`), and the harness then passes (`rda-after-repinned.log`). There is no truth
  on these datasets, so whether the extra peaks are real disks is **unmeasured**.
- **P3 held:** the unit gate is 908 / 0 / 1 (`unit-floor.log`). The scientific gate failed only
  `disk-correlation-parity` (`scientific-floor.log`). That harness pins the CPU correlation baseline
  recorded at 0.005 for backend identity, not a product default, so it now passes 0.005 explicitly. It
  then passes, and the gate is **48/48** (`scientific-floor2.log`).
- **Decision rule met:** the default moves to 0.15 %, with a `DEVIATION` note naming py4DSTEM's 0.005.

## Independent refuter (Sonnet), same day

**The change holds. Four gaps were found and closed.**
- **Code: no gap.** Every consumer reaches the default through one seam
  (`DiskDetectionProduct.diskParams` / `detectorAdapted`). A replayed recipe *requires* its recorded
  floor (`ReplayPlan.swift`, refused without it), and no UI text claims 0.5 %.
- **No test pinned the default.** The struct's only initialiser carries the effective default; the
  property's own `= …` is never consulted. Reverting the init default to 0.005 left all 908 tests
  green. `testShippedDefaultMinRelativeIntensityIsThePinnedFloor` is now added: green on the fix,
  red on that revert (`refuter-pin-green.log`, `refuter-pin-red.log`).
- **Docs:** no ADR existed (now ADR 041), and ADRs 026 and 038 still stated 0.5 % (now marked
  superseded). Two test comments called 0.5 % "the shipped" threshold (reworded).
- **The owner's 306 hand labels are not recoverable.** `net-labels.npz` holds the network's own
  predicted heatmaps at the 40 labelled positions, not the labels. Peak-finding on it gives 253–1 755
  "centres" depending on the threshold. The label JSON exists nowhere on disk. **Whether the new
  floor's extra peaks are real disks cannot be measured today.** At 0.5 % the classical detector
  already missed 27–51 % of those labels, which supports but does not prove it.
- **The over-claim is real and is stated:** the demo check is weak, and one dataset with truth set
  the default. ADR 041 says so.
