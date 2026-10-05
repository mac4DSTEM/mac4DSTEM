# Low-count behaviour of exspy defaults on a synthetic Al-Cu spectrum image with known truth.
import warnings; warnings.filterwarnings("ignore")
import logging; logging.disable(logging.WARNING)
import numpy as np, hyperspy.api as hs, exspy
from exspy.utils import eds as eu
rng = np.random.default_rng(12345)
ax = {"name": "E", "units": "keV", "scale": 0.01, "offset": 0.0, "size": 2048}
truth_wt_cu = 54.1  # Al2Cu by weight (theta/theta')
s0 = eu.xray_lines_model(elements=["Al", "Cu"], weight_percents=[100 - truth_wt_cu, truth_wt_cu], energy_axis=ax)
peaks = s0.data / s0.data.sum()
bg = np.ones_like(peaks); bg[:20] = 0; bg /= bg.sum()
print("truth: Al2Cu, Cu wt%% = %.1f ; model uses k-factor 1 by construction (xray_lines_model)" % truth_wt_cu)
print("N(counts/px) | vac-masked %% | px with single-line 100%% %% | per-pixel Cu wt%% mean/sd (unmasked) | pooled Cu wt%% (sum of map)")
for N in [1, 3, 10, 30, 100, 1000]:
    for bgfrac in [0.0, 0.3]:
        lam = N * ((1 - bgfrac) * peaks + bgfrac * bg)
        data = rng.poisson(np.broadcast_to(lam, (64, 64, lam.size))).astype(float)
        s = exspy.signals.EDSTEMSpectrum(data)
        s.axes_manager.signal_axes[0].update_from(s0.axes_manager.signal_axes[0], ("scale", "offset", "units", "name"))
        s.set_microscope_parameters(beam_energy=200, energy_resolution_MnKa=130)
        s.set_elements(["Al", "Cu"]); s.add_lines(["Al_Ka", "Cu_Ka"])
        ints = s.get_lines_intensity()
        vm = s.vacuum_mask()  # default threshold=1.0 counts, closing=True
        q = s.quantification(ints, "CL", [1.0, 1.0], composition_units="weight")  # default navigation_mask=1.0 -> vacuum mask
        cu = q[1].data
        unmasked = ~vm.data
        ia, ic = ints[0].data, ints[1].data
        single = ((ia > 0.1) ^ (ic > 0.1)).mean() * 100
        pooled = 100 * ic.sum() / (ia.sum() + ic.sum())
        vals = cu[unmasked]
        print("%5d bg=%.1f | %6.1f | %6.1f | %s | %.2f" % (N, bgfrac, vm.data.mean() * 100, single,
              ("%.1f / %.1f" % (vals.mean(), vals.std())) if vals.size else "n/a (all masked)", pooled))
