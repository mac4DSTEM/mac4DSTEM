import h5py, json, sys, numpy as np, datetime
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from ncempy.io import dm
root='<owner-backup>/01_projects/GRK_LMW_LPBF_AlMgSi/'
def meta(ds,col=0):
    raw=bytes(ds[:,col]).split(b'\x00')[0]; return json.loads(raw.decode('utf-8','replace'))
def velox_haadf(p):
    with h5py.File(p,'r') as f:
        out=[]
        for u,g in f['Data/Image'].items():
            m=meta(g['Metadata'])
            det=m['BinaryResult']['Detector']
            if det=='HAADF':
                a=g['Data'][:,:,0].astype('float32')
                px=float(m['BinaryResult']['PixelSize']['width'])*1e9
                out.append((a,px,m['Optics'].get('FullScanFieldOfView',{}).get('x')))
        return out
files=[('190330_65kx','CA_DA_190330/emd_files/SI HAADF 1006 65000 x 20260603.emd'),
       ('190330_91kx','CA_DA_190330/emd_files/SI HAADF 1038 91000 x 20260603.emd'),
       ('190330_130kx','CA_DA_190330/emd_files/SI HAADF 1122 130 kx 20260603.emd')]
fig,ax=plt.subplots(2,2,figsize=(16,10)); ax=ax.ravel()
for i,(lab,rel) in enumerate(files):
    ims=velox_haadf(root+rel)
    a,px,fov=ims[0]
    print(lab,a.shape,'px nm',px,'fov',fov, 'n haadf',len(ims))
    ax[i].imshow(a.T,cmap='gray'); ax[i].set_title(f'{lab} {a.shape} {px:.2f} nm/px'); ax[i].axis('off')
# 4D survey
p=root+'CA_DA_190330/4DSTEM_190330/Workspace 1/051_STEM SI.dm4'
with dm.fileDM(p,on_memory=False) as f:
    d=f.getDataset(0)
    im=d['data']; print('dm survey',im.shape,d['pixelSize'],d['pixelUnit'])
    ax[3].imshow(im,cmap='gray'); ax[3].set_title(f"4D-STEM 051 ADF survey {im.shape} {d['pixelSize'][0]:.4g} {d['pixelUnit'][0]}")
    ax[3].axis('off')
    # scan rect
plt.tight_layout(); plt.savefig('cmp_190330.png',dpi=55)
