# Cross-vendor registration probe: Velox HAADF 18:41 vs GMS 051 ADF survey (190330, 2026-06-03). Read-only.
import h5py, json, numpy as np
from ncempy.io import dm
from scipy import ndimage
V='<owner-backup>/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/emd_files/STEM HAADF 1841 28500 x 20260603.emd'
G='<owner-backup>/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/4DSTEM_190330/Workspace 1/051_STEM SI.dm4'
import glob, os
if not os.path.exists(G):
    c = glob.glob('<owner-backup>/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/4DSTEM_190330/**/051_STEM SI.dm4', recursive=True); G = c[0]
with h5py.File(V,'r') as f:
    for u,g in f['Data/Image'].items():
        m=json.loads(bytes(g['Metadata'][:,0]).split(b'\x00')[0].decode())
        if m['BinaryResult']['Detector']=='HAADF':
            a=g['Data'][:,:,0].astype('float32').T; vpx=float(m['BinaryResult']['PixelSize']['width'])*1e9
            vrot=float(m['Scan'].get('ScanRotation',0)); break
with dm.fileDM(G,on_memory=False) as f:
    for i in range(f.numObjects-1):
        d=f.getDataset(i); im=d['data']
        if im.ndim==2: b=im.astype('float32'); gpx=d['pixelSize'][0]; gu=d['pixelUnit'][0]; break
gpx_nm = gpx*1000 if gu in ('µm','um') else gpx
print('Velox', a.shape, f'{vpx:.3f} nm/px, ScanRotation {vrot:.4f} rad; GMS survey', b.shape, f'{gpx_nm:.3f} nm/px ({gu})')
T=4.0
A=ndimage.zoom(a, vpx/T, order=1); B=ndimage.zoom(b, gpx_nm/T, order=1)
def prep(x):
    x=ndimage.gaussian_filter(x,1.0); x=x-ndimage.gaussian_filter(x,25); return (x-x.mean())/(x.std()+1e-9)
A=prep(A); B=prep(B)
n=max(A.shape+B.shape); n=int(2**np.ceil(np.log2(n)))
def pad(x):
    y=np.zeros((n,n),'float32'); y[:x.shape[0],:x.shape[1]]=x*np.outer(np.hanning(x.shape[0]),np.hanning(x.shape[1])); return y
FA=np.fft.fft2(pad(A))
res=[]
for flip in (False,True):
    for ang in np.arange(-180,180,2.0):
        Bt=ndimage.rotate(B[:, ::-1] if flip else B, ang, reshape=True, order=1)
        F=FA*np.conj(np.fft.fft2(pad(Bt))); F/=np.abs(F)+1e-6
        c=np.fft.ifft2(F).real; res.append((c.max()/c.std(), flip, ang, np.unravel_index(c.argmax(),c.shape)))
res.sort(key=lambda r:-r[0])
for r in res[:6]: print(f'peak/std {r[0]:.1f} flip {r[1]} rot {r[2]:+.0f} deg shift {r[3]}')
print('median peak/std over all trials', np.median([r[0] for r in res]).round(1))
print('--- refine around flip=True rot=+90')
best=[]
Bf=B[:, ::-1]
for s in (0.96,0.98,1.0,1.02,1.04):
    Bs=ndimage.zoom(Bf, s, order=1)
    for ang in np.arange(86,94.01,0.5):
        Bt=ndimage.rotate(Bs, ang, reshape=True, order=1)
        F=FA*np.conj(np.fft.fft2(pad(Bt))); F/=np.abs(F)+1e-6
        c=np.fft.ifft2(F).real; best.append((c.max()/c.std(), s, ang))
best.sort(key=lambda r:-r[0])
for r in best[:5]: print(f'peak/std {r[0]:.1f} scale {r[1]} rot {r[2]:+.1f}')
