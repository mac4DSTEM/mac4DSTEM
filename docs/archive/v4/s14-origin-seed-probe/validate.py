import sys, numpy as np, h5py, importlib.util
sys.argv=['x','__none__']
spec=importlib.util.spec_from_file_location('twin','/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/tools/origin-fit-diagnostics/origin-kernel-twin.py')
tw=importlib.util.module_from_spec(spec); spec.loader.exec_module(tw)
SP='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/b119bc6d-fd92-4a13-b081-be12f91a813f/scratchpad/s14/out/'
D='/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/'
cubes=[('SiSiGe_exp','downsample_Si_SiGe_exp.h5','4DSTEM_experiment/data/datacubes/datacube_0/data',3.645,3.7383),
       ('Particle_1','Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5','datacube_root/datacube/data',5.577,6.1229)]
def box_argmax(pat,hw):
    qy,qx=pat.shape
    ii=np.pad(np.cumsum(np.cumsum(pat,0),1),((1,0),(1,0)))
    ys=np.arange(qy); xs=np.arange(qx)
    y0=np.clip(ys-hw,0,qy); y1=np.clip(ys+hw+1,0,qy); x0=np.clip(xs-hw,0,qx); x1=np.clip(xs+hw+1,0,qx)
    s=ii[y1][:,x1]-ii[y0][:,x1]-ii[y1][:,x0]+ii[y0][:,x0]
    iy,ix=np.unravel_index(np.argmax(s),s.shape); return float(ix),float(iy)
def load(f): return np.fromfile(SP+f,dtype=np.float32).reshape(-1,2)
for lab,fn,ds,r_twin,r_app in cubes:
    with h5py.File(D+fn,'r') as h:
        d=h[ds]; ry,rx,qy,qx=d.shape; sy=max(1,ry//12); sx=max(1,rx//12)
        idx=[(iy*rx+ix) for iy in range(0,ry,sy) for ix in range(0,rx,sx)]
        samp=np.nan_to_num(d[::sy,::sx].astype(np.float64)).reshape(-1,qy,qx)
    print('==',lab,'sample',len(idx))
    for rr,name in ((r_twin,'twin r'),(r_app,'app r')):
        win=max(1.2*rr,rr+1.5)
        old=[];new=[];py=[]
        for p in samp:
            bx,by=tw.block_coarse(p,rr); old.append(tw.com(p,bx,by,1.2*rr,1)); new.append(tw.com(p,bx,by,win,4))
            px,pyy=tw.py_seed(p,rr); py.append(tw.com(p,px,pyy,1.2*rr,1))
        old,new,py=map(np.array,(old,new,py))
        e=lambda a,b:np.hypot(*(a-b).T)
        print(f' [{name} {rr}] >1px of PY: OLD euclid {(e(old,py)>1).sum()}/{len(idx)}  NEW euclid {(e(new,py)>1).sum()}  OLD per-axis {(np.abs(old-py).max(1)>1).sum()}  NEW per-axis {(np.abs(new-py).max(1)>1).sum()}')
        if name=='app r': NEW=new
    # B: GPU V0 vs twin NEW at app r
    v0=load(lab+'.meas_v0.f32')[idx]; dv=np.abs(v0-NEW).max(1)
    print(f' B: GPU V0 vs twin NEW(app r): max {dv.max():.2e}  n>1e-3: {(dv>1e-3).sum()}  median {np.median(dv):.2e}')
    # C: G seed vs scipy, G refined vs twin
    gs=load(lab+'.seed_g.f32')[idx]; gm=load(lab+'.meas_g.f32')[idx]
    win=max(1.2*r_app,r_app+1.5); ex=0; gref=[]
    for k,p in enumerate(samp):
        sx_,sy_=tw.py_seed(p,r_app); gref.append(tw.com(p,sx_,sy_,win,4))
        if (sx_,sy_)!=(gs[k,0],gs[k,1]): ex+=1
    gref=np.array(gref); dg=np.abs(gm-gref).max(1)
    print(f' C: G seed == scipy on {len(idx)-ex}/{len(idx)}; G refined vs twin refine of scipy seed: max {dg.max():.2e} n>1e-3 {(dg>1e-3).sum()}')
    # D: box seeds vs float64 box argmax
    for k,hw in ((1,max(1,int(round(r_app)))),(2,max(1,int(round(3**.5*r_app))))):
        s=load(lab+f'.seed_v{k}.f32')[idx]
        ref=np.array([box_argmax(p,hw) for p in samp])
        agree=(np.abs(s-ref).max(1)==0).sum()
        print(f' D: V{k} (hw {hw}) seed == float64 clipped-box argmax on {agree}/{len(idx)}')
