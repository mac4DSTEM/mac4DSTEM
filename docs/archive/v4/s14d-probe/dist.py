# S14-D step-1 DISTRIBUTION: per dataset the refine touches, the mean-DP radial structure vs the refine window
# (win = max(1.2 r, r+1.5), r = app probeSize r recorded in s14 grid-rerun.log). Strided sample (<=12x12), read-only.
import h5py, numpy as np, sys
from py4DSTEM.process.calibration import get_probe_size
R='/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/'; T=R+'training_dataset/'
sets=[('WS2',T+'polycrystal_2D_WS2.h5','4DSTEM/datacube/data',1.8584),
 ('SiSiGe_exp',T+'downsample_Si_SiGe_exp.h5','4DSTEM_experiment/data/datacubes/datacube_0/data',3.7383),
 ('Particle_1',T+'Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5','datacube_root/datacube/data',6.1229),
 ('simAu_poly',T+'sim_Au_data_all_binned.h5','4DSTEM_simulation/4DSTEM_polyAu/data',5.1173),
 ('simAu_nano',T+'sim_Au_data_all_binned.h5','4DSTEM_simulation/4DSTEM_AuNanoplatelet/data',5.1133),
 ('bullseye_polyAu',T+'calibrationData_bullseyeProbe.h5','4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data',6.8429),
 ('bullseye_sim',T+'calibrationData_bullseyeProbe.h5','4DSTEM_experiment/data/datacubes/simulation_4DSTEM/data',6.7815),
 ('SiSiGe_cal',T+'Si-SiGe_calibrated.h5','datacube_root/datacube/data',3.6933),
 ('Au_ref',T+'Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5','dm_dataset_root/dm_dataset/data',8.0556),
 ('AlMgSi_060',T+'Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5','dm_dataset_root/dm_dataset/data',2.5403),
 ('thronsenA',R+'thronsen-datasetA/datasetA_stride3.h5','Experiments/__unnamed__/data',2.8352),
 ('demo_cube',R+'demo-dataset/AlMgSi_demo.h5','4DSTEM_experiment/data/datacubes/datacube_0/data',2.9849)]
only=sys.argv[1:]
for lab,path,dset,r in sets:
    if only and lab not in only: continue
    with h5py.File(path,'r') as h:
        ds=h[dset]; ry,rx,qy,qx=ds.shape; sy=max(1,ry//12); sx=max(1,rx//12)
        smp=np.nan_to_num(ds[::sy,::sx].astype(np.float64)).reshape(-1,qy,qx)
    mean=smp.mean(0); rp,x0,y0=get_probe_size(mean)
    yy,xx=np.mgrid[:qy,:qx]; rad=np.hypot(xx-x0,yy-y0)
    step=0.5; nb=int(min(x0,y0,qx-x0,qy-y0)/step)
    prof=np.array([mean[(rad>=i*step)&(rad<(i+1)*step)].mean() for i in range(nb)])
    bg=np.median(mean); p=prof-bg; pk=p[:4].max()
    # gap = first local min after the profile has dropped, ring = next local max after that; require it > 2 % of peak
    i=int(np.argmax(p[:4])); 
    while i<nb-2 and not (p[i]<=p[i-1] and p[i]<=p[i+1] and i>2): i+=1
    gap=i*step+step/2
    j=i
    while j<nb-2 and not (p[j]>=p[j-1] and p[j]>=p[j+1] and j>i): j+=1
    ringpos=j*step+step/2; ringh=p[j]/pk; gaph=p[i]/pk
    win=max(1.2*r,r+1.5)
    rw=(rad<=win); mass_in=(np.maximum(mean-bg,0)*(rad<=r)).sum(); mass_ring=(np.maximum(mean-bg,0)*((rad>r)&(rad<=win))).sum(); mass_out=(np.maximum(mean-bg,0)*((rad>win)&(rad<=3*r))).sum()
    print(f"{lab:16s} q={qy}x{qx} n={len(smp):3d} r_app={r:.2f} r_py={rp:.2f} win={win:.2f} centre=({x0:.2f},{y0:.2f}) | first gap min at {gap:.1f}px ({gaph:+.2f} of peak), next max at {ringpos:.1f}px ({ringh:+.2f} of peak) | mass r<=r:{mass_in:.3g}  r..win:{mass_ring/mass_in:.3f}  win..3r:{mass_out/mass_in:.3f} (x core)")
