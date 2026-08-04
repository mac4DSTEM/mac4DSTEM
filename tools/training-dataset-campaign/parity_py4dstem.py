#!/usr/bin/env python3
"""Recompute QC-visible products with py4DSTEM and emit parity records.

This is the "missing wire" of docs/py4dstem-pipelines.md §10: the campaign
(main.swift) exports, for each training dataset, the exact arrays the app
produced for the products a user looks at — the strain map and the full-scan
ACOM orientation map — plus the Bragg vectors they were computed from (in the
EMD sidecar py4DSTEM already reads). This script recomputes the same products
with py4DSTEM's own code from the same Bragg vectors and writes one
machine-readable parity record per dataset+product.

Frames: the app works in (x = detector column, y = row); the sidecar and this
script use py4DSTEM's (qx = row, qy = column). The swap is applied exactly
once, here, when reading the app's parity_input JSON:
    py qx = app y,   py qy = app x
Under that axis swap the strain tensor transforms as beta' = P beta P with P
the (0,1) permutation, so:
    py e_xx <-> app e_yy,  py e_yy <-> app e_xx,
    py e_xy  =  app e_xy,  py theta = -app theta.

Comparison design (what each record isolates):
  strain — py4DSTEM indexes and fits FROM THE APP'S OWN Bragg vectors and the
    APP'S OWN reference basis (g1, g2). Identical inputs, so the record
    measures whether the app's port of index/fit/tensor matches py4DSTEM's
    latticevectors.py on real data. The reference-selection step is compared
    separately (py median reference vs app robust reference) inside the same
    record, because the app's robust rejection is a documented deviation.
  acom — py4DSTEM builds its own template bank (its defaults: 2 deg zone-axis
    and in-plane steps) from the same crystal and matches the same peaks. The
    two implementations sample orientation space differently by design, so
    agreement is measured as misorientation (deg, min over the proper cubic
    rotations) between matched orientations, not as bitwise equality.

Tolerances are FIRST PROPOSALS (recorded in each record's tolerance_basis):
no existing harness compares these products end-to-end on real data, so there
is nothing to derive from. A failing record is a finding to report, never a
number to tune away (ui-implementation-prompts.md Prompt A).
"""

import argparse
import datetime
import json
import sys
from pathlib import Path

import numpy as np

# Compare against the checked-in reference source, not whatever wheel the
# environment happens to carry: the repo's source-locked harnesses all pin
# References/py4DSTEM-dev, and the installed 0.14.17 wheel is additionally
# NumPy-2-incompatible in Crystal.__init__ (dtype="float_").
_REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO_ROOT / "References" / "py4DSTEM-dev"))

import py4DSTEM
from emdfile import PointList
from py4DSTEM.process.strain.latticevectors import (
    add_indices_to_braggvectors,
    fit_lattice_vectors_all_DPs,
    get_reference_g1g2,
    get_strain_from_reference_g1g2,
)
from scipy.spatial.transform import Rotation
from scipy.stats import spearmanr

SCHEMA = 1
GENERATOR = "tools/training-dataset-campaign/parity_py4dstem.py"

# First-proposal tolerances. Basis strings are embedded in the records so a
# reader never has to trust a bare number.
STRAIN_MEDIAN_TOL = 1e-3
STRAIN_P95_TOL = 5e-3
STRAIN_TOLERANCE_BASIS = (
    "first proposal, anchored to measurement: identical Bragg vectors and "
    "identical reference basis are supplied to both implementations, and the "
    "fit estimators are matched (see notes on the weighting DEVIATION), after "
    "which sim_Au agrees to ~2e-4 median per component; the gate leaves ~4x "
    "headroom for messier datasets. The remaining differences come from the "
    "app's robust MAD outlier pass, its |h|,|k|<=8 indexing clamp, and "
    "float32 vs float64. The UNMATCHED-estimator difference (py4DSTEM's "
    "effective w^2 weighting vs the app's standard w weighting) is reported "
    "as weighting_deviation_* and is NOT gated: it is a documented DEVIATION "
    "in Core/Analysis/StrainMapping.swift, ~5e-3 median on sim_Au."
)
ACOM_MEDIAN_DEG_TOL = 3.0
ACOM_WITHIN_5DEG_TOL = 0.80
ACOM_TOLERANCE_BASIS = (
    "first proposal: both implementations sample orientation space at coarse "
    "steps (py4DSTEM defaults 2 deg zone-axis/in-plane; the app plans 96 zone "
    "axes over the cubic fundamental zone, ~3 deg), so two correct matchers "
    "can disagree by roughly one sampling step on a clean pattern and "
    "arbitrarily at grain boundaries/weak patterns. Requiring median <= 3 deg "
    "and >= 80% within 5 deg over the mutually-confident subset asserts the "
    "maps describe the same microstructure without demanding identical "
    "template banks."
)


