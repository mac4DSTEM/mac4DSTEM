import h5py, numpy as np, math
f=h5py.File('/Volumes/PL_SSD_2TB/4D_STEM_Datacubes/twisted_bilayer_graphene.hdf5','r')
d=f['ds']; ry,rx,qy,qx=d.shape
affordable=max(1,(64<<20)//(qy*qx*4)); total=ry*rx
step=math.ceil(math.sqrt(total/affordable)) if total>affordable else 1
print('stride',step,'affordable',affordable)
ys=range(0,ry,step); xs=range(0,rx,step)
img=np.zeros((len(ys),len(xs)),np.float32)
for i,y in enumerate(ys):
    for j,x in enumerate(xs):
        p=d[y,x].astype(np.float32)
        img[i,j]=np.float32(p.astype(np.float64).sum())
v=img.ravel()
print('shape',img.shape,'min',v.min(),'max',v.max(),'nonfinite',(~np.isfinite(v)).sum())
print('pct 1/50/99',np.percentile(v,[1,50,99]))
lo,hi=v.min(),v.max(); n=(v-lo)/(hi-lo)
print('hist of normalized (10 bins)',np.histogram(n,bins=10,range=(0,1))[0])
print('top5',np.sort(v)[-5:],'bottom5',np.sort(v)[:5])
print('argmax',np.unravel_index(img.argmax(),img.shape))
p=d[0,0]; print('pattern0 min/max/sum',p.min(),p.max(),p.sum())
print('ds min/max sampled', min(d[y,x].min() for y in ys for x in xs), max(d[y,x].max() for y in ys for x in xs))
