import warnings
import logging
import numpy as np, hyperspy.api as hs, exspy
s = exspy.signals.EDSTEMSpectrum(np.ones((2, 2, 2048)))
ax = s.axes_manager.signal_axes[0]; ax.scale = 0.01; ax.units = "keV"
s.set_microscope_parameters(beam_energy=200)
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    s.set_elements(["Al", "Cu", "Li"]); s.add_lines()
    print("elements:", s.metadata.Sample.elements, "lines:", s.metadata.Sample.xray_lines)
    for x in w: print("WARNING:", str(x.message)[:200])
try:
    print("Li lines near energy 0.054:", exspy.utils.eds.get_xray_lines_near_energy(0.054, width=0.05))
except Exception as e: print("err", e)
# T1 (Al2CuLi) vs theta' (Al2Cu): at% if Li invisible and normalised over Al+Cu
for name, comp in [("T1 Al2CuLi", {"Al":2,"Cu":1,"Li":1}), ("theta' Al2Cu", {"Al":2,"Cu":1})]:
    vis = {k:v for k,v in comp.items() if k!="Li"}; tot=sum(vis.values())
    print(name, "true at%:", {k: round(100*v/sum(comp.values()),1) for k,v in comp.items()}, "-> EDX-normalised at%:", {k: round(100*v/tot,1) for k,v in vis.items()})
