#!/usr/bin/env python3
"""Guard the ACOM parity metric itself.

The parity records are only worth what the comparator is worth. A misplaced
symmetry operator produced a metric that was invariant under the lab-frame
difference it was supposed to measure, and sensitive to the crystal-axis
relabelling it was supposed to absorb — and it was "verified" on a dataset
(sim_Au) that is one grain, where any constant frame map fits and nothing can
be tested at all. These assertions are the properties that fact-check the
metric without reference to any dataset.

Run: python tools/training-dataset-campaign/test_parity_metric.py
Also runs as part of tools/run-tests.sh scientific.
"""
import sys
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parity_py4dstem import misorientation_deg  # noqa: E402

SYM = Rotation.create_group("O").as_matrix()
# The lab-frame map between the two conventions: app (x = column, y = row) vs
# py4DSTEM (qx = row, qy = column), z flipped so it stays a proper rotation.
P = np.array([[0.0, 1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, -1.0]])
TOL = 1e-4  # degrees; arccos near 1 is only good to ~1e-6 deg
FAILURES = []


def check(name, condition, detail=""):
    print(f"  {'PASS' if condition else 'FAIL'}  {name}{detail}")
    if not condition:
        FAILURES.append(name)


def main():
    rng = np.random.default_rng(20260804)
    A = Rotation.random(120, random_state=rng).as_matrix()
    B = Rotation.random(120, random_state=rng).as_matrix()

    print("ACOM parity metric checks")

    d = misorientation_deg(A, A, SYM)
    check("a matrix has zero misorientation with itself",
          d.max() < TOL, f"  (max {d.max():.2e} deg)")

    # Crystal symmetry acts on the LEFT for the shared "columns = lab axes in
    # crystal coordinates" convention, so relabelling must change nothing.
    base = misorientation_deg(A, B, SYM)
    worst = 0.0
    for S in SYM:
        worst = max(
            worst,
            np.abs(misorientation_deg(S @ A, B, SYM) - base).max(),
            np.abs(misorientation_deg(A, S @ B, SYM) - base).max(),
        )
    check("invariant under crystal-axis relabelling M -> S @ M",
          worst < TOL, f"  (worst drift {worst:.2e} deg)")

    # A genuine lab-frame change must NOT be absorbed, or the metric cannot
    # detect a frame bug — which is the failure mode that produced the
    # original 8 deg sim_Au number.
    drift = np.abs(misorientation_deg(A, B @ P, SYM) - base).max()
    check("sensitive to a lab-frame change M -> M @ P",
          drift > 1.0, f"  (drift {drift:.2f} deg)")

    # Injected rotations must come back exactly. Stay below 45 deg: the
    # smallest non-identity cubic rotation is 90 deg, so nothing folds.
    ok = True
    detail = []
    for theta in (0.5, 1.0, 3.0, 5.0, 10.0, 30.0, 44.0):
        axes = rng.normal(size=(len(A), 3))
        axes /= np.linalg.norm(axes, axis=1, keepdims=True)
        dR = Rotation.from_rotvec(np.radians(theta) * axes).as_matrix()
        got = misorientation_deg(np.einsum("nij,njk->nik", dR, A), A, SYM)
        err = np.abs(got - theta).max()
        ok = ok and err < TOL
        detail.append(f"{theta:g}->{np.median(got):.3f}")
    check("recovers injected rotations", ok, "  (" + ", ".join(detail) + ")")

    # Round trip through the frame map: an app matrix that is exactly
    # py4DSTEM's answer must score zero.
    round_tripped = np.einsum("nij,jk->nik", B, P)
    d = misorientation_deg(round_tripped, np.einsum("nij,jk->nik", B, P), SYM)
    check("frame-mapped round trip is zero",
          d.max() < TOL, f"  (max {d.max():.2e} deg)")

    if FAILURES:
        print(f"\nFAILED: {', '.join(FAILURES)}")
        return 1
    print("\nall metric checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
