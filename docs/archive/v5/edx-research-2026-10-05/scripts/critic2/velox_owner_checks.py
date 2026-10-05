# Header/small-slice reads only: per-frame scan-transform terms, HAADF frame registration (4x binned),
# zero-peak fraction of the stored summed spectrum, optics state. 2026-10-05, critic2.
import h5py, json, sys, numpy as np
def md(ds,j): return json.loads(ds[:,j].tobytes().split(b'\x00')[0])
def flat(d,p=''):
    o={}
    if isinstance(d,dict):
        for k,v in d.items(): o.update(flat(v,p+k+'.'))
    elif isinstance(d,list):
        for i,v in enumerate(d): o.update(flat(v,p+str(i)+'.'))
    else: o[p[:-1]]=d
    return o
def xc(a,b):
    a=a-a.mean(); b=b-b.mean(); c=np.fft.ifft2(np.fft.fft2(a)*np.conj(np.fft.fft2(b))).real
    i=np.unravel_index(np.argmax(c),c.shape); return [int(x if x<n//2 else x-n) for x,n in zip(i,c.shape)]
def binr(x,k=4):
    h,w=(x.shape[0]//k)*k,(x.shape[1]//k)*k; return x[:h,:w].reshape(h//k,k,w//k,k).mean((1,3))
for path in sys.argv[1:]:
    print("=====", path.split('/')[-1])
    with h5py.File(path,'r') as f:
        for u in f['Data/Image']:
            g=f['Data/Image'][u]; d=g['Data']; M=g['Metadata']
            a=flat(md(M,0))
            keys=['Optics.SpotIndex','Optics.BeamConvergence','Optics.Apertures.Aperture-1.Diameter','Optics.ScreenCurrent','Optics.ProbeMode','Stage.AlphaTilt','BinaryResult.Detector']
            print(' image',d.shape,{k:a.get(k) for k in keys})
            if d.shape[2]<2: continue
            n=d.shape[2]; idx=sorted(set(list(range(0,n,max(1,n//8)))+[n-1]))
            fr={j:binr(d[:,:,j].astype(float)) for j in idx}; ref=sum(fr.values())/len(fr)
            for j in idx:
                c=flat(md(M,j)); A13=c.get('CustomProperties.Scan.ScanTransformation.A13.value'); A23=c.get('CustomProperties.Scan.ScanTransformation.A23.value')
                print(f'  frame {j}: A13={A13} A23={A23} xc_vs_mean_4xbin={xc(ref,fr[j])} Live/Real(det5)={c.get("Detectors.Detector-5.LiveTime")}/{c.get("Detectors.Detector-5.RealTime")}')
        if 'Spectrum' in f['Data']:
            for u in f['Data/Spectrum']:
                g=f['Data/Spectrum'][u]; y=g['Data'][:,0].astype(float); m=md(g['Metadata'],0)
                det=[v for v in m['Detectors'].values() if 'Dispersion' in v][0]
                E=float(det['OffsetEnergy'])+float(det['Dispersion'])*np.arange(len(y)); t=y.sum()
                print(f'  summed spectrum total={t:.0f} zero-peak(|E|<=150 eV)={100*y[np.abs(E)<=150].sum()/t:.2f}%')
                break
