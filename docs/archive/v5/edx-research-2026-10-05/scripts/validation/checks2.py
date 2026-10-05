import warnings; warnings.filterwarnings("ignore")
import hyperspy.api as hs, exspy, numpy as np
from exspy.utils import eds as eu
from exspy import material as m
import exspy._misc.eds as em
f = em.ffast_mac
e = np.array(f["Al"]["energies (keV)"]); mac = np.array(f["Al"]["mass_absorption_coefficient (cm2/g)"])
print("ffast elements:", len(f), "Li:", "Li" in f, "H:", "H" in f)
print("Al ffast grid:", len(e), "min", e.min(), "max", e.max(), "zeros:", int((e==0).sum()), "monotonic:", bool(np.all(np.diff(e[e>0])>=0)))
print("Al around K edge:", [(round(a,5), b) for a,b in zip(e, mac) if 1.45 < a < 1.65])
print("TOA(10,45,22)", eu.take_off_angle(10., 45., 22.))
print("electron_range Cu 30", eu.electron_range("Cu", 30.))
print("xray_range Cu_Ka 30", eu.xray_range("Cu_Ka", 30.))
print("xray_range Cu_Ka 30 in C", eu.xray_range("Cu_Ka", 30., m.elements.C.Physical_properties.density_gcm3))
print("MAC Al [C_Ka, Al_Ka]", m.mass_absorption_coefficient("Al", ["C_Ka", "Al_Ka"]))
print("MAC mixture Al/Zn 50/50 Al_Ka", m.mass_absorption_mixture([50,50], ["Al","Zn"], "Al_Ka"))
print("wt->at Cu/Sn 88/12", m.weight_to_atomic((88,12),("Cu","Sn")))
print("at->wt Cu/Sn 93.2/6.8", m.atomic_to_weight([93.2,6.8],("Cu","Sn")))
print("density Cu/Sn 88/12", m.density_of_mixture([88,12],["Cu","Sn"]))
for absb in ["Al","Cu","Li"]:
    print("MAC absorber", absb, {l: round(float(m.mass_absorption_coefficient(absb, l)),2) for l in ["Al_Ka","Cu_Ka","Cu_La","Mg_Ka","O_Ka","Si_Ka","Zn_Ka","Ag_La"]})
print("cross_section_to_zeta Al,Zn 3,5", eu.cross_section_to_zeta([3,5],["Al","Zn"]))
