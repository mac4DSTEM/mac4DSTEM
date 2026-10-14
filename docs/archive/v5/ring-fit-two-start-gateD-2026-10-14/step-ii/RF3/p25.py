import sys,io,contextlib; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
with contextlib.redirect_stdout(io.StringIO()):
    from p2 import same
from lib import *
D=load()
ok=bad=tie=skip=0; badl=[]
for s in SETS:
    for n,c in D[s]['c'].items():
        h=D[s]['head'][n]; a=D[s]['a'][n]
        if h['status']!='profile' or a['status']!='profile' or same(h,a): skip+=1; continue
        lo = 'head' if h['resid']<a['resid'] else ('a' if a['resid']<h['resid'] else 'tie')
        pick='head' if same(c,h) else ('a' if same(c,a) else '?')
        if lo=='tie': tie+=1
        elif lo==pick: ok+=1
        else: bad+=1; badl.append((s,n,lo,pick,h['resid'],a['resid']))
print('c = lower-resid of the two profile fits where both profile & different:',ok,'agree;',bad,'disagree;',tie,'exact ties; skipped (not both profile / identical)',skip)
print(badl[:10])
# near ties: |resid diff| relative < 1e-6
near=0
for s in SETS:
    for n,c in D[s]['c'].items():
        h=D[s]['head'][n]; a=D[s]['a'][n]
        if h['status']=='profile' and a['status']=='profile' and not same(h,a) and abs(h['resid']-a['resid'])<1e-6*h['resid']: near+=1
print('near-ties (relative resid diff <1e-6, fits differ):',near)
print()
for tol in (1e-6,1e-4,1e-3,1e-2):
    n_close=0; n_mat=0; n_farther=0
    for s in SETS:
        for n,c in D[s]['c'].items():
            h=D[s]['head'][n]; a=D[s]['a'][n]
            if h['status']!='profile' or a['status']!='profile' or same(h,a): continue
            if abs(h['resid']-a['resid'])>=tol*min(h['resid'],a['resid']): continue
            n_close+=1
            if abs(abs(h['dR'])-abs(a['dR']))>1e-3 or abs(abs(h['dba'])-abs(a['dba']))>2e-3:
                n_mat+=1
                pick='head' if same(c,h) else 'a'
                bestR='head' if abs(h['dR'])<abs(a['dR']) else 'a'
                n_farther+= pick!=bestR
    print(f'cost within {tol:g} relative: {n_close} pairs differ; {n_mat} materially (R 1e-3 / b/a 2e-3); c picks the farther one in {n_farther}')
