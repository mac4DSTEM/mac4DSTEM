import warnings; warnings.filterwarnings("ignore")
import logging; logging.disable(logging.WARNING)
import numpy as np, exspy
def run(label, **kw):
    s = exspy.data.EDS_TEM_FePt_nanoparticles(); s.add_elements(["Cu"]); s.change_dtype("float")
    m = s.create_model(True); m.set_signal_range(5.5, 10.0)
    m.fit()  # LS start
    if kw: m.fit(**kw)
    I = m.get_lines_intensity(xray_lines=["Fe_Ka", "Pt_La"])
    y = s.isig[5.5:10.0].data.astype(float); mu = m._model_function(m.p0) if False else m.as_signal().isig[5.5:10.0].data.astype(float)
    mu = np.clip(mu, 1e-9, None)
    nll = float(np.sum(mu - y*np.log(mu)))
    print(f"{label:40s} Fe_Ka={float(I[0].data[0]):10.2f} Pt_La={float(I[1].data[0]):10.2f} poissonNLL={nll:.3f}")
run("LS (lm)")
run("ML-poisson NM from LS start", optimizer="Nelder-Mead", loss_function="ML-poisson")
run("ML-poisson L-BFGS-B from LS start", optimizer="L-BFGS-B", loss_function="ML-poisson")
run("ML-poisson Powell from LS start", optimizer="Powell", loss_function="ML-poisson")
