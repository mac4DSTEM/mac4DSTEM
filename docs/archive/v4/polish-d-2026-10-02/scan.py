import h5py, numpy as np
A=h5py.File('/Volumes/PL_SSD_2TB/4D_STEM_Datacubes/twisted_bilayer_graphene.hdf5','r')['ds'][...]
ry,rx,qy,qx=A.shape
yy,xx=np.mgrid[0:qy,0:qx].astype(np.float32)
hits=[]
for cy in [64,62,61,63]:
  for cx in [64,61,62,63]:
    for R in range(24,41):
      m=((xx-cx)**2+(yy-cy)**2<R*R)
      vi=np.tensordot(A,m.astype(np.float64),axes=([2,3],[0,1]))
      lo,hi=vi.min(),vi.max()
      s='%.4g-%.4g'%(lo,hi)
      if s=='0.9955-0.9994': hits.append((cy,cx,R,'full'))
      for p in [(0.5,99.5),(1,99),(0.1,99.9),(2,98)]:
        a,b=np.percentile(vi,p)
        if '%.4g-%.4g'%(a,b)=='0.9955-0.9994': hits.append((cy,cx,R,p))
      if cy==64 and cx==64: print(R,s)
print('hits',hits)
