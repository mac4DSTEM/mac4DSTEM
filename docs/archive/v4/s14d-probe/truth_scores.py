import numpy as np, os
SP=os.environ['SP']; O=SP+'/s14d/out/'
cx,cy=np.load(SP+'/s14d/truth_sim_plane.npy')
ry,rx=100,84; I,J=np.mgrid[:ry,:rx]
tx=(cx[0]+cx[1]*I+cx[2]*J).ravel(); ty=(cy[0]+cy[1]*I+cy[2]*J).ravel()
s=np.fromfile(O+'bullseye_sim.sum.f32',np.float32).astype(float)
vac=np.abs(s/1033759.0-1)<0.005; print("vacuum-like positions",vac.sum(),"of",len(s))
cands=['ship','k1.5','k1.75','k2.0','k2.5','k3.0','p1','py1','p10','p30','G1.2','G2.0','G3.0']
lines=[]
print(f"{'cand':6s} {'median':>7s} {'p95':>7s} {'max':>7s}  |err vs truth plane| px, vacuum positions;  all-position |meas - truth plane| median")
for c in cands:
    m=np.fromfile(O+f'bullseye_sim.{c}.f32',np.float32).reshape(-1,2).astype(float)
    e=np.hypot(m[:,0]-tx,m[:,1]-ty); ev=e[vac]
    print(f"{c:6s} {np.median(ev):7.3f} {np.percentile(ev,95):7.3f} {ev.max():7.3f}   all-pos median {np.median(e):7.3f}")
# proxies for polyAu: mean-DP probe centre (126.98,127.48) and WIDE (G3.0) mean vs candidates' scan-mean fitted origins are in the CAND lines
