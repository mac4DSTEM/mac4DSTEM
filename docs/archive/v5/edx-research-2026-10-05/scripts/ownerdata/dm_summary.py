import json,re,sys
R=[json.loads(l) for l in open('dm_scan.jsonl')]
def parse(r):
    t=r['tags']; D={}
    names={}; dt={}; cal={}
    for k,v in t.items():
        m=re.search(r'ImageList\.(\d+)\.ImageData\.Dimensions\.(\d+)$',k)
        if m: D.setdefault(int(m.group(1)),{})[int(m.group(2))]=int(float(v))
        m=re.search(r'ImageList\.(\d+)\.Name$',k)
        if m: names[int(m.group(1))]=v
        m=re.search(r'ImageList\.(\d+)\.ImageData\.DataType$',k)
        if m: dt[int(m.group(1))]=int(float(v))
        m=re.search(r'ImageList\.(\d+)\.ImageData\.Calibrations\.Dimension\.(\d+)\.(Scale|Units)$',k)
        if m: cal.setdefault(int(m.group(1)),{}).setdefault(int(m.group(2)),{})[m.group(3)]=v
    dims={i:[d[j] for j in sorted(d)] for i,d in D.items()}
    return dims,names,dt,cal
def tag(r,idx,key):
    for k,v in r['tags'].items():
        if re.search(r'ImageList\.%d\.ImageTags\.%s$'%(idx,re.escape(key)),k): return v
    return None
if __name__=='__main__':
    for r in sorted(R,key=lambda r:r['path']):
        dims,names,dt,cal=parse(r)
        nd=max([len(v) for v in dims.values()] or [0])
        if nd<3 and r['size']<50e6: continue
        print(f"## {r['size']/1e6:.0f} MB {r['mtime']} {r['path']}")
        for i in sorted(dims):
            print('   obj',i,names.get(i),dims[i],'dt',dt.get(i), [(c.get('Scale','')[:7],c.get('Units')) for j,c in sorted(cal.get(i,{}).items())])
