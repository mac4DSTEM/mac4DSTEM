# Refuter held-out check: fit the bullseye_sim truth plane on ODD-ODD scan positions (disjoint from the record's even-even
# sample), score the k2.0 / ship GPU measurements on the even-even positions and on all vacuum positions. Slices only.
import h5py, numpy as np, os
SP='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/b119bc6d-fd92-4a13-b081-be12f91a813f/scratchpad'
f=h5py.File('/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/calibrationData_bullseyeProbe.h5','r')
b='4DSTEM_experiment/data/'; d=f[b+'datacubes/simulation_4DSTEM/data']
tsum=f[b+'diffractionslices/probe_template/data'][:,:,0].astype(float).sum()
yy,xx=np.mgrid[:250,:250]; ring=np.hypot(xx-127,yy-127.5)<20
rec=[]
for i in range(1,100,2):
  for j in range(1,84,2):
    s=d[i,j].astype(float)
    if abs(s.sum()/tsum-1)>0.005: continue
    t=np.where(ring,s-np.median(s),0); S=t.sum(); rec.append((i,j,(t*xx).sum()/S,(t*yy).sum()/S))
r=np.array(rec); print("odd-odd vacuum-like positions",len(r),"of",50*42)
A=np.c_[np.ones(len(r)),r[:,0],r[:,1]]
cx,_,_,_=np.linalg.lstsq(A,r[:,2],rcond=None); cy,_,_,_=np.linalg.lstsq(A,r[:,3],rcond=None)
print("odd-odd plane x",np.round(cx,4),"y",np.round(cy,4))
ox,oy=np.load(SP+'/s14d/truth_sim_plane.npy'); print("record  plane x",np.round(ox,4),"y",np.round(oy,4))
I,J=np.mgrid[:100,:84]
px=(cx[0]+cx[1]*I+cx[2]*J); py=(cy[0]+cy[1]*I+cy[2]*J); qx=(ox[0]+ox[1]*I+ox[2]*J); qy=(oy[0]+oy[1]*I+oy[2]*J)
print("plane-vs-plane |diff| over the scan: median %.4f max %.4f px"%(np.median(np.hypot(px-qx,py-qy)),np.hypot(px-qx,py-qy).max()))
s=np.fromfile(SP+'/s14d/out/bullseye_sim.sum.f32',np.float32).astype(float); vac=np.abs(s/1033759.0-1)<0.005
ee=((I%2==0)&(J%2==0)).ravel(); oo=((I%2==1)&(J%2==1)).ravel()
for c in ('ship','k2.0','k1.75','G2.0'):
    m=np.fromfile(SP+f'/s14d/out/bullseye_sim.{c}.f32',np.float32).reshape(-1,2).astype(float)
    e_new=np.hypot(m[:,0]-px.ravel(),m[:,1]-py.ravel()); e_old=np.hypot(m[:,0]-qx.ravel(),m[:,1]-qy.ravel())
    print(f"{c:6s} vs odd-odd plane: even-even vac median {np.median(e_new[vac&ee]):.3f} p95 {np.percentile(e_new[vac&ee],95):.3f} | all vac median {np.median(e_new[vac]):.3f} p95 {np.percentile(e_new[vac],95):.3f}"
          f" || vs record plane: in-sample(ee) {np.median(e_old[vac&ee]):.3f}  out-of-sample(not ee) {np.median(e_old[vac&~ee]):.3f}")
