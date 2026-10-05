import warnings; warnings.filterwarnings("ignore")
import numpy as np, exspy
mac = exspy.material.mass_absorption_coefficient
for line in ["Mg_Ka","Al_Ka","Si_Ka","Cu_Ka"]:
    mu = float(mac("Al", line))  # cm^2/g per exspy docs
    out=[]
    for t_nm in (50,100,150):
        for toa in (18.0, 22.0, 30.0):
            x = mu*2.70*(t_nm*1e-7)/np.sin(np.radians(toa))
            out.append(f"t={t_nm} TOA={toa}: x/(1-e^-x)={x/(1-np.exp(-x)):.3f}")
    print(line, f"mu/rho(Al)={mu:.1f} cm2/g |", "; ".join(out[:3]), "|", "; ".join(out[3:6]))
