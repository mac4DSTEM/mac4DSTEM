#!/usr/bin/env python3
"""Source-locked golden values for single-pattern Bragg-disk detection.

This intentionally uses only the Python standard library. It asserts the
operative formulas in the checked-in py4DSTEM 0.14.19 source, then evaluates
the correlation, smoothing, and localization routes directly. The small
radix-2 detector avoids mixing detector semantics with mac4DSTEM's separate
power-of-two padding deviation.
"""

import json
import math
import pathlib
import sys


REPO = pathlib.Path(__file__).resolve().parents[2]
PROBE_SOURCE = (
    REPO / "References/py4DSTEM-dev/py4DSTEM/braggvectors/probe.py"
).read_text(encoding="utf-8")
DETECTION_SOURCE = (
    REPO / "References/py4DSTEM-dev/py4DSTEM/braggvectors/diskdetection.py"
).read_text(encoding="utf-8")
MAXIMA_SOURCE = (
    REPO / "References/py4DSTEM-dev/py4DSTEM/preprocess/utils.py"
).read_text(encoding="utf-8")
CROSS_SOURCE = (
    REPO / "References/py4DSTEM-dev/py4DSTEM/process/utils/cross_correlate.py"
).read_text(encoding="utf-8")

SOURCE_CONTRACTS = (
    (PROBE_SOURCE, "probe = 1 / (1 + np.exp(4 * qr / width))"),
    (PROBE_SOURCE, "sigmoid = np.cos((np.pi / 2) * sigmoid) ** 2"),
    (PROBE_SOURCE, "probe_kernel / np.sum(probe_kernel) - sigmoid / np.sum(sigmoid)"),
    (CROSS_SOURCE, "m = np.fft.fft2(ar) * template_FT"),
    (CROSS_SOURCE, "cc = np.abs(m) ** (corrPower) * np.exp(1j * np.angle(m))"),
    (CROSS_SOURCE, "cc = np.maximum(np.real(np.fft.ifft2(cc)), 0)"),
    (DETECTION_SOURCE, "minSpacing=minPeakSpacing"),
    (MAXIMA_SOURCE, "(ar >= np.roll(ar, (-1, 0), axis=(0, 1)))"),
    (MAXIMA_SOURCE, "(ar > np.roll(ar, (1, 1), axis=(0, 1)))"),
    (MAXIMA_SOURCE, "< minSpacing**2"),
    (MAXIMA_SOURCE, "gaussian_filter(ar, sigma)"),
)
for source, line in SOURCE_CONTRACTS:
    if line not in source:
        raise SystemExit(f"py4DSTEM disk-detection contract changed; missing: {line}")


# App [Qy,Qx] == py4DSTEM [Q_Nx,Q_Ny]. Both dimensions are powers of two so
# production vDSP and py4DSTEM operate on the same circular-correlation grid.
ROWS, COLS = 32, 64
RADIUS = 3.0
WIDTH = 1.5
TRENCH_INNER, TRENCH_OUTER = RADIUS, 2 * RADIUS


def corner_radius(row, col):
    row = row if row < ROWS // 2 else row - ROWS
    col = col if col < COLS // 2 else col - COLS
    return math.hypot(row, col)


probe = []
trench = []
for row in range(ROWS):
    for col in range(COLS):
        radius = corner_radius(row, col)
        probe.append(1 / (1 + math.exp(4 * (radius - RADIUS) / WIDTH)))
        t = min(max((radius - TRENCH_INNER) / (TRENCH_OUTER - TRENCH_INNER), 0), 1)
        trench.append(math.cos(math.pi / 2 * t) ** 2)

probe_sum = sum(probe)
trench_sum = sum(trench)
kernel = [p / probe_sum - t / trench_sum for p, t in zip(probe, trench)]


# Five isolated logistic disks with deliberately different intensities. Two
# are six pixels apart, and one is inside a four-pixel edge boundary, making
# spacing and edge filtering independently visible.
DISKS = (
    (8.0, 12.0, 10.0),
    (8.0, 18.0, 8.0),
    (2.0, 57.0, 7.0),
    (22.0, 45.0, 5.0),
    (25.0, 25.0, 2.5),
)
pattern = []
for row in range(ROWS):
    for col in range(COLS):
        value = 0.25 + 0.001 * row + 0.0001 * col
        for center_row, center_col, amplitude in DISKS:
            radius = math.hypot(row - center_row, col - center_col)
            value += amplitude / (1 + math.exp(4 * (radius - RADIUS) / WIDTH))
        pattern.append(value)


