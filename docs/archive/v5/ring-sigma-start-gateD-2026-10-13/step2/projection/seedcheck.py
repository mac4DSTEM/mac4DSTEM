# In-sample check of a seed-consistency rule on HEAD rows: flag an accepted profile fit whose mean radius moved
# more than 5 % from the conic seed's. Counts flagged among wrong (>1 %) and right (<=0.1 %) profile fits.
import sys
def load(f):
    for line in open(f):
        if line.startswith('ROW|'):
            yield dict(p.split('=',1) for p in line.strip().split('|')[1:] if '=' in p)
W=F=R=FR=0
for f in sys.argv[1:]:
    w=fl=r=fr=0
    for h in load(f):
        if h.get('status')!='profile' or 'seed_dR' not in h: continue
        dR=float(h['dR']); sd=float(h['seed_dR']); moved=abs((1+dR)/(1+sd)-1)>0.05
        if abs(dR)>0.01: w+=1; fl+=moved
        elif abs(dR)<=0.001: r+=1; fr+=moved
    print(f.split('/')[-1], 'wrong', w, 'flagged', fl, '| right', r, 'flagged', fr); W+=w;F+=fl;R+=r;FR+=fr
print('TOTAL wrong',W,'flagged',F,'| right',R,'flagged',FR)
