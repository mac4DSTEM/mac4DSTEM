# A2 — scoring both detectors on the re-labelled bullseye set (2026-09-28)

Measurement only; no app code changed, no default moved. Labels: `tools/disk-detector/labels/bullseye-2026-09-28.json`
(sha `d69f2aa0…`, 40 seed-1 positions, 370 centres incl. the central beam; Claude by eye, owner-approved).
Net heatmaps: the 2026-09-08 run's cached `net-labels.npz` (its Core AI `heatmap-b32` export of the shipped weights),
at exactly these 40 positions (checked). Classical: py4DSTEM `find_Bragg_disks` at `evaluate.py`'s `SETTINGS`
(minPeakSpacing 8, edgeBoundary 6, maxNumPeaks 70) — **not** the app's defaults (60 / 20 / 70).
`tools/disk-detector/evaluate.py --stage compare … --labels … --threshold T --min-relative F` (new flag, this commit).
Logs `compare-t07-mr05.log`, `-t07-mr005`, `-t07-mr0015`, `-t09-mr0015`, `compare-tol3.log` (session scratchpad).

| Match | Net 0.7 | Net 0.9 | Classical 0.05 | Classical 0.005 / 0.0015 |
|---|---|---|---|---|
| 2 px | 0.584 / 0.655 (216 of 370; 330 predicted) | 0.497 / 0.757 | 0.362 / 0.436 | 0.611 / 0.081 (2 800 predicted) |
| 3 px | 0.708 / 0.794 | — | 0.416 / 0.502 | — |

Recall / precision. The C6 set (306 centres, lost) gave the net 0.768 / 0.712 and classical 0.487 / 0.485 at 2 px.

**What this does and does not say.**
- Not comparable with C6: a different labeller and 64 more centres (the central beam at 40 positions, fainter disks).
- **Label precision is a confound.** Net–label pairs within 5 px: 301, mean offset (−0.15, −0.27) px (no convention
  shift), median 1.22 px, 72 % within 2 px, 87 % within 3 px. Whether the scatter is in the labels (centroid on
  faint rings) or in the net's refinement is not established; moving the 2 px bar after seeing this is not allowed.
- At 0.005 and 0.0015 the classical path returns 70 peaks at every position (the cap binds), so the two floors
  cannot be told apart here and ADR 041's floor is still unscored on these settings. The app's own spacing/edge
  defaults would give different counts.

**Next:** measure label precision independently (the owner clicks a few positions in `label_centres.py`; the
inter-labeller spread says which side the scatter is on), then score the classical path at the app's own settings.