def correlation():
    # ifft(fft(pattern) * conj(fft(kernel))) expressed directly as circular
    # cross-correlation. This is the corrPower=1 branch of py4DSTEM.
    result = [0.0] * (ROWS * COLS)
    for out_row in range(ROWS):
        for out_col in range(COLS):
            total = 0.0
            for row in range(ROWS):
                kernel_row = (row - out_row) % ROWS
                pattern_base = row * COLS
                kernel_base = kernel_row * COLS
                for col in range(COLS):
                    total += pattern[pattern_base + col] * kernel[
                        kernel_base + (col - out_col) % COLS
                    ]
            result[out_row * COLS + out_col] = total
    return result


raw_cc = correlation()
cc = [max(value, 0.0) for value in raw_cc]


def fft2(values):
    """Small dependency-free forward 2D DFT, separated by rows and columns."""
    col_twiddle = [
        [
            complex(
                math.cos(-2 * math.pi * frequency * sample / COLS),
                math.sin(-2 * math.pi * frequency * sample / COLS),
            )
            for sample in range(COLS)
        ]
        for frequency in range(COLS)
    ]
    row_twiddle = [
        [
            complex(
                math.cos(-2 * math.pi * frequency * sample / ROWS),
                math.sin(-2 * math.pi * frequency * sample / ROWS),
            )
            for sample in range(ROWS)
        ]
        for frequency in range(ROWS)
    ]
    horizontal = [[0j] * COLS for _ in range(ROWS)]
    for row in range(ROWS):
        source = values[row * COLS : (row + 1) * COLS]
        for frequency in range(COLS):
            horizontal[row][frequency] = sum(
                source[sample] * col_twiddle[frequency][sample]
                for sample in range(COLS)
            )

    result = [[0j] * COLS for _ in range(ROWS)]
    for frequency_row in range(ROWS):
        for frequency_col in range(COLS):
            result[frequency_row][frequency_col] = sum(
                horizontal[sample_row][frequency_col]
                * row_twiddle[frequency_row][sample_row]
                for sample_row in range(ROWS)
            )
    return result


image_corr = fft2(raw_cc)


def ifft2(values):
    """Small dependency-free inverse 2D DFT."""
    horizontal = [[0j] * COLS for _ in range(ROWS)]
    for row in range(ROWS):
        for col in range(COLS):
            horizontal[row][col] = sum(
                values[row][frequency]
                * complex(
                    math.cos(2 * math.pi * frequency * col / COLS),
                    math.sin(2 * math.pi * frequency * col / COLS),
                )
                for frequency in range(COLS)
            ) / COLS

    result = [0.0] * (ROWS * COLS)
    for row in range(ROWS):
        for col in range(COLS):
            result[row * COLS + col] = (
                sum(
                    horizontal[frequency][col]
                    * complex(
                        math.cos(2 * math.pi * frequency * row / ROWS),
                        math.sin(2 * math.pi * frequency * row / ROWS),
                    )
                    for frequency in range(ROWS)
                )
                / ROWS
            ).real
    return result


hybrid_spectrum = [
    [
        value * (abs(value) ** -0.5 if abs(value) > 0 else 0)
        for value in row
    ]
    for row in image_corr
]
hybrid_cc = [max(value, 0.0) for value in ifft2(hybrid_spectrum)]


def gaussian_filter_reflect(values, sigma):
    """SciPy gaussian_filter defaults: truncate=4 and mode='reflect'."""
    radius = int(4 * sigma + 0.5)
    taps = [
        math.exp(-(offset * offset) / (2 * sigma * sigma))
        for offset in range(-radius, radius + 1)
    ]
    total = sum(taps)
    taps = [value / total for value in taps]

    def reflect(index, count):
        while index < 0 or index >= count:
            index = -index - 1 if index < 0 else 2 * count - index - 1
        return index

    horizontal = [0.0] * len(values)
    offsets = range(-radius, radius + 1)
    for row in range(ROWS):
        for col in range(COLS):
            horizontal[row * COLS + col] = sum(
                values[row * COLS + reflect(col + offset, COLS)] * tap
                for offset, tap in zip(offsets, taps)
            )
    output = [0.0] * len(values)
    for row in range(ROWS):
        for col in range(COLS):
            output[row * COLS + col] = sum(
                horizontal[reflect(row + offset, ROWS) * COLS + col] * tap
                for offset, tap in zip(offsets, taps)
            )
    return output


