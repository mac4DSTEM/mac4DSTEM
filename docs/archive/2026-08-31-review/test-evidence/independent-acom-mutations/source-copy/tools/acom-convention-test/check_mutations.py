#!/usr/bin/env python3
"""Break the convention gate in disposable source copies, never the checkout.

Usage: python3 tools/acom-convention-test/check_mutations.py OUTPUT_DIRECTORY
Logs and disposition JSON are retained at the requested directory.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = "mac4DSTEM/Core/Crystal/OrientationPlan.swift"
MATCHER = "mac4DSTEM/Core/Crystal/OrientationMatcher.swift"
TEST = "tools/acom-convention-test/main.swift"
MUTATIONS = [
    ("projection-swap", PLAN,
     "let x = simd_dot(refl.g, e1)\n            let y = simd_dot(refl.g, e2)",
     "let x = simd_dot(refl.g, e2)\n            let y = simd_dot(refl.g, e1)",
     "FAIL: Au independent matrix orientation"),
    ("projection-mirror", PLAN, "azim: atan2(y, x)", "azim: atan2(-y, x)",
     "FAIL: Au independent matrix orientation"),
    ("wrong-template-matrix", MATCHER,
     "detectorBasis: plan.detectorBases[bestTemplate]",
     "detectorBasis: plan.detectorBases[0]",
     "FAIL: Au independent matrix orientation"),
    ("correlation-sign", MATCHER,
     "let bin = (azimuthalCount - bestBin) % azimuthalCount", "let bin = bestBin",
     "FAIL: Au independent matrix orientation"),
    ("vacuous-oracle", TEST, "let m = op * a * b.transpose",
     "let m = matrix_identity_double3x3",
     "FAIL: oracle must distinguish a generic wrong orientation"),
    ("all-matches-empty", MATCHER,
     "guard bestTemplate >= 0 else { return .empty }",
     "guard false else { return .empty }",
     "FAIL: Au no skipped failed match"),
]

def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix="mac4dstem-acom-mutations-") as tmp:
        clone = Path(tmp)
        shutil.copytree(ROOT / "mac4DSTEM/Core", clone / "mac4DSTEM/Core")
        shutil.copytree(ROOT / "tools/lib", clone / "tools/lib")
        shutil.copytree(ROOT / "tools/acom-convention-test", clone / "tools/acom-convention-test")
        cases = [("control", None, None, None, "acom-convention-test: all passed")] + MUTATIONS
        for name, relative, before, after, expected in cases:
            path = clone / relative if relative else None
            original = path.read_text() if path else None
            if path:
                if original.count(before) != 1:
                    raise RuntimeError(f"{name}: mutation target must occur exactly once")
                path.write_text(original.replace(before, after, 1))
            try:
                run = subprocess.run([str(clone / "tools/acom-convention-test/run.sh")],
                                     text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            finally:
                if path:
                    path.write_text(original)
            (output / f"{name}.log").write_text(run.stdout)
            expected_exit = 0 if name == "control" else 1
            passed = run.returncode == expected_exit and expected in run.stdout
            records.append({"case": name, "source": relative, "original": before,
                            "replacement": after, "expectedFailure": expected,
                            "exitCode": run.returncode, "verified": passed})
            (output / "results.json").write_text(json.dumps(records, indent=2) + "\n")
            print(f"{'PASS' if passed else 'FAIL'}: {name}; exit {run.returncode}; expected evidence {expected}", flush=True)
            if not passed:
                raise SystemExit(1)

if __name__ == "__main__":
    main()
