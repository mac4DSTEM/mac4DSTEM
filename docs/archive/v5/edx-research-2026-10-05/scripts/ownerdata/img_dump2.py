import h5py, json, numpy as np
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from ncempy.io import dm
G='<owner-backup>/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_170330/emd_files/'
def meta(ds,col=0):
    return json.loads(bytes(ds[:,col]).split(b'\x00')[0].decode('utf-8','replace'))
def haadf(p):
    with h5py.File(p,'r') as f:
        for u,g in f['Data/Image'].items():
            m=meta(g['Metadata'])
            if m['BinaryResult']['Detector']=='HAADF':
                a=g['Data'][:,:,0].astype('float32'); px=float(m['BinaryResult']['PixelSize']['width'])*1e9
                return a.T,px
V=[('0605 33kx','SI HAADF 1438 33000 x 20260605.emd'),('0605 65kx','SI HAADF 1509 65000 x 20260605.emd'),('0605 91kx','SI HAADF 1537 91000 x 20260605.emd'),('0512 91kx','SI HAADF 1623 91000 x 20260512.emd'),('0512 130kx','SI HAADF 1606 130 kx 20260512.emd'),('0605 23kx','SI HAADF 1402 23000 x 20260605.emd')]
S=[('ROI_1 055','<owner-backup>/00_inbox/4DSTEM_170330/ROI_1/raw/SI data (1)/055_STEM SI.dm4'),('ROI_2 056','<owner-backup>/00_inbox/4DSTEM_170330/ROI_2/raw/SI data (2)/056_STEM SI.dm4'),('ROI_3 057','<owner-backup>/00_inbox/4DSTEM_170330/ROI_3/raw/SI data (3)/057_STEM SI.dm4'),('ROI_4 058','<owner-backup>/00_inbox/4DSTEM_170330/ROI_4/raw/SI data (4)/058_STEM SI.dm4'),('ROI_5 060','<owner-backup>/00_inbox/4DSTEM_170330/ROI_5/raw/SI data (7)/060_STEM SI.dm4'),('ROI_4 ADF 0967','<owner-backup>/00_inbox/4DSTEM_170330/ROI_4/raw/Analytical (4)/ADF_0967.dm4')]
fig,ax=plt.subplots(2,6,figsize=(30,10))
for i,(lab,fn) in enumerate(V):
    a,px=haadf(G+fn); ax[0,i].imshow(a,cmap='gray'); ax[0,i].set_title(f'Velox HAADF {lab} {a.shape} {px:.2f}nm/px'); ax[0,i].axis('off')
for i,(lab,p) in enumerate(S):
    with dm.fileDM(p,on_memory=False) as f:
        d=f.getDataset(0); im=d['data']
        ax[1,i].imshow(im,cmap='gray'); ax[1,i].set_title(f"GMS {lab} {im.shape} {d['pixelSize'][0]:.4g}{d['pixelUnit'][0]}"); ax[1,i].axis('off')
plt.tight_layout(); plt.savefig('cmp_170330.png',dpi=40)
