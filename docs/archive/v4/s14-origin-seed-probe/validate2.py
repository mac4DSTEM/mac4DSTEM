import sys, re, numpy as np, h5py, importlib.util
sys.argv=['x','__none__']
spec=importlib.util.spec_from_file_location('twin','/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/tools/origin-fit-diagnostics/origin-kernel-twin.py')
tw=importlib.util.module_from_spec(spec); spec.loader.exec_module(tw)
S='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/b119bc6d-fd92-4a13-b081-be12f91a813f/scratchpad/s14/'
R='/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/'; T=R+'training_dataset/'
cubes=[('WS2',T+'polycrystal_2D_WS2.h5','4DSTEM/datacube/data'),
('SiSiGe_exp',T+'downsample_Si_SiGe_exp.h5','4DSTEM_experiment/data/datacubes/datacube_0/data'),
('Particle_1',T+'Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5','datacube_root/datacube/data'),
('simAu_poly',T+'sim_Au_data_all_binned.h5','4DSTEM_simulation/4DSTEM_polyAu/data'),
('simAu_nano',T+'sim_Au_data_all_binned.h5','4DSTEM_simulation/4DSTEM_AuNanoplatelet/data'),
('bullseye_polyAu',T+'calibrationData_bullseyeProbe.h5','4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data'),
('bullseye_sim',T+'calibrationData_bullseyeProbe.h5','4DSTEM_experiment/data/datacubes/simulation_4DSTEM/data'),
('SiSiGe_cal',T+'Si-SiGe_calibrated.h5','datacube_root/datacube/data'),
('Au_ref',T+'Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5','dm_dataset_root/dm_dataset/data'),
('AlMgSi_060',T+'Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5','dm_dataset_root/dm_dataset/data'),
('thronsenA',R+'thronsen-datasetA/datasetA_stride3.h5','Experiments/__unnamed__/data'),
('demo_cube',R+'demo-dataset/AlMgSi_demo.h5','4DSTEM_experiment/data/datacubes/datacube_0/data')]
def box_argmax(pat,hw,edge):
    if edge:
        pp=np.pad(pat,hw,mode='edge'); qy,qx=pat.shape
        ii=np.pad(np.cumsum(np.cumsum(pp,0),1),((1,0),(1,0)))
        ys=np.arange(qy)+hw; xs=np.arange(qx)+hw
        y0=ys-hw; y1=ys+hw+1; x0=xs-hw; x1=xs+hw+1
    else:
        qy,qx=pat.shape
        ii=np.pad(np.cumsum(np.cumsum(pat,0),1),((1,0),(1,0)))
        ys=np.arange(qy); xs=np.arange(qx)
        y0=np.clip(ys-hw,0,qy); y1=np.clip(ys+hw+1,0,qy); x0=np.clip(xs-hw,0,qx); x1=np.clip(xs+hw+1,0,qx)
    s=ii[y1][:,x1]-ii[y0][:,x1]-ii[y1][:,x0]+ii[y0][:,x0]
    iy,ix=np.unravel_index(np.argmax(s),s.shape); return float(ix),float(iy)
def load(f): return np.fromfile(S+'out/'+f,dtype=np.float32).reshape(-1,2)
for lab,fn,ds in cubes:
    log=open(S+f'logs/grid_{lab}.log').read()
    r=float(re.search(r'\br ([0-9.]+)\s+bin',log).group(1))
    with h5py.File(fn,'r') as h:
        d=h[ds]; ry,rx,qy,qx=d.shape; n=ry*rx
        idx=np.unique(np.linspace(0,n-1,60).astype(int))
        samp=np.array([np.nan_to_num(d[i//rx,i%rx].astype(np.float64)) for i in idx])
    win=max(1.2*r,r+1.5)
    hw1=max(1,int(round(r))); hw2=max(1,int(round(3**.5*r)))
    out=[lab,f'r={r}',f'n={len(idx)}']
    gs=load(lab+'.seed_g.f32')[idx]; g_ok=0
    for k,p in enumerate(samp):
        sx,sy=tw.py_seed(p,r)
        g_ok+= (sx==gs[k,0] and sy==gs[k,1])
    out.append(f'G==scipy {g_ok}')
    for tag,hw,edge,f in (('V1',hw1,False,'v1'),('V2',hw2,False,'v2'),('V1n',hw1,True,'v1n')):
        s=load(lab+f'.seed_{f}.f32')[idx]
        ok=sum(1 for k,p in enumerate(samp) if box_argmax(p,hw,edge)==(s[k,0],s[k,1]))
        out.append(f'{tag}==f64 {ok}')
    # GPU V0 vs twin NEW at app r
    v0=load(lab+'.meas_v0.f32')[idx]; mx=0; nbad=0
    for k,p in enumerate(samp):
        bx,by=tw.block_coarse(p,r); c=tw.com(p,bx,by,win,4)
        e=max(abs(c[0]-v0[k,0]),abs(c[1]-v0[k,1])); mx=max(mx,e); nbad+=e>1e-3
    out.append(f'V0-vs-twin max {mx:.1e} bad {nbad}')
    print(' | '.join(out),flush=True)
