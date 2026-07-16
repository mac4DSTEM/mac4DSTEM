#!/usr/bin/env python3
import json
import math
import sys

expected = json.load(open(sys.argv[1]))
report_text = open(sys.argv[2]).read()
actual, _ = json.JSONDecoder().raw_decode(report_text)
if len(actual) != len(expected):
    raise SystemExit(f"FAIL: report count {len(actual)}, expected {len(expected)}")

for want, got in zip(expected, actual):
    for key in ("file", "datasetPath", "shape", "dtype"):
        if got[key] != want[key]:
            raise SystemExit(f"FAIL: {want['file']} {key}: {got[key]!r} != {want[key]!r}")
    if got["finitePatternFraction"] < 0.999:
        raise SystemExit(f"FAIL: {want['file']} finite fraction {got['finitePatternFraction']}")
    for key in (
        "diskSampleCandidateCounts", "diskSampleAfterAbsoluteCounts",
        "diskSampleAfterRelativeCounts", "diskSampleAfterSpacingCounts",
        "diskSamplePeakCounts",
    ):
        if got[key] != want[key]:
            raise SystemExit(f"FAIL: {want['file']} {key}: {got[key]} != {want[key]}")
    if not math.isclose(
        got["diskProbeRadiusPixels"], want["diskProbeRadiusPixels"],
        rel_tol=2e-6, abs_tol=1e-4
    ):
        raise SystemExit(
            f"FAIL: {want['file']} diskProbeRadiusPixels: "
            f"{got['diskProbeRadiusPixels']} != {want['diskProbeRadiusPixels']}"
        )
    for key in ("virtualImageMinimum", "virtualImageMaximum", "virtualImageMean", "virtualImageChecksum"):
        if not math.isclose(got[key], want[key], rel_tol=2e-6, abs_tol=1e-3):
            raise SystemExit(f"FAIL: {want['file']} {key}: {got[key]} != {want[key]}")
    if got["elapsedSeconds"] > 15:
        raise SystemExit(f"FAIL: {want['file']} exceeded 15 s acceptance budget: {got['elapsedSeconds']:.2f} s")
    print(f"PASS: {want['file']} golden and {got['elapsedSeconds']:.2f} s budget")
