"""Reference for ACOMEulerFrameTests: the frame and convention of the Euler angles of an ACOM map.

Two parts, each run in the environment that has its library (each part is skipped when its import fails):

1. py4DSTEM f050d207 (0.14.19, NumPy 2.5.0, SciPy 1.18.0): the three patterns the Swift test plants in py4DSTEM's frame
   (qx = g . x_lab along the detector rows, qy = g . y_lab along the columns), matched by `match_single_pattern`.
   Measured 2026-10-31: 1.41, 1.95 and 0.88 deg from the planted G; 33.3, 56.0 and 34.7 deg from G with x and y swapped
   and z reversed (the matcher's frame), so the planted truth is in py4DSTEM's frame.
2. orix 0.15.0 with SciPy 1.18.1, 500 random G: the SciPy triple t = from_matrix(G.T).as_euler("zxz") read as Bunge
   (orix `Rotation.from_euler`, lab to crystal) in the order (t2, t1, t0) is G (9e-16); py4DSTEM's
   `orientation_map_to_orix_CrystalMap` (`Rotation.from_euler(t, direction="crystal2lab")`) is diag(1,-1,1) G diag(1,-1,1).

On the public Al-Mg-Si demo, py4DSTEM's `match_single_pattern` on the app's own peaks gave grain C [111] the orientation
pinned in `testTheDemoGrainCAgreesWithPy4DSTEM` (Euler 45.0, 54.7355, -40.013 deg; the matcher's frame read -135.0,
54.7, 130.3); the app's map in py4DSTEM's frame is 0.30 deg from it (median of 255 positions).
"""
import itertools

import numpy as np


def proper_cubic():
    ops = []
    for perm in itertools.permutations(range(3)):
        for s in itertools.product([1, -1], repeat=3):
            m = np.zeros((3, 3))
            for i, j in enumerate(perm):
                m[i, j] = s[i]
            if np.linalg.det(m) > 0:
                ops.append(m)
    return ops


def misorientation_deg(g1, g2, ops):
    return min(np.degrees(np.arccos(np.clip((np.trace(s @ g1 @ g2.T) - 1) / 2, -1, 1))) for s in ops)


def planted_py4dstem():
    from emdfile import PointList
    from py4DSTEM.process.diffraction import Crystal

    crystal = Crystal(np.array([[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]]), 13, 4.0495)
    crystal.calculate_structure_factors(1.2)
    crystal.orientation_plan(zone_axis_range="auto", angle_step_zone_axis=1.0, angle_step_in_plane=1.0,
                             accel_voltage=200e3, progress_bar=False)
    lam, ops = 0.02508, proper_cubic()
    f = np.array([[0, 1, 0], [1, 0, 0], [0, 0, -1.0]])
    g_all = crystal.g_vec_all.T
    intensity = np.abs(crystal.struct_factors) ** 2
    for axis, angle in [((5, 2, 7), 17.3), ((1, 4, 6), 17.3), ((7, 3, 9), 52.0)]:
        n = np.array(axis, float) / np.linalg.norm(axis)
        seed = np.array([0, 0, 1.0]) if abs(n[2]) < 0.8 else np.array([1.0, 0, 0])
        f0 = seed - seed.dot(n) * n
        f0 /= np.linalg.norm(f0)
        t = np.radians(angle)
        x = f0 * np.cos(t) + np.cross(n, f0) * np.sin(t)
        x /= np.linalg.norm(x)
        y = np.cross(n, x)
        planted = np.column_stack([x, y, n])
        sg = -g_all @ n + 0.5 * lam * np.sum(g_all**2, axis=1)
        w = intensity * np.exp(-((sg / 0.03) ** 2))
        keep = (np.abs(sg) <= 0.1) & (w > 0) & (np.linalg.norm(g_all, axis=1) > 0)
        data = np.zeros(int(keep.sum()), dtype=[("qx", "f8"), ("qy", "f8"), ("intensity", "f8")])
        data["qx"], data["qy"], data["intensity"] = g_all[keep] @ x, g_all[keep] @ y, w[keep]
        g = np.array(crystal.match_single_pattern(PointList(data), num_matches_return=1, verbose=False).matrix[0])
        print(axis, angle, "py4DSTEM vs planted %.2f deg, vs the matcher's frame %.2f deg"
              % (misorientation_deg(g, planted, ops), misorientation_deg(g, planted @ f, ops)))


def orix_conventions():
    from orix.quaternion import Rotation
    from scipy.spatial.transform import Rotation as R

    d = np.diag([1.0, -1, 1])
    bunge = export = 0.0
    for g in R.random(500, random_state=4).as_matrix():
        t = R.from_matrix(g.T).as_euler("zxz")
        bunge = max(bunge, np.abs(Rotation.from_euler(t[[2, 1, 0]]).to_matrix()[0] - g).max())
        export = max(export, np.abs(Rotation.from_euler(t, direction="crystal2lab").to_matrix()[0] - d @ g @ d).max())
    print("Bunge (t2, t1, t0) is G: %.1e; py4DSTEM orix export is diag(1,-1,1) G diag(1,-1,1): %.1e" % (bunge, export))


if __name__ == "__main__":
    for part in (planted_py4dstem, orix_conventions):
        try:
            part()
        except ImportError as error:
            print(part.__name__, "skipped:", error)
