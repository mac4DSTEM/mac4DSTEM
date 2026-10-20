#!/usr/bin/env python3
"""Break the convention gate in disposable source copies, never the checkout.

Usage: python3 tools/harnesses/acom-convention-test/check_mutations.py OUTPUT_DIRECTORY
Logs and disposition JSON are retained at the requested directory.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# Since the orientation switch (DiffractoKit 0.5.0) the projection, the correlation and the result construction this gate
# judges are the KIT's. The mutations are applied to the kit's sources in a scratch copy of the pinned checkout
# (.build/checkouts/DiffractoKit, a git checkout at the pin: the dirty tree keeps `kit_module`'s pin check satisfied).
KIT = "DiffractoKit"
LIBRARY = f".build/checkouts/{KIT}/Sources/DiffractoOrientation/ACOMTemplateLibrary.swift"
MATCHER = f".build/checkouts/{KIT}/Sources/DiffractoOrientation/ACOMMatcher.swift"
TEST = "tools/harnesses/acom-convention-test/main.swift"
MUTATIONS = [
    ("projection-swap", LIBRARY,
     "let x = simd_dot(refl.g, e1), y = simd_dot(refl.g, e2)",
     "let x = simd_dot(refl.g, e2), y = simd_dot(refl.g, e1)",
     "FAIL: Au sampled independent matrix orientation"),
    ("projection-mirror", LIBRARY, "azimuth: atan2(y, x), weight: w", "azimuth: atan2(-y, x), weight: w",
     "FAIL: Au sampled independent matrix orientation"),
    ("wrong-template-matrix", LIBRARY,
     "detectorBasis: detectorBases[templateIndex]",
     "detectorBasis: detectorBases[0]",
     "FAIL: Au sampled independent matrix orientation"),
    ("correlation-sign", MATCHER,
     "let bin = (na - bestBin) % na", "let bin = bestBin",
     "FAIL: Au sampled independent matrix orientation"),
    ("vacuous-oracle", TEST, "let m = op * a * b.transpose",
     "let m = matrix_identity_double3x3",
     "FAIL: oracle must distinguish a generic wrong orientation"),
    ("all-matches-empty", MATCHER,
     "guard selected.template >= 0 else { return .empty }",
     "guard selected.template < 0 else { return .empty }",
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
        # The pinned kit checkouts and their built objects (a scratch copy: the mutations never touch the real ones).
        for name in ("Package.swift", "Package.resolved"):
            shutil.copy2(ROOT / name, clone / name)
        (clone / ".build").mkdir()
        shutil.copytree(ROOT / ".build/checkouts", clone / ".build/checkouts", symlinks=True)
        for tools in ("cubokit-tools", "imagokit-tools", "diffractokit-tools"):
            shutil.copytree(ROOT / ".build" / tools, clone / ".build" / tools, symlinks=True)
        shutil.copytree(ROOT / "tools/lib", clone / "tools/lib")
        shutil.copytree(ROOT / "tools/harnesses/acom-convention-test", clone / "tools/harnesses/acom-convention-test")
        cases = [("control", None, None, None, "acom-convention-test: all passed")] + MUTATIONS
        for name, relative, before, after, expected in cases:
            path = clone / relative if relative else None
            original = path.read_text() if path else None
            if path:
                path.chmod(0o644)   # SwiftPM checkouts are read-only
            if path:
                if original.count(before) != 1:
                    raise RuntimeError(f"{name}: mutation target must occur exactly once")
                path.write_text(original.replace(before, after, 1))
            # kit_module rebuilds the kit only when its pin stamp is missing: remove it so the (mutated) kit is rebuilt.
            (clone / ".build/diffractokit-tools/.pin").unlink(missing_ok=True)
            try:
                run = subprocess.run([str(clone / "tools/harnesses/acom-convention-test/run.sh")],
                                     text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            finally:
                if path:
                    path.write_text(original)
                (clone / ".build/diffractokit-tools/.pin").unlink(missing_ok=True)
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