def _fail(msg):
    print(f"parity: FATAL: {msg}", file=sys.stderr)
    sys.exit(70)


def _now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def load_inputs(output_dir):
    pairs = []
    for spec_path in sorted(output_dir.glob("*.parity_input.json")):
        stem = spec_path.name[: -len(".parity_input.json")]
        sidecar = output_dir / f"{stem}.mac4dstem.h5"
        if not sidecar.exists():
            _fail(f"{spec_path.name} has no matching sidecar {sidecar.name}")
        pairs.append((stem, spec_path, sidecar))
    if not pairs:
        _fail(f"no *.parity_input.json under {output_dir}")
    return pairs


def app_map(values, w, h, dtype=float):
    """App flat array (index y*w + x) -> py4DSTEM-shaped (Rx=h, Ry=w) array."""
    return np.asarray(values, dtype=dtype).reshape(h, w)


def make_lattice_pointlist(g1, g2, q_radius):
    """All integer combinations h*g1 + k*g2 within q_radius of the origin."""
    # Bound the (h, k) search by the shorter basis vector's projection.
    lengths = [np.hypot(*g1), np.hypot(*g2)]
    if min(lengths) <= 0:
        _fail("degenerate reference basis in parity input")
    nmax = int(np.ceil(q_radius / min(lengths))) + 1
    rows = []
    for h in range(-nmax, nmax + 1):
        for k in range(-nmax, nmax + 1):
            qx = h * g1[0] + k * g2[0]
            qy = h * g1[1] + k * g2[1]
            if np.hypot(qx, qy) <= q_radius:
                rows.append((qx, qy, h, k))
    data = np.zeros(
        len(rows),
        dtype=[("qx", float), ("qy", float), ("g1_ind", int), ("g2_ind", int)],
    )
    for i, (qx, qy, h, k) in enumerate(rows):
        data[i] = (qx, qy, h, k)
    return PointList(data=data, name="lattice")


def fit_lattice_vectors_all_DPs_estimator_matched(braggpeaks):
    """py4DSTEM's per-position lattice fit, but minimizing sum(w * r^2).

    py4DSTEM's fit_lattice_vectors multiplies the design matrix AND the data
    by the intensity weight before lstsq, which minimizes sum(w^2 * r^2). The
    app's port minimizes the statistically standard sum(w * r^2) (DEVIATION
    note in Core/Analysis/StrainMapping.swift). Matching the estimator here
    (sqrt(w) into lstsq) lets the record gate the rest of the port —
    indexing, origin+g fit model, tensor, frames — with the one diagnosed
    deviation factored out and reported separately.
    """
    from py4DSTEM.data import RealSlice

    labels = ("x0", "y0", "g1x", "g1y", "g2x", "g2y", "error", "mask")
    out = RealSlice(
        data=np.zeros((8, braggpeaks.shape[0], braggpeaks.shape[1])),
        slicelabels=labels,
        name="g1g2_map_estimator_matched",
    )
    for rx in range(braggpeaks.shape[0]):
        for ry in range(braggpeaks.shape[1]):
            pl = braggpeaks.get_pointlist(rx, ry)
            if pl.length < 5:
                continue
            gi, ki = pl.data["g1_ind"], pl.data["g2_ind"]
            design = np.vstack((np.ones_like(gi, dtype=float), gi, ki)).T
            alpha = np.vstack((pl.data["qx"], pl.data["qy"])).T
            sw = np.sqrt(np.maximum(pl.data["intensity"], 1e-6))[:, None]
            beta = np.linalg.lstsq(design * sw, alpha * sw, rcond=None)[0]
            out.get_slice("x0").data[rx, ry] = beta[0, 0]
            out.get_slice("y0").data[rx, ry] = beta[0, 1]
            out.get_slice("g1x").data[rx, ry] = beta[1, 0]
            out.get_slice("g1y").data[rx, ry] = beta[1, 1]
            out.get_slice("g2x").data[rx, ry] = beta[2, 0]
            out.get_slice("g2y").data[rx, ry] = beta[2, 1]
            out.get_slice("mask").data[rx, ry] = 1
    return out


