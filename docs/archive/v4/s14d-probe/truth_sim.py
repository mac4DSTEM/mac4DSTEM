# S14-D truth for bullseye_sim: the sim's own descan ramp, measured on VACUUM-like patterns (sum within 0.5 % of the
# probe_template sum) by the bg-subtracted full-frame (r<20 about the mean-DP centre) centre of mass -- no windowed refine involved.
import h5py, numpy as np, sys
f=h5py.File('/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/calibrationData_bullseyeProbe.h5','r')
b='4DSTEM_experiment/data/'
d=f[b+'datacubes/simulation_4DSTEM/data']
tsum=f[b+'diffractionslices/probe_template/data'][:,:,0].astype(float).sum()
yy,xx=np.mgrid[:250,:250]; ring=np.hypot(xx-127,yy-127.5)<20
rec=[]
for i in range(0,100,2):
  for j in range(0,84,2):
    s=d[i,j].astype(float)
    if abs(s.sum()/tsum-1)>0.005: continue
    t=np.where(ring,s-np.median(s),0); S=t.sum()
    rec.append((i,j,(t*xx).sum()/S,(t*yy).sum()/S))
r=np.array(rec); print("vacuum-like positions",len(r),"of 2100 sampled")
A=np.c_[np.ones(len(r)),r[:,0],r[:,1]]
for k,n in ((2,'x'),(3,'y')):
    c,res,_,_=np.linalg.lstsq(A,r[:,k],rcond=None); rr=r[:,k]-A@c
    print(n,"plane coef (const, d/di(rx-index), d/dj)",np.round(c,4),"resid sd",rr.std().round(4),"max",np.abs(rr).max().round(3))
    if n=='x': cx=c
    else: cy=c
# scan-mean of the plane over the full scan (i in 0..99, j in 0..83)
I,J=np.mgrid[0:100,0:84]
print("truth plane scan mean (x,y):",(cx[0]+cx[1]*I+cx[2]*J).mean().round(3),(cy[0]+cy[1]*I+cy[2]*J).mean().round(3))
np.save('/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/b119bc6d-fd92-4a13-b081-be12f91a813f/scratchpad/s14d/truth_sim_plane.npy',np.array([cx,cy]))
