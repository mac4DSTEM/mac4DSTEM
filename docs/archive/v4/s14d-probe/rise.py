# ringed-probe warning quantity on the MEAN DP (what the app has): rise of the radial profile above its running minimum beyond the core edge, fraction of core max
import numpy as np, os, glob
SP=os.environ['SP']; O=SP+'/s14d/out/'
print(f"{'cube':16s} {'r':>5s} {'rise':>6s} {'at rho':>6s}  (mean DP about the app probe centre, 1-px bins, median bg removed)")
for f in sorted(glob.glob(SP+'/s14d/logs/rhoq_*.log')):
    for l in open(f):
        if l.startswith('   RHOQMETA'):
            _,lab,qy,qx,r,x0,y0=l.split(); qy,qx=int(qy),int(qx); r,x0,y0=float(r),float(x0),float(y0)
            m=np.fromfile(O+f'{lab}.meandp.f32',np.float32).reshape(qy,qx).astype(float); m=m-np.median(m)
            yy,xx=np.mgrid[:qy,:qx]; rad=np.hypot(xx-x0,yy-y0)
            B=np.arange(0,int(3*r)+2); P=np.array([m[(rad>=b-.5)&(rad<b+.5)].mean() if ((rad>=b-.5)&(rad<b+.5)).any() else np.nan for b in B])
            pk=np.nanmax(P[:int(np.ceil(r))+1]); p=P/pk; k0=int(np.ceil(r)); seg=p[k0:int(3*r)+1]; rm=np.minimum.accumulate(seg); rise=np.nanmax(seg-rm)
            print(f"{lab:16s} {r:5.2f} {rise:6.2f} {k0+int(np.nanargmax(seg-rm)):6d}")
