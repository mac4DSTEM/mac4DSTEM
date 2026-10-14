import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
D=load()
print('rows per set:',{s:len(D[s]['head']) for s in SETS}, 'total',sum(len(D[s]['head']) for s in SETS))
hdr='set   var   n  wrong  right  rightLost newlyWrong threw newThrew |dba|>0.01  conic profile'
print(hdr)
tot={v:dict(n=0,wrong=0,right=0,lost=0,newly=0,threw=0,newthrew=0,ba=0,conic=0,prof=0) for v in VARS}
for s in SETS+['ALL']:
    for v in VARS:
        if s=='ALL':
            t=tot[v]
        else:
            t=dict(n=0,wrong=0,right=0,lost=0,newly=0,threw=0,newthrew=0,ba=0,conic=0,prof=0)
            for name,r in D[s][v].items():
                h=D[s]['head'][name]
                t['n']+=1; t['wrong']+=wrong(r); t['right']+=right(r)
                t['lost']+= right(h) and not right(r)
                t['newly']+= (not wrong(h)) and wrong(r)
                t['threw']+= r['status']=='THREW'
                t['newthrew']+= r['status']=='THREW' and h['status']!='THREW'
                t['ba']+= accepted(r) and abs(r['dba'])>0.01
                t['conic']+= r['status']=='conic'; t['prof']+= r['status']=='profile'
            for k in t: tot[v][k]+=t[k]
        print(f"{s:4} {v:5} {t['n']:4} {t['wrong']:5} {t['right']:5} {t['lost']:7} {t['newly']:9} {t['threw']:5} {t['newthrew']:8} {t['ba']:9} {t['conic']:6} {t['prof']:6}")
    print()
