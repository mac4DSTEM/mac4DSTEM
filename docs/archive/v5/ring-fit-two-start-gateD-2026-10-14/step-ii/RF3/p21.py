import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
print('theta: accepted fits with ellipticity >= 1 % (ba_true<=0.99) and dth > 0.1 rad / > 0.3 rad; median dth (rad)')
for v in ['head','a','c','b2','s','cbs']:
    c1=c3=n=0; ds=[]
    for s in SETS:
        for nm,r in D[s][v].items():
            if not accepted(r) or r['ba_true']>0.9905: continue
            n+=1; ds.append(r['dth']); c1+=r['dth']>0.1; c3+=r['dth']>0.3
    ds.sort()
    print(f'{v:5} n={n} dth>0.1: {c1} dth>0.3: {c3} median {ds[len(ds)//2]:.4f} p90 {ds[int(.9*len(ds))]:.3f}')
