import h5py, numpy as np
A=h5py.File('/Volumes/PL_SSD_2TB/4D_STEM_Datacubes/twisted_bilayer_graphene.hdf5','r')['ds'][...].astype(np.float32).astype(np.float64)
qy,qx=A.shape[2:]
yy,xx=np.mgrid[0:qy,0:qx].astype(np.float32); r2=(xx-qx/2)**2+(yy-qy/2)**2
for rin in [0,1,2,3,4,5]:
  for rout in [31,32,33]:
    m=(r2>rin*rin)&(r2<rout*rout)
    vi=np.tensordot(A,m.astype(np.float64),axes=([2,3],[0,1]))
    print('in %d out %d  min %.4g max %.4g'%(rin,rout,vi.min(),vi.max()))
