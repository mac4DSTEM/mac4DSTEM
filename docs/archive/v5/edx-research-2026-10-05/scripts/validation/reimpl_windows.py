# Independent numpy re-implementation of exspy window integration, to prove the spec
import warnings; warnings.filterwarnings("ignore")
import math, numpy as np, exspy
from exspy import material
ELEM = material._elements_dict
def line_E(xl):
    el, ln = xl.split("_"); return ELEM[el]["Atomic_properties"]["Xray_lines"][ln]["energy (keV)"]
def fwhm(res, E):
    return math.sqrt(2.5*(E-line_E("Mn_Ka"))*1000 + res*res)/1000
def v2i(v, off, sc):
    idx = 1e-12*np.trunc((v-off)/sc*1e12)
    # positive value: round half towards zero
    return int(np.sign(idx)*np.ceil(abs(idx)-0.5)) if v >= 0 else int(np.sign(idx)*np.floor(abs(idx)+0.5))
def window_sum(d, off, sc, a, b):
    i0, i1 = v2i(a, off, sc), v2i(b, off, sc)
    return d[i0:i1].sum(), (i0, i1)
for name in ["EDS_TEM_FePt_nanoparticles", "EDS_SEM_TM002"]:
    s = getattr(exspy.data, name)(); s.add_lines()
    ax = s.axes_manager.signal_axes[0]; d = s.data.astype(float)
    print(name, "is_binned", ax.is_binned, "res", s.metadata.get_item("Acquisition_instrument.TEM.Detector.EDS.energy_resolution_MnKa") or s.metadata.get_item("Acquisition_instrument.SEM.Detector.EDS.energy_resolution_MnKa"))
    res = s.metadata.Acquisition_instrument.as_dictionary()
    res = list(res.values())[0]["Detector"]["EDS"]["energy_resolution_MnKa"]
    for xl in s.metadata.Sample.xray_lines:
        E = line_E(xl); w = fwhm(res, E)
        tot, idx = window_sum(d, ax.offset, ax.scale, E - w, E + w)
        # background windows line_width [5,2], windows_width 1
        bw = [E - w*5 - w, E - w*5, E + w*2, E + w*2 + w]
        b1, i1 = window_sum(d, ax.offset, ax.scale, bw[0], bw[1]); b2, i2 = window_sum(d, ax.offset, ax.scale, bw[2], bw[3])
        corr = (idx[1]-idx[0]) / ((i1[1]-i1[0]) + (i2[1]-i2[0]))
        print(f"  {xl} E={E} FWHM={w:.6f} window idx {idx} sum={tot:.0f}  bg-sub={tot-(b1+b2)*corr:.4f}")
