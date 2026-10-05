import warnings; warnings.filterwarnings("ignore")
import matplotlib; matplotlib.use("Agg")
import numpy as np, exspy, hyperspy.api as hs
from exspy.utils import eds as eu

def show(label, ints):
    print(label, [(i.metadata.Sample.xray_lines[0], float(np.asarray(i.data).ravel()[0])) for i in ints])

for name in ["EDS_SEM_TM002", "EDS_TEM_FePt_nanoparticles"]:
    s = getattr(exspy.data, name)()
    ax = s.axes_manager.signal_axes[0]
    md = s.metadata
    print("==", name, "shape", s.data.shape, s.data.dtype, "axis", ax.offset, ax.scale, ax.units, ax.size, "sum", float(s.data.sum()))
    print(" elements", md.Sample.elements, "lines", md.Sample.get_item("xray_lines"))
    inst = md.Acquisition_instrument
    print(" instrument", inst.as_dictionary())
    try: print(" TOA", s.get_take_off_angle())
    except Exception as e: print(" TOA err", e)
    show(" default get_lines_intensity", s.get_lines_intensity())
    s2 = getattr(exspy.data, name)(); s2.add_lines()
    print(" add_lines ->", s2.metadata.Sample.xray_lines)
    iw = s2.estimate_integration_windows(); show(" est. integration windows (2xFWHM)", s2.get_lines_intensity(integration_windows=iw))
    bw = s2.estimate_background_windows(line_width=[5.0, 2.0]); show(" background windows [5,2]", s2.get_lines_intensity(background_windows=bw))
    s3 = getattr(exspy.data, name)()
    show(" Mn_Ka default", s3.get_lines_intensity(["Mn_Ka"]))
    show(" Mn_Ka iw=2.1", s3.get_lines_intensity(["Mn_Ka"], integration_windows=2.1))
    s4 = getattr(exspy.data, name)(); s4.set_elements(["Mn"]); s4.set_lines(["Mn_Ka"])
    bw = s4.estimate_background_windows(); show(" Mn only bw", s4.get_lines_intensity(background_windows=bw))
    s5 = getattr(exspy.data, name)(); s5.set_microscope_parameters(tilt_stage=20.)
    try: print(" TOA tilt20", s5.get_take_off_angle())
    except Exception as e: print(" TOA tilt20 err", e)

# FWHM
for E, ln in [(1.4865,"Al_Ka"),(6.4039,"Fe_Ka"),(9.4421,"Pt_La"),(0.277,"C_Ka"),(8.0478,"Cu_Ka")]:
    print("FWHM", ln, eu.get_FWHM_at_Energy(130, E))
print("take_off_angle(0,0,35)", eu.take_off_angle(0.0, 0.0, 35.0))
print("take_off_angle(20,0,18)", eu.take_off_angle(20.0, 0.0, 18.0))
