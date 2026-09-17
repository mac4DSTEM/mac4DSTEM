#!/usr/bin/env python
"""Fairness closure: CrystalPhase residual for Al-alone, T1-alone, and Al+T1 at
T1 positions. If T1-alone fits better (lower residual) than Al-alone yet Al+T1
picks Al, the joint NNLS preference for Al is a scoring artifact, not T1 being
unexplainable by py4DSTEM."""
import os, sys, json, numpy as np
for _n,_v in [("float_",np.float64),("int_",np.int64),("uint",np.uint64),("bool_",np.bool_),
              ("object_",np.object_),("str_",np.str_),("complex_",np.complex128)]:
    if not hasattr(np,_n): setattr(np,_n,_v)
REPO="/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM"
sys.path.insert(0, os.path.join(REPO,"References/py4DSTEM-dev"))
from py4DSTEM.process.diffraction import Crystal
from py4DSTEM.process.diffraction.crystal_phase import CrystalPhase
from py4DSTEM.braggvectors import BraggVectors
from py4DSTEM.data import Calibration
from py4DSTEM import PointListArray
d=json.load(open(sys.argv[1])); P=d["positions"]; byi={p["i"]:p for p in P}; reach=d["reach"]

al=Crystal(positions=np.array([[0,0,0],[.5,.5,0],[.5,0,.5],[0,.5,.5]],dtype=float),
           numbers=np.array([13]*4),cell=4.0495); al.calculate_structure_factors(1.0)
t1p=np.array([[0.333333,0,0],[0.666667,0,0],[0,0.333333,0],[0,0.666667,0],[0.666667,0.666667,0],
 [0.333333,0.333333,0],[0,0,0.4062],[0,0,0.5938],[0.666667,0.333333,0.1612],[0.333333,0.666667,0.8388],
 [0.333333,0.666667,0.1612],[0.666667,0.333333,0.8388],[0.5,0,0.3237],[0.5,0,0.6763],[0,0.5,0.3237],
 [0,0.5,0.6763],[0.5,0.5,0.3237],[0.5,0.5,0.6763],[0,0,0.1993],[0,0,0.8007],[0.333333,0.666667,0.5],
 [0.666667,0.333333,0.5]],dtype=float)
t1=Crystal(positions=t1p,numbers=np.array([13]*8+[29]*10+[3]*4),
           cell=np.array([4.94775,4.94775,14.14499,90,90,120],dtype=float)); t1.calculate_structure_factors(1.0)

sel=[p["i"] for p in P if p["truth"]==3 and p["verdict"]=="indexed"][:15]
sel+=[p["i"] for p in P if p["truth"]==3 and p["verdict"]=="notIndexed"][:15]
sel+=[p["i"] for p in P if p["truth"]==0][:15]     # Al control
N=len(sel)
dtype=np.dtype([("qx","float64"),("qy","float64"),("intensity","float64")])
pla=PointListArray(dtype=dtype,shape=(N,1))
for n,i in enumerate(sel):
    pk=byi[i]["peaks"]
    if pk: pla[n,0].add(np.array([tuple(x) for x in pk],dtype=dtype))
cal=Calibration(name="cal"); cal.set_Q_pixel_size(1.0); cal.set_origin((np.zeros((N,1)),np.zeros((N,1))))
bv=BraggVectors(Rshape=(N,1),Qshape=(128,128),calibration=cal); bv.set_raw_vectors(pla)
bv.setcal(center=True,ellipse=False,pixel=True,rotate=False)
for c in (al,t1):
    c.orientation_plan(zone_axis_range="full",angle_step_zone_axis=2.0,angle_step_in_plane=2.0,
                       accel_voltage=200e3,progress_bar=False)
    c.match_orientations(bv,min_number_peaks=3,progress_bar=False)

def resid(crystals):
    ph=CrystalPhase(crystals)
    ph.quantify_phase(bv,corr_kernel_size=0.04,k_max=reach,single_phase=False,progress_bar=False)
    return ph.phase_residuals[:,0], ph.phase_weights

rAl,_=resid([al]); rT1,_=resid([t1]); rBoth,Wb=resid([al,t1])
ident=np.array(CrystalPhase([al,t1]).crystal_identity)
labels=["T1_indexed"]*15+["T1_notIndexed"]*15+["Al"]*15
from collections import defaultdict
agg=defaultdict(lambda:{"al":[],"t1":[],"both":[],"t1w":[],"n":0})
for n,i in enumerate(sel):
    g=labels[n]; a=agg[g]; a["n"]+=1
    a["al"].append(rAl[n]); a["t1"].append(rT1[n]); a["both"].append(rBoth[n])
    w=Wb[n,0]; tw=w[ident[:,0]==1].sum(); aw=w[ident[:,0]==0].sum()
    a["t1w"].append(tw/(tw+aw) if (tw+aw)>0 else 0)
md=lambda x: float(np.median(x)) if x else float("nan")
print(f"{'group':16}{'n':>3}  {'medResAl-alone':>15}{'medResT1-alone':>15}{'medResBoth':>12}{'medT1frac(Both)':>16}")
for g in ["T1_indexed","T1_notIndexed","Al"]:
    a=agg[g]
    print(f"{g:16}{a['n']:>3}  {md(a['al']):>15.4f}{md(a['t1']):>15.4f}{md(a['both']):>12.4f}{md(a['t1w']):>16.3f}")
print("\nInterpretation: if T1-alone residual < Al-alone residual at T1 positions,")
print("T1 IS the better single-phase explanation, so Both->Al is a scoring artifact.")
