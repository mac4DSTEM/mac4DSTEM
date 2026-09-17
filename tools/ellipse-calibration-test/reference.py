#!/usr/bin/env python3
"""Source-lock py4DSTEM conic/profile conventions and emit synthetic rings."""
import json
import math
import pathlib

repo = pathlib.Path(__file__).resolve().parents[2]
ellipse_source = (repo / "References/py4DSTEM-dev/py4DSTEM/process/calibration/ellipse.py").read_text()
coordinate_source = (repo / "References/py4DSTEM-dev/py4DSTEM/process/utils/elliptical_coords.py").read_text()
profile_source = (repo / "References/py4DSTEM-dev/py4DSTEM/process/calibration/ellipse.py").read_text()
for source, contract in (
    (ellipse_source, "(p[2] * x**2 + p[3] * x * y + p[4] * y**2 - 1) * val"),
    (ellipse_source, "p0 = [x0, y0, (2 / (ri + ro)) ** 2, 0, (2 / (ri + ro)) ** 2]"),
    (coordinate_source, "A = sin2 / b2 + cos2 / a2"),
    (coordinate_source, "B = 2 * (b2 - a2) * np.sin(theta) * np.cos(theta) / (a2 * b2)"),
):
    if contract not in source:
        raise SystemExit(f"py4DSTEM ellipse contract changed; missing: {contract}")

for contract in (
    "I0, I1, sigma0, sigma1, sigma2, c_bkgd, x0, y0, A, B, C = p",
    "R = np.mean((a, b))",
    "A, B, C = A * R2, B * R2, C * R2",
    "I1 * np.exp(-(r**2) / (2 * sigma1**2)) * np.heaviside(-r, 0.5)",
    "I1 * np.exp(-(r**2) / (2 * sigma2**2)) * np.heaviside(r, 0.5)",
):
    if contract not in profile_source:
        raise SystemExit(f"py4DSTEM amorphous profile contract changed; missing: {contract}")


def ring(name, height, width, qx0, qy0, a, b, theta, sigma):
    sin2, cos2 = math.sin(theta) ** 2, math.cos(theta) ** 2
    A = sin2 / b**2 + cos2 / a**2
    C = cos2 / b**2 + sin2 / a**2
    B = 2 * (b**2 - a**2) * math.sin(theta) * math.cos(theta) / (a**2 * b**2)
    radius = (a + b) / 2
    values = []
    for qx in range(height):
        for qy in range(width):
            dx, dy = qx - qx0, qy - qy0
            elliptical_radius = math.sqrt(max(0, A * dx * dx + B * dx * dy + C * dy * dy))
            distance = (elliptical_radius - 1) * radius
            value = math.exp(-(distance * distance) / (2 * sigma * sigma))
            values.append(value if value >= 1e-30 else 0.0)
    return {
        "name": name, "height": height, "width": width,
        "centerQX": qx0, "centerQY": qy0,
        "a": a, "b": b, "theta": theta,
        "innerRadius": min(a, b) - 5,
        "outerRadius": max(a, b) + 5,
        "pixels": values,
    }


def profile_value(qx, qy, p):
    qx0, qy0, a, b, theta, i0, i1, sigma0, sigma1, sigma2, background = p
    sin_t, cos_t = math.sin(theta), math.cos(theta)
    a2, b2 = a * a, b * b
    A = sin_t**2 / b2 + cos_t**2 / a2
    C = cos_t**2 / b2 + sin_t**2 / a2
    B = 2 * (b2 - a2) * sin_t * cos_t / (a2 * b2)
    radius = (a + b) / 2
    radius2 = radius * radius
    dx, dy = qx - qx0, qy - qy0
    r2 = max(0, radius2 * (A * dx * dx + B * dx * dy + C * dy * dy))
    dr = math.sqrt(r2) - radius
    sigma = sigma1 if dr < 0 else sigma2
    return (
        i0 * math.exp(-r2 / (2 * sigma0 * sigma0))
        + i1 * math.exp(-(dr * dr) / (2 * sigma * sigma))
        + background
    )


