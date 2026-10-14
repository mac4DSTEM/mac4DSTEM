# Lane B design note: P2 band for beta'' (C2/m) round trip (written 2026-10-14, before any candidate code or run)

Registration: docs/archive/v5/beta-double-prime-orientation-registration-2026-10-14.md (4ff4ab51), P2 asks for the step and fraction to be set here.

## Library at the app's default
- Default quality = Balanced = 200 templates (ACOMQualityPreset.balanced; ACOMSession.quality default). Fast 96, Best 400 are not the default.
- The 2/m beam-direction zone (b unique = Cartesian +y in py4DSTEM's frame; polar angle from b in [0,90 deg], azimuth period 180 deg) is a quarter sphere: area = 4*pi/4 = pi sr.
- N = 200 points, approximately hexagonally packed by the farthest-point sampler: nearest-neighbour spacing d = sqrt(2A/(sqrt(3) N)) = sqrt(2*pi/(1.7321*200)) = 0.1347 rad = **7.7 deg**. (Covering radius d/sqrt(3) = 4.5 deg: the worst beam-axis offset to the nearest template.)
- In-plane resolution: nAzimuthal = 128 bins = 2.8 deg per bin, so +-1.4 deg quantisation.

## Band (fixed now)
- Step = **7.7 deg** (the library's spacing at 200 templates). Pass if the disorientation (min over {E, C2_b}) between recovered and true orientation is <= 7.7 deg.
- Fraction: **>= 95 %** of draws (as registered), >= 500 seeds, random directions over the full sphere and random in-plane angles, 200 kV (lambda 0.02508 A), kMax 1.2, scale 0.008 A^-1/px.
- Why the step and not the covering radius: the disorientation combines the axis offset (<= 4.5 deg for a perfectly packed library, larger where the farthest-point sampler leaves gaps) with the in-plane quantisation and its coupling to the axis offset; d is the registered single number that bounds both with margin, and the 5 % allowance is for the gaps.
- Reported beside it, not gated: median, p90, max of the disorientation, and the same count at 4.5 deg.
- Not claimed: that this step is adequate for a 15.16 A cell (cannot be validated; registration "Cannot be validated"). Preset Fast (96 templates) has step 11.1 deg and is not the band.

## Colour key (2/m IPF, chosen by design)
Hexagonal pattern reused: polar angle from b maps to tilt (red at [010], b), azimuth maps to the green/blue mix, square-root intensity, max-normalised. Azimuth is periodic with period 180 deg here (no mirror fold of the azimuth within 2/m), so fraction = (1 - cos 2 phi)/2: [100]-direction (azimuth 0 = +x = a) green, [001]-ish (azimuth 90 deg, +z in the frame) blue, and azimuth 180 deg returns to green with no seam.