def multicorr_refine(row_shift, col_shift, upsample_factor, spectrum):
    row_shift = round(row_shift * 2) / 2
    col_shift = round(col_shift * 2) / 2
    row_shift = round(row_shift * upsample_factor) / upsample_factor
    col_shift = round(col_shift * upsample_factor) / upsample_factor

    size = math.ceil(1.5 * upsample_factor)
    global_shift = math.trunc(math.ceil(upsample_factor * 1.5) / 2)
    center_row = global_shift - upsample_factor * row_shift
    center_col = global_shift - upsample_factor * col_shift

    col_kernel = [[0j] * size for _ in range(COLS)]
    for frequency_col in range(COLS):
        wrapped = frequency_col if frequency_col < COLS // 2 else frequency_col - COLS
        for out_col in range(size):
            angle = (
                -2
                * math.pi
                / (COLS * upsample_factor)
                * wrapped
                * (out_col - center_col)
            )
            col_kernel[frequency_col][out_col] = complex(math.cos(angle), math.sin(angle))

    intermediate = [[0j] * size for _ in range(ROWS)]
    for frequency_row in range(ROWS):
        for out_col in range(size):
            intermediate[frequency_row][out_col] = sum(
                spectrum[frequency_row][frequency_col].conjugate()
                * col_kernel[frequency_col][out_col]
                for frequency_col in range(COLS)
            )

    upsampled = [[0.0] * size for _ in range(size)]
    for out_row in range(size):
        for frequency_row in range(ROWS):
            wrapped = frequency_row if frequency_row < ROWS // 2 else frequency_row - ROWS
            angle = (
                -2
                * math.pi
                / (ROWS * upsample_factor)
                * (out_row - center_row)
                * wrapped
            )
            row_value = complex(math.cos(angle), math.sin(angle))
            for out_col in range(size):
                upsampled[out_row][out_col] += (
                    row_value * intermediate[frequency_row][out_col]
                ).real

    best_flat = max(
        range(size * size),
        key=lambda index: upsampled[index // size][index % size],
    )
    best_row, best_col = divmod(best_flat, size)
    delta_row = 0.0
    delta_col = 0.0
    if 0 < best_row < size - 1 and 0 < best_col < size - 1:
        center = upsampled[best_row][best_col]
        below = upsampled[best_row + 1][best_col]
        above = upsampled[best_row - 1][best_col]
        right = upsampled[best_row][best_col + 1]
        left = upsampled[best_row][best_col - 1]
        delta_row = (below - above) / (4 * center - 2 * below - 2 * above)
        delta_col = (right - left) / (4 * center - 2 * right - 2 * left)

    return (
        row_shift + (best_row - global_shift + delta_row) / upsample_factor,
        col_shift + (best_col - global_shift + delta_col) / upsample_factor,
    )


def find_peaks(params):
    correlation_image = cc if params["corrPower"] == 1 else hybrid_cc
    if params["sigmaCC"] > 0:
        correlation_image = gaussian_filter_reflect(
            correlation_image, params["sigmaCC"]
        )
    spectrum = image_corr if params["corrPower"] == 1 else hybrid_spectrum
    edge = max(1, params["edgeBoundary"])
    peaks = []
    for row in range(edge, ROWS - edge):
        for col in range(edge, COLS - edge):
            value = correlation_image[row * COLS + col]

            def at(dr, dc):
                return correlation_image[
                    ((row + dr) % ROWS) * COLS + (col + dc) % COLS
                ]

            if (
                value >= at(0, 1)
                and value > at(0, -1)
                and value >= at(1, 0)
                and value > at(-1, 0)
                and value >= at(1, 1)
                and value > at(1, -1)
                and value >= at(-1, 1)
                and value > at(-1, -1)
            ):
                peaks.append({"qx": row, "qy": col, "intensity": value})

    peaks.sort(key=lambda peak: peak["intensity"], reverse=True)
    minimum_absolute = params["minAbsoluteIntensity"]
    if minimum_absolute > 0:
        peaks = [peak for peak in peaks if peak["intensity"] >= minimum_absolute]

    minimum_relative = params["minRelativeIntensity"]
    relative_to = params["relativeToPeak"]
    if minimum_relative > 0 and len(peaks) > relative_to:
        reference = peaks[relative_to]["intensity"]
        peaks = [
            peak
            for peak in peaks
            if peak["intensity"] / reference >= minimum_relative
        ]

    minimum_spacing = params["minPeakSpacing"]
    if minimum_spacing > 0:
        kept = []
        for candidate in peaks:
            if all(
                (candidate["qx"] - peak["qx"]) ** 2
                + (candidate["qy"] - peak["qy"]) ** 2
                >= minimum_spacing**2
                for peak in kept
            ):
                kept.append(candidate)
        peaks = kept

    peaks = peaks[: params["maxNumPeaks"]]

    if params["subpixel"] in ("poly", "multicorr"):
        for peak in peaks:
            row = peak["qx"]
            col = peak["qy"]
            center = correlation_image[row * COLS + col]
            below = correlation_image[(row + 1) * COLS + col]
            above = correlation_image[(row - 1) * COLS + col]
            right = correlation_image[row * COLS + col + 1]
            left = correlation_image[row * COLS + col - 1]
            delta_row = (below - above) / (4 * center - 2 * below - 2 * above)
            delta_col = (right - left) / (4 * center - 2 * right - 2 * left)
            peak["qx"] += delta_row
            peak["qy"] += delta_col

            row0 = math.floor(peak["qx"])
            row1 = math.ceil(peak["qx"])
            col0 = math.floor(peak["qy"])
            col1 = math.ceil(peak["qy"])
            dr = peak["qx"] - row0
            dc = peak["qy"] - col0
            peak["intensity"] = (
                (1 - dr) * (1 - dc) * correlation_image[row0 * COLS + col0]
                + (1 - dr) * dc * correlation_image[row0 * COLS + col1]
                + dr * (1 - dc) * correlation_image[row1 * COLS + col0]
                + dr * dc * correlation_image[row1 * COLS + col1]
            )

    if params["subpixel"] == "multicorr":
        for peak in peaks:
            peak["qx"], peak["qy"] = multicorr_refine(
                peak["qx"], peak["qy"], params["upsampleFactor"], spectrum
            )
        peaks.sort(key=lambda peak: peak["intensity"], reverse=True)

    return peaks


def case(name, **overrides):
    params = {
        "corrPower": 1.0,
        "sigmaCC": 0.0,
        "subpixel": "pixel",
        "upsampleFactor": 8,
        "minAbsoluteIntensity": 0.0,
        "minRelativeIntensity": 0.0,
        "relativeToPeak": 0,
        "minPeakSpacing": 0.0,
        "edgeBoundary": 1,
        "maxNumPeaks": 5,
    }
    params.update(overrides)
    return {"name": name, "params": params, "expected": find_peaks(params)}


cases = [
    case("pixel_baseline"),
    case("edge_boundary_four", edgeBoundary=4, maxNumPeaks=4),
    case("absolute_one", minAbsoluteIntensity=1.0),
    case("relative_half", minRelativeIntensity=0.5),
    case("relative_to_second", minRelativeIntensity=0.7, relativeToPeak=1),
    case("spacing_seven", minAbsoluteIntensity=0.1, minPeakSpacing=7.0),
    case("maximum_two", maxNumPeaks=2),
    case("parabolic", subpixel="poly"),
    case("multicorr_eight", subpixel="multicorr", upsampleFactor=8),
    case("hybrid_half", corrPower=0.5),
    case("gaussian_sigma_1_25", sigmaCC=1.25, subpixel="poly"),
]

json.dump(
    {
        "dimensions": [ROWS, COLS],
        "radius": RADIUS,
        "width": WIDTH,
        "trenchRadii": [TRENCH_INNER, TRENCH_OUTER],
        "pattern": pattern,
        "kernel": kernel,
        "cases": cases,
    },
    sys.stdout,
    separators=(",", ":"),
)
sys.stdout.write("\n")
