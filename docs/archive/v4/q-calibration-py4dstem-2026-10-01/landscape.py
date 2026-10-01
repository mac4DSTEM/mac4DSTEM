import sys, numpy as np, warnings; warnings.filterwarnings("ignore")
for n,v in [("float_",np.float64),("int_",np.int64),("bool_",np.bool_),("object_",np.object_),("str_",np.str_),("complex_",np.complex128)]:
    if not hasattr(np,n): setattr(np,n,v)
sys.path.insert(0,"/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/py4DSTEM-dev")
from py4DSTEM.process.diffraction import Crystal
from py4DSTEM.process.diffraction.utils import calc_1D_profile
al=Crystal([[0,0,0],[0.5,0.5,0],[0.5,0,0.5],[0,0.5,0.5]],[13]*4,4.05); al.calculate_structure_factors(2.0)
g=al.g_vec_leng; I=al.struct_factors_int; hkl=al.hkl.T
zone=[i for i in range(len(g)) if hkl[i][2]==0 and g[i]>0]
# experimental histogram exactly as calculate_bragg_peak_histogram: k grid 0..k_max, linear bins, int * k^1, normalised
for kb in [0.002,0.02]:
    k_step=0.002; k=np.arange(0,2.0+k_step,k_step)
    # data at true scale (pixel size right): qr = g, weights |F|^2
    def hist(qr,w):
        kp=(qr-0)/k_step; kf=np.floor(kp).astype(int); dk=kp-kf; n=len(k); h=np.zeros(n)
        s=(kf>=0)&(kf<n); h+=np.bincount(kf[s],weights=(1-dk[s])*w[s],minlength=n)
        s=(kp>=-1)&(kp<n-1); h+=np.bincount(kf[s]+1,weights=dk[s]*w[s],minlength=n); return h
    ie=hist(g[zone],I[zone]); ie=ie*k; ie/=ie.max()
    rows=[]
    for s in np.arange(0.60,1.60,0.002):
        m=calc_1D_profile(k,g*s,I,k_broadening=kb,int_scale=np.array([1.0]),normalize_intensity=False)
        a=(m@ie)/(m@m) if m@m>0 else 0   # best single int_scale
        rows.append((s,np.sum((ie-a*m)**2)))
    rows=np.array(rows)
    # local minima
    r=rows[:,1]; mins=[i for i in range(1,len(r)-1) if r[i]<r[i-1] and r[i]<r[i+1]]
    print(f"k_broadening={kb}: SSE at s=1: {r[np.argmin(abs(rows[:,0]-1))]:.4f}; local minima (scale, SSE) sorted by SSE:")
    for i in sorted(mins,key=lambda i:r[i])[:8]: print(f"   s={rows[i,0]:.3f}  SSE={r[i]:.4f}")
