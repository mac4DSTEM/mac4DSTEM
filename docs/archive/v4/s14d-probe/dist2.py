# S14-D step-1 DISTRIBUTION v2: profile aligned per pattern (twin WIDE = Gaussian seed + 4 passes of 3 r CoM), median over <=60 strided patterns.
import h5py, numpy as np, sys
from scipy.ndimage import gaussian_filter
exec(open('dist.py').read().split("only=sys.argv")[0])
def com(pat,cx,cy,win,passes):
    qy,qx=pat.shape; yy,xx=np.mgrid[0:qy,0:qx]; p=np.maximum(pat,0)
    for _ in range(passes):
        m=(xx-cx)**2+(yy-cy)**2<=win*win; s=p[m].sum()
        if not s>0: break
        nx=(p*xx)[m].sum()/s; ny=(p*yy)[m].sum()/s
        st=abs(nx-cx)<1e-4 and abs(ny-cy)<1e-4; cx,cy=nx,ny
        if st: break
    return cx,cy
only=sys.argv[1:]
for lab,path,dset,r in sets:
    if only and lab not in only: continue
    with h5py.File(path,'r') as h:
        ds=h[dset]; ry,rx,qy,qx=ds.shape; sy=max(1,ry//8); sx=max(1,rx//8)
        smp=np.nan_to_num(ds[::sy,::sx].astype(np.float64)).reshape(-1,qy,qx)
    yy,xx=np.mgrid[:qy,:qx]; profs=[]
    B=np.arange(0,int(3.5*r)+2)          # 1 px bins
    for pat in smp:
        iy,ix=np.unravel_index(np.argmax(gaussian_filter(pat,r,mode='nearest')),pat.shape)
        cx,cy=com(pat,float(ix),float(iy),3*r,4); rad=np.hypot(xx-cx,yy-cy)
        profs.append([pat[(rad>=b-.5)&(rad<b+.5)].mean() if ((rad>=b-.5)&(rad<b+.5)).any() else np.nan for b in B])
    P=np.nanmedian(np.array(profs),0); pk=np.nanmax(P[:int(np.ceil(r))+1]); p=P/pk   # raw, normalised by the core max (no bg subtraction)
    # ring prominence: over rho in [r, 3r], max of (p[k]-min(p[r0..k])) i.e. rise above the running minimum beyond the core edge
    k0=int(np.ceil(r)); rm=np.minimum.accumulate(p[k0:int(3*r)+1]); rise=(p[k0:int(3*r)+1]-rm).max(); at=k0+int(np.argmax(p[k0:int(3*r)+1]-rm))
    print(f"{lab:16s} n={len(smp):2d} r={r:.2f} win={max(1.2*r,r+1.5):.2f} rise above running min beyond core edge (of core max)={rise:+.2f} of peak at rho={at} | p(rho): "+" ".join(f"{v:.2f}" for v in p[:int(3*r)+2:1][:24]))
