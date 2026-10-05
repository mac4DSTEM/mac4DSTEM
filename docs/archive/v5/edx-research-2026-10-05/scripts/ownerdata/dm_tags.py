import sys, json, time
from ncempy.io import dm
p=sys.argv[1]
t=time.time()
with dm.fileDM(p, on_memory=False) as f:
    tags=f.allTags
    ks=list(tags.keys())
    print(len(ks),'tags in',round(time.time()-t,2),'s')
    pat=sys.argv[2:] 
    for k in ks:
        if not pat or any(x.lower() in k.lower() for x in pat):
            v=tags[k]
            s=str(v)
            print(k,'=',s[:160])
