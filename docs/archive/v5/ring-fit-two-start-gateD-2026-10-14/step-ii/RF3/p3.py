import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
from p2 import same
import math
D=load()
rows=[]
cnt=dict(total=0, headEqA=0, picked_head=0, picked_a=0, differ_pairs=0)
for s in SETS:
    for n,c in D[s]['c'].items():
        h=D[s]['head'][n]; a=D[s]['a'][n]
        cnt['total']+=1
        if same(h,a): cnt['headEqA']+=1; continue
        cnt['differ_pairs']+=1
        pick='head' if same(c,h) else 'a'
        cnt['picked_'+pick]+=1
        eh=err(h); ea=err(a); ec=err(c)
        other=a if pick=='head' else h
        eo=err(other)
        rows.append((s,n,pick,h,a,c,other))
print(cnt)
# worse-than-other: c's |dR| > other's |dR| + 1e-3 (abs) -- or b/a worse by > 2e-3
worse=[]
for s,n,pick,h,a,c,o in rows:
    dR_c,dR_o=abs(c['dR']) if accepted(c) else math.inf, abs(o['dR']) if accepted(o) else math.inf
    ba_c,ba_o=abs(c['dba']) if accepted(c) else math.inf, abs(o['dba']) if accepted(o) else math.inf
    if dR_c>dR_o+1e-3 or ba_c>ba_o+2e-3:
        worse.append((s,n,pick,c,o,dR_c,dR_o,ba_c,ba_o))
print('c picks the fit farther from truth (|dR| by >1e-3 or |dba| by >2e-3):',len(worse),'of',cnt['differ_pairs'],'differing pairs')
from collections import Counter
print(' by set:',Counter(w[0] for w in worse))
print(' by pick:',Counter(w[2] for w in worse))
def tag(n): return n.split('-')[0]
print(' by name-prefix:',Counter(tag(w[1]) for w in worse))
print()
print('set name pick  c:(status dR dba dth cost) | other:(status dR dba dth cost)')
for s,n,pick,c,o,dRc,dRo,bac,bao in sorted(worse,key=lambda w:-(w[8] if w[8]!=math.inf else 9) if False else -abs(w[7]-w[8]) if w[8]!=math.inf and w[7]!=math.inf else 0):
    def f(r): 
        return f"{r['status']} dR={r['dR']:+.4f} dba={r['dba']:+.4f} dth={r['dth']:.4f} res={r['resid']:.5f}" if accepted(r) else 'THREW'
    print(f'{s:3} {n[:60]:60} {pick:4} c: {f(c)} | o: {f(o)}')
