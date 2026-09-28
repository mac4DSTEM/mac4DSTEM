# 041 — The default disk-detection floor is 0.15 %, not py4DSTEM's 0.5 %

Dates: 2026-09-28

Status: live. The owner, after the first T4 scored run: "we could also just change the default to
0,15", then "do the default floor Gate D". This supersedes the floor sentence of ADR 026 and ADR 038.
It changes a default only: any value can still be set, and saved recipes and sidecars keep their own.

## Decision

`DiskDetectionParams.minRelativeIntensity` defaults to **0.0015**. It carries a `DEVIATION` note:
py4DSTEM's `find_Bragg_disks` defaults to 0.005 (`diskdetection.py:34`). A unit test pins the new
value, and harnesses that test the py4DSTEM port or a recorded baseline pass 0.005 explicitly.

## Evidence (`docs/archive/v4/default-floor-gateD-2026-09-28.md`, registered first in `d285243`)

- **Thronsen dataset A, under the adopted T4 bar:** 11.42 % per-position error at 0.5 %, with θ′
  face-on lost, against 1.31 % at 0.15 %.
- **The demo cube with its truth:** identical (100 % on every class), a weak check.
- **Real datasets:** disk counts rise, for example the bullseye calibration cube 24 → 52 over its
  three sample positions. There is no truth there.
- **Gates:** unit green, scientific 48/48.
- **The independent refuter** found no code gap. It found the missing pin test (added) and the
  missing ADR (this one).

## Not measured

Whether the extra peaks on real data are real disks: the owner's 306 hand-labelled centres
(2026-09-08) are no longer on disk. At 0.5 % the classical detector already missed 27–51 % of them
(`archive/v3/learned-detector-2026-09-06.md`). One dataset with truth set this default. That is an
exception to CLAUDE.md's threshold rule, taken knowingly at the owner's word, and to be revisited
when a second dataset with truth arrives.
