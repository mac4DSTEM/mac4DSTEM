# 019 — Precipitates: density by classifying patterns; template-matched and material-general; ship only if the baseline is beaten

Dates: 2026-09-11

Status: live

## Decision

Precipitate density is measured by classifying diffraction patterns, not by
segmenting a virtual image — superseding the plan's original "per-object,
real-space segmentation". Class identification is template-matched against
an imported CIF's predicted diffraction, and material-general (never a
hardcoded Al-Mg-Si assumption); clustering is the fallback for what
templates do not explain. Precipitates ship only if a pre-registered
baseline (threshold plus connected components, ridge filter disabled) is
built and beaten on both the synthetic fixture and an owner-adjudicated hand
count, a tie passing — or they do not ship and the classification/image
route in front of them stands as unscored.

## Why

The image route collapses each diffraction pattern (4096 numbers) to one
aperture-sum number before any decision is made; three measured failures
this session were all downstream of that one choice (a shape filter losing
end-on needles 2.1x low; the ridge filter's own baseline coming out a tie;
no upstream counterpart, so no parity harness is possible). The
classification route can have a py4DSTEM parity harness
(`Featurization`/`BraggVectorClassification` already exist upstream) and the
image route provably cannot. Unsupervised k-means labels are slop without a
template — the user has to identify each class by hand anyway.

## Governs

`mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift`,
`docs/v3-precipitate-classification.md`'s ship gate.

## Sources

- 2026-09-11 "precipitates ship only if the pre-registered baseline is built and beaten", log line 921
- 2026-09-11 "precipitate density is measured by CLASSIFYING diffraction patterns", log line 994
- 2026-09-11 "class identification is TEMPLATE-MATCHED and MATERIAL-GENERAL", log line 1102
