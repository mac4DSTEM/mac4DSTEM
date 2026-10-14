# RF3 own parser. Rows: ROW|k=v|k=v... ; errors/fallback text may contain '=' so split on first '=' only.
import os, math
SP='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad'
LOGS=SP+'/ii/logs'
SETS=['A','B','C','P','N','T','S3','S4']
VARS=['head','a','b','none','c','b2','s','cb','cs','cbs']
NUM=set('R ba_true sigma_true dR dba dth cerr resid cres cx cy fa fb fth I0 I1 s0 sin sout cbg'.split())
def parse_line(line):
    parts=line.rstrip('\n').split('|')
    assert parts[0]=='ROW'
    d={}
    for p in parts[1:]:
        k,_,v=p.partition('=')
        d[k]=float(v) if k in NUM else v
    return d
def load():
    D={}
    for s in SETS:
        D[s]={}
        for v in VARS:
            rows=[parse_line(l) for l in open(f'{LOGS}/{s}_{v}.log') if l.startswith('ROW|')]
            D[s][v]={r['name']:r for r in rows}
            assert len(rows)==len(D[s][v]), (s,v,'duplicate names')
    for s in SETS:
        base=set(D[s]['head'])
        for v in VARS: assert set(D[s][v])==base,(s,v,'name set differs')
    return D
def accepted(r): return r['status'] in ('profile','conic')
def wrong(r): return accepted(r) and abs(r['dR'])>0.01
def right(r): return accepted(r) and abs(r['dR'])<=0.001
def err(r): return (abs(r['dR']),abs(r['dba'])) if accepted(r) else (math.inf,math.inf)
