#!/usr/bin/env python3
"""Pin the Bragg-peak positions of a harness report into expected.json (S19).

usage: pin-positions.py expected.json report.json

For every dataset ALREADY pinned in expected.json, copies `diskSampleScanPositions`
and `diskSamplePeakPositions` from the report (the harness's own output, peaks
rounded to 0.01 px) and rewrites the file. It pins today's behaviour; it is not a
py4DSTEM comparison and it moves no scientific number. Re-run it, and say so in
the commit, only when a peak movement is intended and understood. Counts and
image values are NOT touched here.
"""
import json
import sys

expected_path, report_path = sys.argv[1], sys.argv[2]
expected = json.load(open(expected_path))
report = {e["file"]: e for e in json.JSONDecoder().raw_decode(open(report_path).read())[0]}


def block(entry):
    lines = []
    for key, value in entry.items():
        if key == "diskSamplePeakPositions":
            rows = ["      " + json.dumps(peaks) for peaks in value]
            lines.append(f'    "{key}": [\n' + ",\n".join(rows) + "\n    ]")
        else:
            lines.append(f'    "{key}": {json.dumps(value)}')
    return "  {\n" + ",\n".join(lines) + "\n  }"


out = []
for entry in expected:
    got = report[entry["file"]]
    fresh = {}
    for key, value in entry.items():
        if key in ("diskSampleScanPositions", "diskSamplePeakPositions"):
            continue
        fresh[key] = value
        if key == "diskSamplePeakCounts":
            fresh["diskSampleScanPositions"] = got["diskSampleScanPositions"]
            fresh["diskSamplePeakPositions"] = got["diskSamplePeakPositions"]
    assert [len(p) for p in fresh["diskSamplePeakPositions"]] == fresh["diskSamplePeakCounts"], (
        f"{entry['file']}: the report's peaks disagree with the pinned counts — "
        "a count moved, this script pins positions only")
    out.append(block(fresh))
open(expected_path, "w").write("[\n" + ",\n".join(out) + "\n]\n")
