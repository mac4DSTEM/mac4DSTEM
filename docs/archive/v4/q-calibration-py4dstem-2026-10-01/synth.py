import sys, numpy as np, warnings
warnings.filterwarnings("ignore")
for n,v in [("float_",np.float64),("int_",np.int64),("bool_",np.bool_),("object_",np.object_),("str_",np.str_),("complex_",np.complex128)]:
    if not hasattr(np,n): setattr(np,n,v)
sys.path.insert(0,"/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/py4DSTEM-dev")
import py4DSTEM
assert "References/py4DSTEM-dev" in py4DSTEM.__file__
from py4DSTEM.process.diffraction import Crystal
from py4DSTEM import BraggVectors
from py4DSTEM.data import Calibration
from emdfile import PointListArray, PointList
import io, contextlib

a=4.05
al=Crystal([[0,0,0],[0.5,0.5,0],[0.5,0,0.5],[0,0.5,0.5]],[13]*4,a)
al.calculate_structure_factors(2.0)
hkl=al.hkl.T; g=al.g_vec_leng; I=al.struct_factors_int
order=np.argsort(g)
print("model comb (|g| Å^-1, |F|^2, hkl) first 12:")
seen=set()
for i in order:
    key=round(g[i],4)
    if key in seen: continue
    seen.add(key); print(f"  {g[i]:.4f} {I[i]:9.1f} {tuple(hkl[i])}")
    if len(seen)>=12: break

# [001]-zone data: (h,k,0) with h,k even, at TRUE pixel size p
p=0.01  # Å^-1 / px
zone=[i for i in range(len(g)) if hkl[i][2]==0 and g[i]>0]
print("\n[001] zone data rings (Å^-1):", sorted(set(np.round(g[zone],3))))
rng=np.random.default_rng(0)
N=16
pla=PointListArray(dtype=np.dtype([("qx","f8"),("qy","f8"),("intensity","f8")]),shape=(N,1))
for r in range(N):
    qx=al.g_vec_all[0,zone]/p+rng.normal(0,0.3,len(zone)); qy=al.g_vec_all[1,zone]/p+rng.normal(0,0.3,len(zone))
    it=I[zone]*rng.uniform(0.7,1.3,len(zone))
    pl=PointList(np.array(list(zip(qx,qy,it)),dtype=pla.dtype)); pla[r,0]=pl

def run(f, **kw):
    cal=Calibration(); cal.set_Q_pixel_size(p*f); cal.set_Q_pixel_units("A^-1")
    cal.set_origin((np.zeros((N,1)),np.zeros((N,1))))
    bv=BraggVectors(Rshape=(N,1),Qshape=(256,256),calibration=cal); bv.set_raw_vectors(pla)
    bv.setcal(center=True,ellipse=False,pixel=True,rotate=False)
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            out=al.calibrate_pixel_size(bv,scale_pixel_size=1.0,verbose=False,**kw)
            return out.calibration.get_Q_pixel_size()/p
        except Exception as e:
            return f"ERR {type(e).__name__}: {str(e)[:60]}"

for kw in [dict(), dict(k_broadening=0.02), dict(k_broadening=0.02,fit_all_intensities=True), dict(k_broadening=0.05)]:
    print("\nkwargs:",kw or "defaults (k_broadening=0.002, single int scale)")
    for f in [1.0,0.95,1.05,0.9,1.1,0.866,0.8,1.2,1/np.sqrt(2),np.sqrt(2)]:
        res=run(f,**kw)
        s=f"{res:.4f}" if isinstance(res,float) else res
        print(f"  start guess pixel size = {f:.3f} x true  ->  returned / true = {s}")
