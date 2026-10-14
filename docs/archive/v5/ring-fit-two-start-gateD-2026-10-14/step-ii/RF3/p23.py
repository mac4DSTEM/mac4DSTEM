import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
D=load()
def bad(r): return accepted(r) and abs(r['dba'])>0.01
def good(r): return accepted(r) and abs(r['dba'])<=0.002   # "b/a within 0.002" 
print('Applied-quantity view (b/a is what reaches the correction): bad = accepted and |dba|>0.01')
print('var   bad  newlyBad(vs head)  rescued(head bad->not bad)  head-good(<=.002) lost(>0.002)  headgood->bad(>0.01)  threw  maxRegress(|dba|-|dba_head|)')
for v in ['head','a','c','b2','s','cb','cs','cbs']:
    nb=nl=res=gl=g2b=th=0; mx=0; mxn=''
    for s in SETS:
        for n,r in D[s][v].items():
            h=D[s]['head'][n]
            if not accepted(r): th+=1; continue
            if bad(r): nb+=1
            if accepted(h):
                if bad(r) and not bad(h): nl+=1
                if bad(h) and not bad(r): res+=1
                if good(h) and abs(r['dba'])>0.002: gl+=1
                if good(h) and bad(r): g2b+=1
                d=abs(r['dba'])-abs(h['dba'])
                if d>mx: mx=d; mxn=(s,n[:40])
    print(f'{v:5} {nb:4} {nl:8} {res:14} {gl:20} {g2b:16} {th:8} {mx:.3f} {mxn}')
