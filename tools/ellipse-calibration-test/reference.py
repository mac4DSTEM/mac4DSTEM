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
}, fp=__import__("sys").stdout, separators=(",", ":"))
print()
