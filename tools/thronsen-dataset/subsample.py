"""tools/thronsen-dataset/subsample.py — stream Thronsen et al.'s datasetA
(Zenodo 10.5281/zenodo.6645396, CC BY 4.0, 7.4 GB float32) by HTTP range
requests and write every STRIDE-th scan row and column as uint16 in the
HyperSpy layout H5Reader finds. One pattern per chunk: a per-position read
then decompresses 32 kB, not a 44 MB chunk (the first cut of this file made
the probe run for 43 minutes without finishing). About 50 minutes at 5 MB/s.

usage: subsample.py <out.h5> [stride=3]
"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rangefile import RangeFile
import h5py, numpy as np, io, time, os
STRIDE=int(sys.argv[2]) if len(sys.argv)>2 else 3
base="https://zenodo.org/api/records/6645396/files/"
import sys
out=sys.argv[1]
os.makedirs(os.path.dirname(out), exist_ok=True)
f=RangeFile(base+"datasetA_preprocessed.hspy/content", block=16*1024*1024)
t0=time.time()
with h5py.File(io.BufferedReader(f),"r") as h:
    ds=h["Experiments"]["Dataset A"]["data"]
    ny,nx,qy,qx=ds.shape
    rows=list(range(0,ny,STRIDE)); cols=list(range(0,nx,STRIDE))
    with h5py.File(out,"w") as o:
        g=o.create_group("Experiments").create_group("__unnamed__")
        od=g.create_dataset("data",(len(rows),len(cols),qy,qx),dtype=np.uint16,chunks=(1,1,qy,qx),compression="gzip",compression_opts=1)
        for i,(name,scale,offset,size,units,nav) in enumerate([("y",2.4943*STRIDE,0.0,len(rows),"nm",True),("x",2.4943*STRIDE,0.0,len(cols),"nm",True),("ky",0.01904,-1.2138,qy,"$A^{-1}$",False),("kx",0.01904,-1.2138,qx,"$A^{-1}$",False)]):
            a=g.create_group(f"axis-{i}"); a.attrs.update({"_type":"UniformDataAxis","name":name,"scale":scale,"offset":offset,"size":size,"units":units,"navigate":nav})
        o.attrs["source"]="Thronsen et al. 2024, Zenodo 10.5281/zenodo.6645396 datasetA_preprocessed.hspy (CC BY 4.0), every 3rd scan row and column, intensities x65535 as uint16"
        for cy in range(0,ny,32):
            block=ds[cy:cy+32]
            sel_r=[r-cy for r in rows if cy<=r<cy+32]
            sub=block[sel_r][:,cols]
            oi=rows.index(cy+sel_r[0])
            od[oi:oi+len(sel_r)]=np.clip(np.round(sub*65535),0,65535).astype(np.uint16)
            o.flush()
            print(f"rows {cy}-{cy+31}: wrote {len(sel_r)} sample rows; fetched {f.bytes_fetched/1e9:.2f} GB; {time.time()-t0:.0f} s", flush=True)
print("DONE", out, os.path.getsize(out)/1e9, "GB", time.time()-t0, "s")