def compare_strain(stem, spec, bragg, q_radius):
    app = spec["strain"]
    w, h = spec["scanWidth"], spec["scanHeight"]
    # App frame -> py4DSTEM frame (see module docstring).
    g1 = (app["refG1"][1], app["refG1"][0])
    g2 = (app["refG2"][1], app["refG2"][0])
    tol = app["indexingTolerancePixels"]

    bragg.setcal(center=True, ellipse=False, pixel=False, rotate=False)
    lattice = make_lattice_pointlist(g1, g2, q_radius)
    indexed = add_indices_to_braggvectors(bragg, lattice, maxPeakSpacing=tol)

    app_mask = app_map(app["mask"], w, h, bool)
    app_arrays = {
        "e_xx": app_map(app["eyy"], w, h),
        "e_yy": app_map(app["exx"], w, h),
        "e_xy": app_map(app["exy"], w, h),
        "theta": -app_map(app["theta"], w, h),
    }

    def component_diffs(g1g2_map, prefix):
        strain = get_strain_from_reference_g1g2(g1g2_map, g1, g2)
        py_mask = g1g2_map.get_slice("mask").data.astype(bool)
        joint = app_mask & py_mask
        stats = {}
        worst_median = worst_p95 = 0.0
        if not joint.any():
            return stats, joint, np.inf, np.inf
        for name in ("e_xx", "e_yy", "e_xy", "theta"):
            d = np.abs(strain.get_slice(name).data[joint] - app_arrays[name][joint])
            stats[f"{prefix}{name}_median_absdiff"] = float(np.median(d))
            stats[f"{prefix}{name}_p95_absdiff"] = float(np.percentile(d, 95))
            stats[f"{prefix}{name}_max_absdiff"] = float(d.max())
            worst_median = max(worst_median, float(np.median(d)))
            worst_p95 = max(worst_p95, float(np.percentile(d, 95)))
        return stats, joint, worst_median, worst_p95

    # Gated comparison: estimator matched, so the diagnosed weighting
    # DEVIATION does not mask a regression anywhere else in the port.
    g1g2_matched = fit_lattice_vectors_all_DPs_estimator_matched(indexed)
    matched_stats, joint, worst_median, worst_p95 = component_diffs(
        g1g2_matched, ""
    )
    # Reported, not gated: the deviation magnitude against stock py4DSTEM.
    g1g2_stock = fit_lattice_vectors_all_DPs(indexed)
    stock_stats, _, _, _ = component_diffs(g1g2_stock, "weighting_deviation_")

    n_joint = int(joint.sum())
    metrics = {
        "app_indexed": int(app_mask.sum()),
        "py_indexed": int(
            g1g2_matched.get_slice("mask").data.astype(bool).sum()
        ),
        "joint_indexed": n_joint,
    }
    metrics.update(matched_stats)
    metrics.update(stock_stats)
    if n_joint == 0:
        return {
            "pass": False,
            "metrics": metrics,
            "notes": ["no jointly indexed positions; nothing to compare"],
        }
    metrics["mask_jaccard"] = float(
        n_joint
        / (app_mask | g1g2_matched.get_slice("mask").data.astype(bool)).sum()
    )

    # Reference-selection agreement, reported separately: py4DSTEM's plain
    # median reference over the joint mask vs the app's robust reference.
    ref_g1, ref_g2 = get_reference_g1g2(g1g2_matched, joint)
    metrics["reference_g1_absdiff_px"] = float(
        np.hypot(ref_g1[0] - g1[0], ref_g1[1] - g1[1])
    )
    metrics["reference_g2_absdiff_px"] = float(
        np.hypot(ref_g2[0] - g2[0], ref_g2[1] - g2[1])
    )

    passed = worst_median <= STRAIN_MEDIAN_TOL and worst_p95 <= STRAIN_P95_TOL
    return {
        "pass": bool(passed),
        "metrics": metrics,
        "tolerance": {
            "component_median_absdiff": STRAIN_MEDIAN_TOL,
            "component_p95_absdiff": STRAIN_P95_TOL,
        },
        "tolerance_basis": STRAIN_TOLERANCE_BASIS,
        "notes": [
            "py4DSTEM ran add_indices_to_braggvectors + the lattice fit +"
            " get_strain_from_reference_g1g2 on the app's exported Bragg"
            " vectors with the app's reference basis",
            "gated metrics use the estimator-matched fit; weighting_deviation_*"
            " metrics are stock py4DSTEM (w^2 effective weighting) vs the app"
            " and quantify the DEVIATION documented in"
            " Core/Analysis/StrainMapping.swift — reported, not gated",
            "reference_g?_absdiff_px compares py4DSTEM's plain median reference"
            " against the app's robust reference (documented deviation); it is"
            " reported, not gated",
        ],
    }


