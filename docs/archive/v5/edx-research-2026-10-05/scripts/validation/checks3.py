import warnings; warnings.filterwarnings("ignore")
import hyperspy.api as hs, exspy, numpy as np
import exspy._misc.eds as em
f = em.ffast_mac
bad = {}
for el, d in f.items():
    e = np.array(d["energies (keV)"]); mu = np.array(d["mass_absorption_coefficient (cm2/g)"])
    if (e == 0).any() or (mu == 0).any() or len(e) != len(mu):
        bad[el] = (int((e==0).sum()), [int(i) for i in np.where(e==0)[0]], len(e), int((mu==0).sum()))
print("elements with zero energies/macs:", len(bad), dict(list(bad.items())[:8]))
print("missing elements vs Z<=92:", sorted(set(["H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca"]) - set(f)))
