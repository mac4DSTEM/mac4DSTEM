import numpy as np, os, glob, re
SP=os.environ['SP']; O=SP+'/s14d/out/'; rows=[]
for f in sorted(glob.glob(SP+'/s14d/logs/rhoq_*.log')):
    for l in open(f):
        if l.startswith('   RHOQMETA'):
            _,lab,qy,qx,r,x0,y0=l.split(); qy,qx=int(qy),int(qx); r,x0,y0=float(r),float(x0),float(y0)
            m=np.fromfile(O+f'{lab}.meandp.f32',np.float32).reshape(qy,qx).astype(float)
            yy,xx=np.mgrid[:qy,:qx]; rad=np.hypot(xx-x0,yy-y0); t=np.maximum(m-np.median(m),0)
            sel=rad<=3*r; order=np.argsort(rad[sel]); cs=np.cumsum(t[sel][order]); tot=cs[-1]; rs=rad[sel][order]
            rq=[rs[np.searchsorted(cs,q*tot)] for q in (0.90,0.95,0.98,0.99)]
            rows.append((lab,r,max(1.2*r,r+1.5),rq))
print(f"{'cube':16s} {'r':>5s} {'win_ship':>8s} | rho_q for q=0.90 0.95 0.98 0.99  | rho_q/r")
for lab,r,w,rq in rows: print(f"{lab:16s} {r:5.2f} {w:8.2f} | "+" ".join(f"{x:6.2f}" for x in rq)+" | "+" ".join(f"{x/r:4.2f}" for x in rq))
