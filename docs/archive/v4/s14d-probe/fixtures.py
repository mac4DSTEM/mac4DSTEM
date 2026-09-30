# S14-D fixtures with exact (F2) / by-construction (F1) truth. Writes out/fixt_<name>.f32 [n,250,250] and out/fixt_<name>.truth.txt (cx cy per pattern).
import numpy as np, h5py, os
from scipy.special import erfc
O=os.environ['SP']+'/s14d/out/'; N=250
rng=np.random.default_rng(20260930)
def f2(cx,cy,rho0,ring_amp=0.72,disk_a=3.0,disk_s=1.0,ring_s=1.5,peak=3000.0,bg=8.0):
    ss=4; o=(np.arange(ss)+0.5)/ss-0.5
    y=(np.arange(N)[:,None]+o[None,:]).reshape(-1); x=y.copy()
    Y,X=np.meshgrid(y,x,indexing='ij'); rho=np.hypot(X-cx,Y-cy)
    v=0.5*erfc((rho-disk_a)/(np.sqrt(2)*disk_s))+ring_amp*np.exp(-(rho-rho0)**2/(2*ring_s**2))
    v=v.reshape(N,ss,N,ss).mean((1,3))
    return peak*v+bg
offs=[-0.5,-0.25,0,0.25,0.5]
def write(name,pats,truth):
    np.asarray(pats,np.float32).tofile(O+f'fixt_{name}.f32'); np.savetxt(O+f'fixt_{name}.truth.txt',np.array(truth),fmt='%.6f')
    print(name,len(truth))
for rho0 in (6.0,8.5,10.0,12.0):
    cs=[(127.3+dx,127.6+dy) for dy in offs for dx in offs]
    clean=[f2(cx,cy,rho0) for cx,cy in cs]
    tag=str(rho0).replace('.','p')
    write(f'F2_rho{tag}',clean,cs)
    write(f'F2_rho{tag}_noisy',[rng.poisson(p).astype(float) for p in clean],cs)
cs=[(127.3+dx,127.6+dy) for dy in offs for dx in offs]
write('F2_diskonly',[f2(cx,cy,8.5,ring_amp=0.0) for cx,cy in cs],cs)
write('F2_diskonly_noisy',[rng.poisson(f2(cx,cy,8.5,ring_amp=0.0)).astype(float) for cx,cy in cs],cs)
# F1: real probe_template slices Fourier-shifted by known sub-pixel offsets; truth = own-slice bg-subtracted CoM + shift
f=h5py.File('/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/calibrationData_bullseyeProbe.h5','r')
pt=f['4DSTEM_experiment/data/diffractionslices/probe_template/data'][:].astype(float)
yy,xx=np.mgrid[:N,:N]; pats=[];tr=[]
for i in range(20):
    s=pt[:,:,i]; t=np.maximum(s-np.median(s),0); c0=((t*xx).sum()/t.sum(),(t*yy).sum()/t.sum())
    for k in range(3):
        sx,sy=rng.uniform(1.5,3.5),rng.uniform(1.5,3.5)   # shift into the sim's centre region (~127.3)
        F=np.fft.fft2(s); ky=np.fft.fftfreq(N)[:,None]; kx=np.fft.fftfreq(N)[None,:]
        sh=np.fft.ifft2(F*np.exp(-2j*np.pi*(kx*sx+ky*sy))).real
        pats.append(sh); tr.append((c0[0]+sx,c0[1]+sy))
write('F1_template',pats,tr)
