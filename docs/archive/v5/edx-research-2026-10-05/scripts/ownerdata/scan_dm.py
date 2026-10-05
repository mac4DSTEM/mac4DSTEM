import sys, json, os, datetime, re, time
from ncempy.io import dm
files=[l.rstrip('\n') for l in open('find_ext.txt') if l.strip().lower().endswith('.dm4')]
extra=[l.rstrip('\n') for l in open('dm_extra.txt')] if os.path.exists('dm_extra.txt') else []
root='<owner-ssd>/'
out=open('dm_scan.jsonl','w')
KEEP=re.compile(r'(ImageList\.\d+\.(Name|ImageTags\.(Microscope Info|Acquisition|Meta Data|DataBar|Session Info|Camera|SI|Spectrum|EELS|EDS|STEM|Calibration|Detector|Experiment|Device|Sample|Acquisition Parameters).*)|ImageList\.\d+\.ImageData\.(Dimensions|DataType|PixelDepth|Calibrations\.(Dimension|Brightness).*))')
SKIP=re.compile(r'(Display|Brightness|CLUT|Thumbnail|ROI|Annotation|Histogram)',re.I)
for rel in files+extra:
    p=rel if rel.startswith('/') else root+rel[2:]
    rec={'path':rel}
    try:
        st=os.stat(p); rec['size']=st.st_size; rec['mtime']=datetime.datetime.fromtimestamp(st.st_mtime).isoformat(timespec='minutes')
        with dm.fileDM(p,on_memory=False) as f:
            rec['n']=f.numObjects
            off=0; objs=[]
            for i in range(f.numObjects):
                nd=int(f.dataShape[i])
                objs.append(dict(nd=nd,dt=int(f.dataType[i]),scale=[float(x) for x in f.scale[off:off+nd]],units=[str(u) for u in f.scaleUnit[off:off+nd]]))
                off+=nd
            rec['objs']=objs
            tags={}
            for k,v in f.allTags.items():
                if KEEP.search(k) and not SKIP.search(k):
                    s=str(v)
                    if len(s)>120: s=s[:120]
                    tags[k]=s
            rec['tags']=tags
    except Exception as ex:
        rec['error']=type(ex).__name__+': '+str(ex)[:150]
    out.write(json.dumps(rec)+'\n'); out.flush()
print('done')