def profile_case(name, height, width, params, inner, outer, noisy=False):
    pixels = []
    for qx in range(height):
        for qy in range(width):
            value = profile_value(qx, qy, params)
            if noisy:
                value += 0.025 * params[6] * math.sin(qx * 1.731 + qy * 0.917)
                if (qx * width + qy) % 293 == 17:
                    value += 0.45 * params[6]
            pixels.append(max(0, value))
    keys = ("centerQX", "centerQY", "a", "b", "theta", "centralIntensity",
            "ringIntensity", "centralSigma", "innerSigma", "outerSigma", "background")
    return {
        "name": name, "height": height, "width": width,
        **dict(zip(keys, params)),
        "innerRadius": inner, "outerRadius": outer, "pixels": pixels,
    }


profile_one = (36.2, 57.4, 24.0, 17.5, 0.43, 7.0, 13.0, 8.0, 1.2, 2.7, 1.4)
profile_two = (31.5, 45.25, 20.5, 15.2, 1.03, 5.0, 11.0, 7.0, 1.6, 3.1, 0.8)
overlap = (34.0, 51.0, 22.0, 17.0, 0.62, 4.0, 12.0, 7.5, 1.5, 2.4, 1.0)
overlap_case = profile_case("overlapping_ring_fallback", 72, 104, overlap, 12, 31)
for qx in range(overlap_case["height"]):
    for qy in range(overlap_case["width"]):
        index = qx * overlap_case["width"] + qy
        second = list(overlap)
        second[2] *= 1.13
        second[3] *= 1.13
        second[6] *= 0.35
        second[5] = 0
        second[10] = 0
        overlap_case["pixels"][index] += profile_value(qx, qy, second)


def spot_pattern(name, height, width, qx0, qy0, rings, inner, outer,
                 sigma=2.2, halo=None, background=0.0, expect="fit", why="",
                 expectAnyway="fit", whyAnyway="", ellipse=None):
    """A pattern built from DISCRETE Bragg disks, optionally on an amorphous halo.

    `rings` is a list of (radius_px, start_deg, count) — each entry places
    `count` spots evenly around the circle from `start_deg`, and every spot is
    paired with its -g partner, so the pattern carries the 2-fold symmetry a
    real one does. Each ring is CIRCULAR unless `ellipse` is given: there is
    no detector distortion in any of these by construction, so any ellipse a
    fit reports here is a statement about the arrangement of the diffracting
    grains.

    `ellipse`, when given, is (a_over_b, theta): each ring's spots are placed
    on an actual elliptical ring — b = radius, a = radius * a_over_b — using
    the same (a,b,theta) conic convention `ring()`/`profile_value()` use, so
    this is a LEGITIMATE detector distortion, not a grain artefact.

    `halo` is (radius_px, sigma_px, intensity) for a continuous amorphous ring
    underneath — the legitimate nanocrystalline case, where the ellipse fit is
    exactly right and must NOT be refused.

    `expect`/`why` are the default-path (`acceptSparseCoverage: false`)
    expectation; `expectAnyway`/`whyAnyway` are for the anyway path.
    """
    a_over_b, theta = ellipse if ellipse is not None else (1.0, 0.0)
    sin_t, cos_t = math.sin(theta), math.cos(theta)
    spots = []
    for radius, start_deg, count in rings:
        b = radius
        a = radius * a_over_b
        for index in range(count):
            phi = math.radians(start_deg + index * 360.0 / count)
            # (u,v) on the ellipse in its own frame, then rotated by theta —
            # exactly the inverse of the (A,B,C) conic `ring()` builds.
            u, v = a * math.cos(phi), b * math.sin(phi)
            sx = u * cos_t - v * sin_t
            sy = u * sin_t + v * cos_t
            spots.append((sx, sy))
            spots.append((-sx, -sy))
    values = []
    for qx in range(height):
        for qy in range(width):
            dx, dy = qx - qx0, qy - qy0
            total = background
            if halo is not None:
                hr, hs, hi = halo
                dr = math.hypot(dx, dy) - hr
                total += hi * math.exp(-(dr * dr) / (2 * hs * hs))
            for sx, sy in spots:
                d2 = (dx - sx) ** 2 + (dy - sy) ** 2
                if d2 < 36 * sigma * sigma:
                    total += math.exp(-d2 / (2 * sigma * sigma))
            values.append(total)
    first_radius = rings[0][0] if rings else 0.0
    return {
        "name": name, "height": height, "width": width,
        "centerQX": qx0, "centerQY": qy0,
        "innerRadius": inner, "outerRadius": outer,
        "expect": expect, "why": why,
        "expectAnyway": expectAnyway, "whyAnyway": whyAnyway,
        "a": first_radius * a_over_b, "b": first_radius, "theta": theta,
        "pixels": values,
    }


