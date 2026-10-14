import h5py, numpy as np, sys
f=h5py.File(sys.argv[1],'r'); d=f['dm_dataset_root/dm_dataset/data']
acc=np.zeros((64,64),np.float64); n=0
for i in range(0,d.shape[0],16):
    blk=d[i:i+16].astype(np.float64); acc+=blk.sum(axis=(0,1)); n+=blk.shape[0]*blk.shape[1]
m=acc/n
m.astype('<f4').tofile('au_mean.f32')
print('n',n,'min',m.min(),'max',m.max(),'nonfinite',(~np.isfinite(m)).sum())
# centre: CoM of top pixels
yy,xx=np.mgrid[0:64,0:64]
w=np.where(m>np.percentile(m,99),m,0); cy=(w*yy).sum()/w.sum(); cx=(w*xx).sum()/w.sum()
print('centre(row,col)',cy,cx)
r=np.hypot(yy-cy,xx-cx); 
for k in range(0,46):
    s=(r>=k)&(r<k+1)
    if s.any(): print(k, '%.4g'%m[s].mean(), s.sum())
for k in ['Q_pixel_size','Q_pixel_units','R_pixel_size','QR_flip']:
    print(k, f['dm_dataset_root/metadatabundle/calibration/'+k][()])
