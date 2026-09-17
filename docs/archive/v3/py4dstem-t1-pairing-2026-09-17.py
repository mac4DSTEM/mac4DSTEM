#!/usr/bin/env python
"""Transparent (no-NNLS, no-ACOM) check: at real T1 positions, how many
experimental peaks does each phase's reference explain, at the KNOWN zone axes?
Pairs each experimental peak to the nearest reference peak within corr_kernel
(0.04). Answers: does T1 fit the data at least as well as Al geometrically?"""
import os, sys, json, numpy as np
for _n,_v in [("float_",np.float64),("int_",np.int64),("uint",np.uint64),("bool_",np.bool_),
              ("object_",np.object_),("str_",np.str_),("complex_",np.complex128)]:
    if not hasattr(np,_n): setattr(np,_n,_v)
REPO="/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM"
sys.path.insert(0, os.path.join(REPO,"References/py4DSTEM-dev"))
from py4DSTEM.process.diffraction import Crystal

d=json.load(open(sys.argv[1])); P=d["positions"]; byi={p["i"]:p for p in P}

al=Crystal(positions=np.array([[0,0,0],[.5,.5,0],[.5,0,.5],[0,.5,.5]],dtype=float),
           numbers=np.array([13,13,13,13]),cell=4.0495); al.calculate_structure_factors(1.0)
t1p=np.array([[0.333333,0,0],[0.666667,0,0],[0,0.333333,0],[0,0.666667,0],[0.666667,0.666667,0],
 [0.333333,0.333333,0],[0,0,0.4062],[0,0,0.5938],[0.666667,0.333333,0.1612],[0.333333,0.666667,0.8388],
 [0.333333,0.666667,0.1612],[0.666667,0.333333,0.8388],[0.5,0,0.3237],[0.5,0,0.6763],[0,0.5,0.3237],
 [0,0.5,0.6763],[0.5,0.5,0.3237],[0.5,0.5,0.6763],[0,0,0.1993],[0,0,0.8007],[0.333333,0.666667,0.5],
 [0.666667,0.333333,0.5]],dtype=float)
t1=Crystal(positions=t1p,numbers=np.array([13]*8+[29]*10+[3]*4),
           cell=np.array([4.94775,4.94775,14.14499,90,90,120],dtype=float)); t1.calculate_structure_factors(1.0)

def refpeaks(cr, zone):
    b=cr.generate_diffraction_pattern(zone_axis_lattice=np.array(zone),sigma_excitation_error=0.02)
    q=np.vstack([b.data["qx"],b.data["qy"]]).T; I=b.data["intensity"]
    g=np.hypot(q[:,0],q[:,1]); m=(g>0.15)&(g<0.68)
    return q[m], I[m], g[m]
alq,alI,alg = refpeaks(al,[0,0,1])
t1q,t1I,t1g = refpeaks(t1,[0,-4,1])
print(f"Al ref: {len(alq)} peaks in (0.15,0.68); |g| set: {sorted(set(np.round(alg,3)))}")
print(f"T1 ref: {len(t1q)} peaks; |g| set: {sorted(set(np.round(t1g,3)))}")
print(f"Al maxI={alI.max():.4f}  T1 maxI={t1I.max():.5f}  (ratio {alI.max()/t1I.max():.0f}x)\n")

K=0.04
def explain(exp, refq):
    # for each exp peak, nearest ref within K (best in-plane rotation search, since
    # the pattern's in-plane angle is free). Try 180 rotations, take best count.
    expI=np.array([p[2] for p in exp]); exp=np.array([[p[0],p[1]] for p in exp])
    best=None
    for deg in range(0,360,2):
        th=np.radians(deg); c,s=np.cos(th),np.sin(th)
        R=np.array([[c,-s],[s,c]])
        rq=refq@R.T
        n=0; Ie=0.0
        for k,e in enumerate(exp):
            dd=np.min(np.sum((rq-e)**2,axis=1))
            if dd<=K*K: n+=1; Ie+=expI[k]
        if best is None or (n,Ie)>(best[0],best[1]): best=(n,Ie,deg)
    return best  # matched count, matched exp-intensity, best angle

for lab,ids in [("T1_indexed",[p["i"] for p in P if p["truth"]==3 and p["verdict"]=="indexed"][:6]),
                ("T1_notIndexed",[p["i"] for p in P if p["truth"]==3 and p["verdict"]=="notIndexed"][:6])]:
    print(f"== {lab} ==  (exp peaks -> matched by each ref within {K} Å⁻¹, best in-plane angle)")
    for i in ids:
        exp=byi[i]["peaks"]; ne=len(exp)
        an,aI,ad=explain(exp,alq); tn,tI,td=explain(exp,t1q)
        print(f"  i={i:5d} nexp={ne}:  Al matches {an}/{ne} (I={aI:.0f})   T1 matches {tn}/{ne} (I={tI:.0f})")
