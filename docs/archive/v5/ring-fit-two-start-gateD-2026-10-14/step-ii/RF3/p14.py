import sys,io,contextlib; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
with contextlib.redirect_stdout(io.StringIO()):
    from p2 import same
from lib import *
import math
from collections import Counter
D=load()
rows=[]
for s in SETS:
    for n,c in D[s]['c'].items():
        h=D[s]['head'][n]; a=D[s]['a'][n]
        if same(h,a): continue
        o = a if same(c,h) else h
        if not (accepted(c) and accepted(o)): 
            rows.append((s,n,c,o,'unacc')); continue
        dc,do=abs(c['dba']),abs(o['dba'])
        rc,ro=abs(c['dR']),abs(o['dR'])
        if rc>ro+1e-3 or dc>do+2e-3: rows.append((s,n,c,o,'farther'))
F=[r for r in rows if r[4]=='farther']
print('c farther than the other start (|dR|+1e-3 or |dba|+2e-3):',len(F),'| unacc pairs',sum(r[4]=='unacc' for r in rows))
def cl(r): 
    x=abs(r['dR']); return 'R' if x<=.001 else 'M' if x<=.01 else 'W'
cc=Counter((cl(c),cl(o)) for s,n,c,o,_ in F)
print('class(c),class(other):',dict(cc))
big=[(s,n,c,o) for s,n,c,o,_ in F if cl(c)=='W' and cl(o)!='W']
print('c wrong while the other start is within 1%:',len(big))
for s,n,c,o in big:
    print('  ',s,n[:50],f"c: dR={c['dR']:+.3f} dba={c['dba']:+.3f} dth={c['dth']:.3f} | other: dR={o['dR']:+.4f} dba={o['dba']:+.4f} dth={o['dth']:.3f} ({o['status']})")
bothW=[(s,n,c,o) for s,n,c,o,_ in F if cl(c)=='W' and cl(o)=='W']
print('both wrong, c farther:',len(bothW), ' extra |dba| (c - other): median %.3f max %.3f'%(sorted(abs(c['dba'])-abs(o['dba']) for s,n,c,o in bothW)[len(bothW)//2], max(abs(c['dba'])-abs(o['dba']) for s,n,c,o in bothW)))
mm=[(s,n,c,o) for s,n,c,o,_ in F if cl(c)!='W']
print('c within 1% but farther (R/M): ',len(mm),' max extra |dba| %.4f, max extra dth %.3f'%(max(abs(c['dba'])-abs(o['dba']) for s,n,c,o in mm), max(c['dth']-o['dth'] for s,n,c,o in mm)))
# how often does the lower cost == closer to truth overall, among differing pairs where the two fits differ materially (|dR diff|>1e-3 or |dba diff|>2e-3)?
mat=0; closer=0; farther=0
for s in SETS:
    for n,c in D[s]['c'].items():
        h=D[s]['head'][n]; a=D[s]['a'][n]
        if not (accepted(h) and accepted(a)) or same(h,a): continue
        if abs(abs(h['dR'])-abs(a['dR']))<=1e-3 and abs(abs(h['dba'])-abs(a['dba']))<=2e-3: continue
        mat+=1
        # which is closer to truth by |dR|
        best='head' if abs(h['dR'])<abs(a['dR']) else 'a'
        pick='head' if same(c,h) else 'a'
        closer+= (best==pick); farther+= (best!=pick)
print('materially different pairs (both accepted):',mat,' c picks closer-in-R',closer,' farther',farther)
