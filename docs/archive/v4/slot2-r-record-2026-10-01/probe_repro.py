import sys, numpy as np, json
sys.argv = ["x"]
import importlib.util
spec = importlib.util.spec_from_file_location("synth", "synth.py"); synth = importlib.util.module_from_spec(spec); spec.loader.exec_module(synth)
synth.import_py4dstem()
from py4DSTEM.process.phase.utils import ComplexProbe
s = 1.0 / (0.025 * 64)
def build(df):
    cp = ComplexProbe(energy=80e3, gpts=(64, 64), sampling=(s, s), semiangle_cutoff=20.0, rolloff=2.0, parameters={"defocus": df})
    return np.asarray(cp.build()._array, dtype=np.complex128), cp
a, cpa = build(200.0); b, cpb = build(200.0)
print("same process twice: max |d| %.3e" % np.abs(a - b).max(), "dtype", cpa._array.dtype, "params", cpa._parameters.get("C10"), "phase_shift", getattr(cpa, "_phase_shift", None))
t = json.load(open("truth-1.json"))["fixtures"][0]; d = json.load(open("fx/df200-s1.json"))
pt = np.asarray(t["probeReal"]) + 1j * np.asarray(t["probeImag"]); pd = np.asarray(d["probeReal"]) + 1j * np.asarray(d["probeImag"])
r = pt / pd; m = np.abs(pd) > 1e-3 * np.abs(pd).max()
print("truth.py / synth probe ratio: |ratio| mean %.6f std %.2e, angle mean %.4f std %.2e rad" % (np.abs(r[m]).mean(), np.abs(r[m]).std(), np.angle(r[m]).mean(), np.angle(r[m]).std()))
np.save("probe-proc1.npy", a)
