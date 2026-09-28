"""run_their_vectors.py — A3a (docs/archive/v4/a3a-thronsen-stride3-2026-09-28.md): Thronsen et al.'s own vector
analysis notebooks, executed unmodified on disk against the stride-3 cube, with the four registered grid patches.

Their code is read at run time from References/SPED-phase-mapping-main/VectorAnalysis (ADR 042: run, never copy).
Every code cell runs in order in one namespace; display-only lines (plots, markers, `%` magics) are dropped, and the
interactive peak-finding preview cell is skipped. Each patch must match its line exactly once, or the run stops.

    python run_their_vectors.py <work dir> [--nb2-only]   (conda env `thronsen`; one heavy job at a time)
    --nb2-only reruns notebook 2 from notebook 1's saved peak files in <work dir>.

Writes <work dir>/their_vectors_stride3.npy (171 x 171 phase ids after their score cut-off) and prints their own
success-rate line.
"""
import json
import os
import sys

import matplotlib
matplotlib.use("Agg")
import h5py
import hyperspy.api as hs
import numpy as np
import pyxem as pxm

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NB = os.path.join(REPO, "References", "SPED-phase-mapping-main", "VectorAnalysis")
CUBE = os.path.join(REPO, "References", "thronsen-datasetA", "datasetA_stride3.h5")
TRUTH = os.path.join(REPO, "References", "thronsen-datasetA", "published", "ground_truth.hspy")
STRIDE = 3

PATCHES = {  # (notebook, exact original text) -> replacement; the registered deviations
    ("vector_analysis_1_peak_finding.ipynb", "dp = hs.load(folder + file + '.hspy')"): "dp = __cube__",
    ("vector_analysis_1_peak_finding.ipynb", "Al_peaks = peaks_com[215, 274].copy()"): "Al_peaks = peaks_com[72, 91].copy()",
    ("vector_analysis_1_peak_finding.ipynb", "dpshape = (512, 512)"): "dpshape = (171, 171)",
    ("vector_analysis_2.ipynb", "X_pix = (512, 512)"): "X_pix = (171, 171)",
    ("vector_analysis_2.ipynb", "GT = np.load('ground_truth_all.npy', allow_pickle=True)"): "GT = __gt__",
    # not a method change: their CIF folder is relative to the notebook, and we run in a work dir
    ("vector_analysis_2.ipynb", "folder_cif = '../cif-files/'"): "folder_cif = __cif__",
}
DISPLAY = (".plot(", "add_peak_array_as_markers", "plt.", "%matplotlib")


def load_cube():
    with h5py.File(CUBE, "r") as f:
        data = f["Experiments/__unnamed__/data"][...].astype(np.float32) / 65535.0
    s = pxm.signals.ElectronDiffraction2D(data)
    for i, (scale, offset, units) in enumerate([(2.4943 * STRIDE, 0.0, "nm"), (2.4943 * STRIDE, 0.0, "nm")]):
        ax = s.axes_manager.navigation_axes[i]; ax.scale, ax.offset, ax.units = scale, offset, units
    for ax in s.axes_manager.signal_axes:
        ax.scale, ax.offset, ax.units = 0.01904, -1.2138, "$A^{-1}$"
    return s


def run_notebook(name, ns, used):
    cells = json.load(open(os.path.join(NB, name)))["cells"]
    for idx, cell in enumerate(cells):
        if cell["cell_type"] != "code":
            continue
        src = "".join(cell["source"])
        if "interactive=True" in src:
            print(f"[{name} cell {idx}] skipped (interactive preview)", flush=True)
            continue
        for (nb, old), new in PATCHES.items():
            if nb == name and old in src:
                assert src.count(old) == 1, (name, idx, old)
                src = src.replace(old, new); used.add((nb, old))
        kept = [l for l in src.splitlines() if not any(t in l for t in DISPLAY)]
        code = "\n".join(kept).strip()
        if not code:
            continue
        try:
            compiled = compile(code, f"{name}:cell{idx}", "exec")
        except SyntaxError:
            # a display call spanning several lines; the cell must be display-only to be skipped
            if any(t in src for t in DISPLAY):
                print(f"[{name} cell {idx}] skipped (multi-line display call)", flush=True)
                continue
            raise
        exec(compiled, ns)


def main(work):
    os.makedirs(work, exist_ok=True); os.chdir(work)
    ns = {"__name__": "__their_notebook__",
          "__cube__": load_cube(),
          "__gt__": hs.load(TRUTH).data[::STRIDE, ::STRIDE],
          "__cif__": os.path.join(REPO, "References", "SPED-phase-mapping-main", "cif-files") + "/"}
    used = set()
    if "--nb2-only" in sys.argv and os.path.exists("peaks_noAl_calibrated.npy"):
        print("notebook 1 skipped: reusing its saved peak files in", work, flush=True)
        used |= {k for k in PATCHES if k[0] == "vector_analysis_1_peak_finding.ipynb"}
    else:
        run_notebook("vector_analysis_1_peak_finding.ipynb", ns, used)
    ns2 = {k: ns[k] for k in ("__name__", "__gt__", "__cif__")}   # notebook 2 reloads from the .npy files, as written
    run_notebook("vector_analysis_2.ipynb", ns2, used)
    missing = set(PATCHES) - used
    if missing:
        sys.exit(f"patches that matched nothing (the notebooks changed?): {sorted(missing)}")
    np.save(os.path.join(work, "their_vectors_stride3.npy"), np.asarray(ns2["phase_id"]).reshape(171, 171))
    print("wrote", os.path.join(work, "their_vectors_stride3.npy"))


if __name__ == "__main__":
    main(sys.argv[1])
