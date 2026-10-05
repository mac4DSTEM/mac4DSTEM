import warnings; warnings.filterwarnings("ignore")
import logging; logging.disable(logging.WARNING)
import numpy as np, exspy, hyperspy.api as hs
s = exspy.data.EDS_TEM_FePt_nanoparticles(); s.add_elements(["Cu"]); s.change_dtype("float")
m = s.create_model(True); m.set_signal_range(5.5, 10.0); m.fit()
def report(tag):
    I = m.get_lines_intensity(xray_lines=["Fe_Ka", "Pt_La"])
    y = s.isig[5.5:10.0].data; mu = np.clip(m.as_signal().isig[5.5:10.0].data, 1e-9, None)
    print(f"{tag:28s} Fe_Ka={float(I[0].data[0]):9.2f} Pt_La={float(I[1].data[0]):9.2f} NLL={float(np.sum(mu - y*np.log(mu))):.3f}")
report("LS unweighted")
# IRLS: weighted LS with variance = current model (identity-link Poisson GLM -> ML fixed point)
for it in range(8):
    var = s.deepcopy(); var.data = np.clip(m.as_signal().data, 1.0, None)
    s.metadata.set_item("Signal.Noise_properties.variance", var)
    m.fit()
    report(f"IRLS iter {it+1}")
