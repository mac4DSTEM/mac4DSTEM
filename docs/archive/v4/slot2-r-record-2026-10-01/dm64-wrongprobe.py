"""Refuter: DM with the probe FIXED but WRONG (defocus off by -10 % / +10 % / +25 %), nm 0, float64, vs GD joint from the same
wrong probe. Decides whether 'DM, probe fixed' is offerable when the probe is not known exactly."""
import sys, pathlib, json, numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from synth import load, score, import_py4dstem
from dm64 import run
py4DSTEM = import_py4dstem()
from py4DSTEM.process.phase.utils import ComplexProbe

fx = sys.argv[1]; d = load(fx)
keys = {k: d[k] for k in d if not k.startswith("_") and not isinstance(d[k], list)}
print("fixture keys:", keys)
det = d["probeShape"][0]; sampling = d["objectSamplingAngstrom"]; energy = d.get("energyEV", 80e3)
semi = d.get("semiangleMrad", 20.0); roll = d.get("rolloffMrad", 2.0); df0 = d["defocusAngstrom"]
mean_intensity = float((d["_amp"].astype(np.float64) ** 2).sum() / d["_amp"].shape[0])
for factor in (1.0, 0.9, 1.1, 1.25):
    pu = np.asarray(ComplexProbe(energy=energy, gpts=(det, det), sampling=(sampling, sampling), semiangle_cutoff=semi, rolloff=roll,
                                 parameters={"defocus": df0 * factor}).build()._array, dtype=np.complex128)
    probe = pu * np.sqrt(mean_intensity / np.sum(np.abs(np.fft.fft2(pu)) ** 2))
    dd = dict(d); dd["_probe"] = probe
    for label, kw in [("DM a1 fixP nm0 f64", dict(method="dm", nm=0.0, dtype="float64", alpha=1.0, fix_probe=1)),
                      ("DM a1 joint nm0.02 f64", dict(method="dm", nm=0.02, dtype="float64", alpha=1.0, fix_probe=0)),
                      ("GD joint nm1 f64", dict(method="gd", nm=1.0, dtype="float64", alpha=1.0, fix_probe=0))]:
        rows = run(dd, iterations=32, clamp=1, **kw)
        print(pathlib.Path(fx).stem, "defocus x%.2f" % factor, label, " | ".join("it%d e=%.2e P=%.3f r=%.3f" % r for r in rows), flush=True)