# The demo cube's own radii in detector pixels (Al {200} at 41.2 px and {220}
# at 58.2 px on a 0.012 A^-1 pixel). Grain counts 3 -> 18: Gate B measured the
# azimuthal-contrast guard firing at 3 and going silent by 6, so the sweep is
# the fixture, not one case.
def grains_at(n):
    rings = []
    for index in range(n):
        radius = [41.2, 58.2, 36.6][index % 3]
        rings.append((radius, 12.0 + index * 180.0 / n, 2))
    return rings


spot_cases = [
    # THE DEFECT: three grains at three radii in one annulus, on a detector
    # with no distortion in it. One ellipse threads through them and reports
    # a/b = 1.685. It must be refused — anyway or not: three radii are more
    # than one ring apart, which is exactly what the anyway path's one-ring
    # check exists to catch.
    spot_pattern("grains_3_one_annulus", 128, 128, 63.5, 63.5, grains_at(3), 30, 70,
                 expect="refuse", why="3 radii, 12 of 36 bins: the fit reports a/b 1.685",
                 expectAnyway="refuse",
                 whyAnyway="three radii (36.6/41.2/58.2 px), more than one ring apart"),
    # Degenerate but LUCKY: the answer it would give is right, and it is still
    # refused, because nothing in the data says which it is. The cost is
    # recorded here rather than discovered later. Anyway is no rescue either:
    # it is the same three radii as above, just repeated.
    spot_pattern("grains_6_one_annulus", 128, 128, 63.5, 63.5, grains_at(6), 30, 70,
                 expect="refuse", why="24 of 36 bins; a/b would be 1.000, but undecidable",
                 expectAnyway="refuse", whyAnyway="same three radii, repeated"),
    # Enough azimuths to decide: it fits, and the answer must be isotropic.
    # Anyway changes nothing here — 36 of 36 bins makes the flag inert.
    spot_pattern("grains_12_one_annulus", 128, 128, 63.5, 63.5, grains_at(12), 30, 70,
                 expect="fit", why="36 of 36 bins",
                 expectAnyway="fit", whyAnyway="36 of 36 bins: flag inert"),
    # LEGITIMATE, and the two cases every previous attempt lacked. A coarse
    # polycrystal's Debye-Scherrer ring is spots at ONE |g|, and py4DSTEM's own
    # fit_ellipse_1D is documented for "a Bragg vector map"; a nanocrystalline
    # halo carrying sharp reflections is the intermediate case. The fit is
    # right on both and must not be refused.
    # LEGITIMATE and the case every earlier attempt lacked: a coarse
    # polycrystal's Debye-Scherrer ring is spots at ONE |g|, and py4DSTEM's own
    # fit_ellipse_1D is documented for "a Bragg vector map".
    spot_pattern("spotty_single_ring", 128, 128, 63.5, 63.5,
                 [(41.2, 7.0, 9)], 30, 52, expect="fit", why="one radius, full coverage",
                 expectAnyway="fit", whyAnyway="full coverage: flag inert"),
    # The nanocrystalline case at four spot-to-halo ratios. This is the one
    # Gate B says a refusal must not take: the halo is continuous, its radius
    # is the detector's answer, and the fit gets it right. The ratio decides
    # whether the halo survives the strong-sample threshold at all.
    # A halo 50x fainter than the spots on it never reaches the strong-sample
    # threshold, so only the spots are seen and the fit is refused on 8 bins —
    # that is SHIPPED behaviour, unchanged by the bound above, and it is here
    # so a reader does not attribute it to the bound. Anyway does not rescue
    # it either: 8 bins is below the restored hard floor of 12.
    spot_pattern("halo_spots_50to1", 128, 128, 63.5, 63.5,
                 [(41.2, 7.0, 4)], 30, 52, halo=(41.2, 3.0, 0.02), background=0.001,
                 expect="refuse", why="halo below the strong-sample threshold: 8 bins",
                 expectAnyway="refuse",
                 whyAnyway="8 bins is below the hard floor of 12 even anyway"),
    # Bring the halo within a factor of two of the spots and it is a ring
    # again: full coverage, and the fit must find the detector isotropic.
    spot_pattern("halo_spots_2to1", 128, 128, 63.5, 63.5,
                 [(41.2, 7.0, 4)], 30, 52, halo=(41.2, 3.0, 0.50), background=0.001,
                 expect="fit", why="continuous halo, 36 bins",
                 expectAnyway="fit", whyAnyway="continuous halo, 36 bins: flag inert"),
    # THE COST, stated: a legitimate single-radius ring at six azimuths is
    # refused by default, because it is the same measurement as
    # grains_3_one_annulus and nothing in it says which. THE ANYWAY PATH is
    # exactly for this case: the caller asserts "one ring", the fit proceeds,
    # and it is MARKED sparseCoverage rather than trusted silently.
    spot_pattern("spotty_ring_6_azimuths", 128, 128, 63.5, 63.5,
                 [(41.2, 7.0, 6)], 30, 52,
                 expect="refuse", why="legitimate, but 12 bins cannot decide five parameters",
                 expectAnyway="fit",
                 whyAnyway="one radius, 12 bins: fits anyway, marked sparse"),
    # THE ANYWAY PATH ON A REAL DISTORTED DETECTOR. Same six-azimuth sparsity
    # as spotty_ring_6_azimuths, but this time the ring truly is an ellipse
    # (6% ellipticity — inside the 1.10 one-ring bound and the caller's to
    # answer for). Proves the anyway path measures the DETECTOR when the
    # caller is right, not just that it declines to measure the grains.
    spot_pattern("sparse_ring_6_azimuths_elliptic", 128, 128, 63.5, 63.5,
                 [(41.2, 7.0, 6)], 30, 52, ellipse=(1.06, 0.42),
                 expect="refuse", why="legitimate, but 12 bins cannot decide five parameters",
                 expectAnyway="fit",
                 whyAnyway="one real ring, 6% ellipticity: inside the 1.10 bound"),
    # THE BLIND SPOT, found by Gate B 2026-09-15 and recorded rather than
    # hidden: two rings 25% apart at the SAME six azimuths. The one-ring check
    # reads between sectors, and here every occupied sector holds both radii,
    # so the per-sector means blend to ~48.5 px and the fit is accepted,
    # marked, isotropic — and at a radius that is neither ring's. No cheap
    # statistic separates this from one ring of large disks (a disk's radial
    # width is a similar fraction of its radius). It is the price of the
    # click: the caller asserted one ring, and the annulus held two.
    spot_pattern("overlap_bins_2radii", 128, 128, 63.5, 63.5,
                 [(40.0, 7.0, 6), (50.0, 7.0, 6)], 30, 60,
                 expect="refuse", why="12 bins cannot decide five parameters",
                 expectAnyway="fit",
                 whyAnyway="ACCEPTED AND WRONG: two radii in every sector blend past the check"),
]

json.dump({
    "cases": [
        ring("non_square_rotated", 72, 110, 34.5, 58.25, 24, 17, 0.42, 1.1),
        ring("near_circular", 64, 88, 31.25, 43.5, 19, 18.2, 1.1, 0.9),
    ],
    "profileCases": [
        profile_case("asymmetric_background", 76, 112, profile_one, 12, 31),
        profile_case("noisy_asymmetric", 68, 94, profile_two, 10, 28, noisy=True),
    ],
    "overlapCase": overlap_case,
    "spotCases": spot_cases,
}, fp=__import__("sys").stdout, separators=(",", ":"))
print()
