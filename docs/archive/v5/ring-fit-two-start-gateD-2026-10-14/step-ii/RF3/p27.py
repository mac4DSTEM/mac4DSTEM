import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
import lib, p12, os, math
for s in ['S4','S3','T','N','C','P']:
    for v3,vii in [('none','head'),('a','a'),('c','c')]:
        p=f'{p12.SPD}/{s}_{v3}.log'
        if not os.path.exists(p): continue
        R3=p12.parse(p)
        Rii={}
        for l in open(f'{lib.LOGS}/{s}_{vii}.log'):
            if l.startswith('ROW|'):
                r=lib.parse_line(l); Rii[r['name']]=r
        if len(R3)!=len(Rii): print(s,v3,'row count',len(R3),len(Rii)); continue
        mism=0; maxd=0
        for n,r in R3.items():
            q=Rii[n]
            if r.get('status')!=q.get('status'): mism+=1; continue
            if r['status']=='THREW': continue
            for k3,kii in [('dR','dR'),('dba','dba'),('fa','fa'),('fb','fb'),('resid','resid')]:
                d=abs(r[k3]-q[kii])/max(abs(q[kii]),1e-12)
                if d>1e-9: mism+=1; break
                maxd=max(maxd,d)
        print(f'{s} {v3} vs ii {vii}: {len(R3)} rows, mismatches (status or dR/dba/fa/fb/resid rel 1e-9): {mism}')
