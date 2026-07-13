#!/usr/bin/env python3
"""Source-lock py4DSTEM's conic/ellipse convention and emit synthetic rings."""
import json
import math
import pathlib

repo = pathlib.Path(__file__).resolve().parents[2]
ellipse_source = (repo / "References/py4DSTEM-dev/py4DSTEM/process/calibration/ellipse.py").read_text()
coordinate_source = (repo / "References/py4DSTEM-dev/py4DSTEM/process/utils/elliptical_coords.py").read_text()
for source, contract in (
    (ellipse_source, "(p[2] * x**2 + p[3] * x * y + p[4] * y**2 - 1) * val"),
    (ellipse_source, "p0 = [x0, y0, (2 / (ri + ro)) ** 2, 0, (2 / (ri + ro)) ** 2]"),
    (coordinate_source, "A = sin2 / b2 + cos2 / a2"),
    (coordinate_source, "B = 2 * (b2 - a2) * np.sin(theta) * np.cos(theta) / (a2 * b2)"),
):
    if contract not in source:
        raise SystemExit(f"py4DSTEM ellipse contract changed; missing: {contract}")


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


json.dump({"cases": [
    ring("non_square_rotated", 72, 110, 34.5, 58.25, 24, 17, 0.42, 1.1),
    ring("near_circular", 64, 88, 31.25, 43.5, 19, 18.2, 1.1, 0.9),
]}, fp=__import__("sys").stdout, separators=(",", ":"))
print()
