import collections, json, os
D='/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/docs/archive/v5/ring-fit-two-start-gateD-2026-10-14/step-ii/runs/logs'
SETS=['A','B','C','P','N','T','S3','S4']
PL=lambda s:('pl'+s if s in ('S3','S4') else s)
def load(p):
    d={}
    for l in open(p):
        if l.startswith('ROW|'):
            kv=dict(q.split('=',1) for q in l.strip().split('|')[1:] if '=' in q); d[kv['name']]=kv
    return d
def cls(r):
    if r['status']=='THREW': return 'T'
    x=abs(float(r['dR'])); return 'R' if x<=0.001 else ('M' if x<=0.01 else 'W')
def ba(r): return abs(float(r['dba'])) if r['status']!='THREW' else 0.0
# reproduction of committed cb
rep=0; n=0
for s in SETS:
    a=[l for l in open(f'logs/{PL(s)}-cb.log') if l.startswith('ROW|')]
    b=[l for l in open(f'{D}/{s}_cb.log') if l.startswith('ROW|')]
    n+=len(a); rep+=sum(1 for x,y in zip(a,b) if x==y)+0*abs(len(a)-len(b))
    if len(a)!=len(b): print('len mismatch',s,len(a),len(b))
print('cb rows byte-identical to committed:',rep,'of',n)
def tab(v):
    tot=collections.Counter(); 
    for s in SETS:
        H=load(f'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/ii/logs/{s}_head.log'); V=load(f'logs/{PL(s)}-{v}.log')
        for k,h in H.items():
            r=V[k]; cr,ch=cls(r),cls(h); tot['n']+=1
            tot['wrong']+=cr=='W'; tot['right']+=cr=='R'; tot['lost']+=(ch=='R' and cr!='R'); tot['ba']+=ba(r)>0.01; tot['throw']+=cr=='T'
    return tot
for v in ('cb','cbg'): print(v,dict(tab(v)))
# rows that differ cb vs cbg
for s in SETS:
    A=load(f'logs/{PL(s)}-cb.log'); B=load(f'logs/{PL(s)}-cbg.log')
    H=load(f'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/ii/logs/{s}_head.log')
    for k in A:
        if A[k]!=B[k]:
            a,b=A[k],B[k]
            print('DIFF',s,k,'cb:',a['status'],a.get('dR'),a.get('dba'),'| cbg:',b['status'],b.get('dR'),b.get('dba'),b.get('err','')[:60],b.get('fallback','')[:50],'| class',cls(a),cls(b),'head',cls(H[k]))