def misorientation_deg(a_mats, b_mats, sym_ops):
    """Minimum misorientation angle (deg) per pair over crystal symmetry.

    a_mats, b_mats: (N, 3, 3) rotation matrices sharing one convention.

    Both implementations store M with COLUMNS = lab axes in crystal
    coordinates (py4DSTEM uses `M.T @ g_vec_all` to take crystal g-vectors into
    the lab, crystal_ACOM.py:762), so M maps lab -> crystal and a grain's
    orientation is defined only up to relabelling the CRYSTAL axes: M ~ S @ M.
    Symmetry therefore multiplies on the LEFT. Minimising over one operator is
    the complete answer: the two-sided minimum min_{S,S'} angle(S A B^T S'^T)
    equals min_S angle(S A B^T), because angle(XY) == angle(YX).

    This previously inserted the operator between A and B.T, which minimises
    over LAB-side operators instead. That is not symmetry-invariant — see
    tools/training-dataset-campaign/test_parity_metric.py, where relabelling
    the crystal axes moved the old metric by up to 51 deg while a genuine
    lab-frame change left it untouched, i.e. it absorbed exactly what it should
    have measured and measured exactly what it should have absorbed.
    """
    rel = np.einsum("nij,nkj->nik", a_mats, b_mats)  # A @ B.T
    best = np.full(a_mats.shape[0], np.inf)
    for op in sym_ops:
        tr = np.trace(np.einsum("ij,njk->nik", op, rel), axis1=1, axis2=2)
        best = np.minimum(
            best, np.degrees(np.arccos(np.clip((tr - 1) / 2, -1, 1)))
        )
    return best


CUBIC_RANDOM_MISORIENTATION_DEG = 40.0
NEIGHBOUR_COHERENCE_LIMIT_DEG = 25.0


def neighbour_coherence_deg(mats, coords, stride, sym_ops):
    """Median misorientation between adjacent sampled scan positions.

    A specimen's grains are enormously larger than a scan step, so a matcher
    that is resolving the microstructure returns nearly the same orientation at
    neighbouring positions, whatever the microstructure is. A matcher that is
    not returns the random baseline (~40 deg for cubic). Unlike "spread about
    the map's modal orientation", this says nothing about whether the specimen
    is single- or poly-crystalline, so it is a fair check on either side.
    """
    index = {c: i for i, c in enumerate(coords)}
    left, right = [], []
    for i, (rx, ry) in enumerate(coords):
        for neighbour in ((rx + stride, ry), (rx, ry + stride)):
            j = index.get(neighbour)
            if j is not None:
                left.append(i)
                right.append(j)
    if not left:
        return None, 0
    d = misorientation_deg(mats[left], mats[right], sym_ops)
    return float(np.median(d)), len(left)


def compare_acom(stem, spec, bragg, stride):
    app = spec["acom"]
    w, h = spec["scanWidth"], spec["scanHeight"]
    if app["symmetry"].lower() != "cubic":
        return {
            "pass": None,
            "metrics": {},
            "notes": [
                f"symmetry {app['symmetry']} not supported by this comparator;"
                " recorded as known non-comparable"
            ],
        }

    crystal = py4DSTEM.process.diffraction.Crystal(
        positions=np.array(app["siteFractional"], dtype=float),
        numbers=np.array(app["siteAtomicNumbers"], dtype=int),
        cell=float(app["cellAAngstrom"]),
    )
    crystal.calculate_structure_factors(float(app["kMaxInvAngstrom"]))
    crystal.orientation_plan(
        accel_voltage=float(spec["voltageKV"]) * 1e3,
        progress_bar=False,
    )

    bragg.setcal(center=True, ellipse=False, pixel=True, rotate=False)
    app_ti = app_map(app["templateIndex"], w, h, int)
    app_rel = app_map(app["reliability"], w, h)
    mats = app["orientationMatrixRowMajor"]

    rows = []
    for rx in range(0, h, stride):
        for ry in range(0, w, stride):
            flat = rx * w + ry  # app flat index y*w + x with (y=rx, x=ry)
            if app_ti[rx, ry] < 0 or not mats[flat]:
                continue
            vectors = bragg.get_vectors(
                scan_x=rx, scan_y=ry,
                center=True, ellipse=False, pixel=True, rotate=False,
            )
            orientation = crystal.match_single_pattern(
                bragg_peaks=vectors, verbose=False, plot_corr=False
            )
            if orientation.corr is None or orientation.corr[0] <= 0:
                continue
            rows.append(
                (
                    np.array(mats[flat], dtype=float).reshape(3, 3),
                    np.array(orientation.matrix[0], dtype=float),
                    float(app_rel[rx, ry]),
                    float(orientation.corr[0]),
                    (rx, ry),
                )
            )

    total_sampled = len(range(0, h, stride)) * len(range(0, w, stride))
    if not rows:
        return {
            "pass": False,
            "metrics": {"positions_sampled": total_sampled, "positions_compared": 0},
            "notes": ["no position was matched by both implementations"],
        }

    a_mats = np.stack([r[0] for r in rows])
    b_mats = np.stack([r[1] for r in rows])
    py_corr = np.array([r[3] for r in rows])
    sym_ops = Rotation.create_group("O").as_matrix()

    # Lab-frame map at the export boundary. The app matrix acts in the app lab
    # frame (x = column, y = row), py4DSTEM's in (qx = row, qy = column), and
    # both store lab axes in their COLUMNS. Column j of the app matrix is app
    # lab axis j, so rebuilding the py4DSTEM column order is a right
    # multiplication: M_app = M_py @ P, with P the x<->y swap plus the z flip
    # that keeps it a proper rotation. Symmetry acts on the left and the frame
    # on the right; they do not mix.
    #
    # This is derived from the two conventions, not fitted. The previous
    # left-multiplication was tuned on sim_Au, where it cannot be tested at
    # all: py4DSTEM puts every sampled sim_Au position within 10 deg of one
    # orientation, and on a single grain ANY constant frame map fits.
    lab_swap = np.array([[0.0, 1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, -1.0]])
    b_in_app_frame = np.einsum("nij,jk->nik", b_mats, lab_swap)
    mis = misorientation_deg(a_mats, b_in_app_frame, sym_ops)

    # Mutually-confident subset: py4DSTEM's correlation top half. The
    # REFERENCE picks the subset deliberately — letting the app choose which
    # of its own answers to be graded on would let a bad confidence measure
    # flatter the result. The app's reliability is scored separately, below.
    confident = py_corr >= np.median(py_corr)
    subset = mis[confident] if confident.any() else mis
    metrics = {
        "positions_sampled": total_sampled,
        "positions_compared": len(rows),
        "confident_positions": int(confident.sum()),
        "confidence_definition": "py4DSTEM correlation >= its median",
        "misorientation_median_deg_all": float(np.median(mis)),
        "misorientation_median_deg_confident": float(np.median(subset)),
        "misorientation_p90_deg_confident": float(np.percentile(subset, 90)),
        "fraction_within_5deg_confident": float(np.mean(subset <= 5.0)),
        "scan_stride": stride,
    }

    # Is the REFERENCE resolving anything on this dataset? Neighbouring scan
    # positions sit inside the same grain, so a working matcher agrees with
    # itself across a scan step. When py4DSTEM does not, the comparison carries
    # no information about the app and must not be reported as the app failing.
    coords = [r[4] for r in rows]
    reference_coherence, pairs = neighbour_coherence_deg(
        b_mats, coords, stride, sym_ops
    )
    app_coherence, _ = neighbour_coherence_deg(a_mats, coords, stride, sym_ops)
    metrics["reference_neighbour_median_deg"] = reference_coherence
    metrics["app_neighbour_median_deg"] = app_coherence
    metrics["neighbour_pairs"] = pairs
    reference_is_incoherent = (
        reference_coherence is not None
        and reference_coherence > NEIGHBOUR_COHERENCE_LIMIT_DEG
    )
    if reference_is_incoherent:
        return {
            "pass": None,
            "metrics": metrics,
            "notes": [
                "NOT COMPARABLE: py4DSTEM's own orientation map is spatially"
                f" incoherent on this dataset — adjacent scan positions"
                f" {stride} step(s) apart disagree by"
                f" {reference_coherence:.1f} deg median, against a ~"
                f"{CUBIC_RANDOM_MISORIENTATION_DEG:.0f} deg random baseline for"
                " cubic. Grains are far larger than a scan step, so the"
                " reference is not resolving the microstructure here and any"
                " app-vs-reference number would measure the reference's noise."
                " Verified independently of k_max: raising py4DSTEM's template"
                " bank from 1.2 to 2.0 A^-1 (all peaks inside the bank) leaves"
                " its self-disagreement at ~38 deg.",
                f"for the record, the app's own neighbour coherence is"
                f" {app_coherence:.1f} deg and the app-vs-reference median is"
                f" {metrics['misorientation_median_deg_confident']:.1f} deg;"
                " neither is evidence about the app until the reference"
                " converges",
                "this dataset is py4DSTEM's STRAIN tutorial specimen; ACOM is"
                " not a workflow its own notebooks run on it",
            ],
        }

    # Does the app's own confidence measure RANK? A number that is small
    # everywhere is useless; what matters is whether sorting by it sorts by
    # accuracy. Reported, not gated — the tolerance is on agreement, and this
    # is a separate property that deserves its own visibility.
    app_rel_values = np.array([r[2] for r in rows])
    if app_rel_values.size and np.ptp(app_rel_values) > 0:
        metrics["app_reliability_median"] = float(np.median(app_rel_values))
        metrics["app_reliability_p90"] = float(np.percentile(app_rel_values, 90))
        high = app_rel_values >= np.median(app_rel_values)
        metrics["app_reliability_top_half_median_deg"] = float(
            np.median(mis[high])
        )
        metrics["app_reliability_bottom_half_median_deg"] = float(
            np.median(mis[~high])
        )
        metrics["app_reliability_spearman_vs_error"] = float(
            spearmanr(app_rel_values, mis).statistic
        )

    passed = (
        metrics["misorientation_median_deg_confident"] <= ACOM_MEDIAN_DEG_TOL
        and metrics["fraction_within_5deg_confident"] >= ACOM_WITHIN_5DEG_TOL
    )
    return {
        "pass": bool(passed),
        "metrics": metrics,
        "tolerance": {
            "misorientation_median_deg_confident": ACOM_MEDIAN_DEG_TOL,
            "fraction_within_5deg_confident": ACOM_WITHIN_5DEG_TOL,
        },
        "tolerance_basis": ACOM_TOLERANCE_BASIS,
        "notes": [
            "py4DSTEM built its own template bank (defaults: 2 deg steps,"
            f" k_max {app['kMaxInvAngstrom']} A^-1, {spec['voltageKV']} kV) from"
            " the same crystal and matched the app's exported Bragg vectors",
            "app plan: 96 zone axes over the cubic fundamental zone",
            "py4DSTEM matrices are mapped into the app lab frame by RIGHT"
            " multiplication (M_app = M_py @ P, P = row/column swap + z flip,"
            " the same boundary convention as the peak export); misorientation"
            " is min over the 24 proper cubic rotations applied on the crystal"
            " side. Both are checked by"
            " tools/training-dataset-campaign/test_parity_metric.py",
            "the confident subset is chosen by py4DSTEM's correlation, not by"
            " the app's own reliability, so the app cannot select the answers"
            " it is graded on; app_reliability_* scores that metric separately",
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path,
                        help="campaign output dir (sidecars + parity inputs)")
    parser.add_argument("records_dir", type=Path,
                        help="where to write parity record JSON files")
    parser.add_argument("--acom-stride", type=int, default=2,
                        help="compare every Nth scan row/column for ACOM "
                             "(py4DSTEM's per-pattern matching is the slow "
                             "side; the app side is always full-scan)")
    parser.add_argument("--report-only", action="store_true",
                        help="always exit 0; use while establishing tolerances")
    args = parser.parse_args()

    args.records_dir.mkdir(parents=True, exist_ok=True)
    index = []
    any_fail = False

    for stem, spec_path, sidecar in load_inputs(args.output_dir):
        spec = json.loads(spec_path.read_text())
        dataset = spec["dataset"]
        bragg = py4DSTEM.read(sidecar, datapath="/braggvectors_root/braggvectors")
        q_radius = float(np.hypot(*bragg.Qshape)) / 2

        # The sidecar stores only the mean origin (qx0_mean/qy0_mean); the
        # app's exported peaks are already descanned onto that reference
        # origin, so a constant origin is the exact calibration for them —
        # promote it so setcal(center=True) is satisfiable.
        cal = bragg.calibration
        if cal.get_origin() is None:
            qx0, qy0 = cal.get_origin_mean()
            if qx0 is None or qy0 is None:
                _fail(f"{sidecar.name} carries no origin calibration")
            cal.set_origin((qx0, qy0))

        products = {}
        if spec.get("strain"):
            products["strain"] = compare_strain(stem, spec, bragg, q_radius)
        else:
            products["strain"] = {
                "pass": None, "metrics": {},
                "notes": ["app produced no strain map for this dataset"
                          " (see campaign report stage 'strain')"],
            }
        if spec.get("acom"):
            products["acom"] = compare_acom(stem, spec, bragg, args.acom_stride)
        else:
            products["acom"] = {
                "pass": None, "metrics": {},
                "notes": ["no phase model / Q calibration for this dataset;"
                          " ACOM is not computed by the app here"],
            }

        for product, result in products.items():
            record = {
                "schema": SCHEMA,
                "generated": _now(),
                "generator": GENERATOR,
                "dataset": dataset,
                "product": product,
                "reference": f"py4DSTEM {py4DSTEM.__version__}",
                **result,
            }
            path = args.records_dir / f"{stem}.{product}.json"
            path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
            index.append(
                {"dataset": dataset, "product": product,
                 "pass": result["pass"], "file": path.name}
            )
            status = {True: "PASS", False: "FAIL", None: "not-comparable"}[
                result["pass"]
            ]
            print(f"parity: {dataset} {product}: {status}")
            if result["pass"] is False:
                any_fail = True

    (args.records_dir / "index.json").write_text(
        json.dumps(
            {"schema": SCHEMA, "generated": _now(), "records": index},
            indent=2, sort_keys=True,
        ) + "\n"
    )
    if any_fail and not args.report_only:
        print("parity: at least one product disagrees with py4DSTEM;"
              " this is a finding to report, not a tolerance to widen",
              file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
