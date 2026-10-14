import sys,math,statistics as st
from collections import defaultdict, Counter
RUN='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3/runs3'
def parse(path):
    rows={}
    for l in open(path):
        if not l.startswith('ROW|'): continue
        d={}
        for p in l.rstrip('\n').split('|')[1:]:
            k,_,v=p.partition('='); d[k]=v
        rows[d['tag']]=d
    return rows
def fl(d,k):
    try: return float(d[k])
    except: return math.nan
def acc(r): return r.get('status') in ('profile','conic')
def ba(r): return fl(r,'b')/fl(r,'a')
def rad(r): return (fl(r,'a')+fl(r,'b'))/2
def th(r): return fl(r,'theta')
VARS=['head','none','c','b2','s','cbs']
tot=Counter()
if __name__=='__main__':
  pass
for src in ['au','s3','s4','s5']:
    V={v:parse(f'{RUN}/sweep-{src}-{v}.log') for v in VARS}
    base=defaultdict(list)
    for t in V['head']: base[t.split('~')[0]].append(t)
    print(f'===== {src}: {len(V["head"])} annuli, bases {len(base)}')
    print(f"{'base':10} n accHead accCbs | consensus b/a (n) | changed(cbs!=head by>0.005 in b/a or status) | closer/farther/equal to consensus | s-refusals of healthy head fits | b2-refusals")
    for b,ts in base.items():
        unchanged=[t for t in ts if acc(V['head'][t]) and acc(V['cbs'][t]) and V['head'][t].get('status')==V['cbs'][t].get('status') and abs(ba(V['head'][t])-ba(V['cbs'][t]))<=0.005 and abs(rad(V['head'][t])-rad(V['cbs'][t]))<0.05]
        if len(unchanged)<4: 
            print(f'{b:10} {len(ts):3d} headAcc {sum(acc(V["head"][t]) for t in ts):3d} cbsAcc {sum(acc(V["cbs"][t]) for t in ts):3d} | too few unchanged fits ({len(unchanged)}) for a consensus'); continue
        cons=st.median(ba(V['head'][t]) for t in unchanged)
        sp=max(ba(V['head'][t]) for t in unchanged)-min(ba(V['head'][t]) for t in unchanged)
        ch=[t for t in ts if (acc(V['head'][t]) and acc(V['cbs'][t]) and (V['head'][t].get('status')!=V['cbs'][t].get('status') or abs(ba(V['head'][t])-ba(V['cbs'][t]))>0.005)) or (acc(V['head'][t]) != acc(V['cbs'][t]))]
        closer=farther=eq=newthrow=lostthrow=0
        for t in ch:
            h,c=V['head'][t],V['cbs'][t]
            if acc(h) and not acc(c): newthrow+=1; continue
            if acc(c) and not acc(h): lostthrow+=1; continue
            dh,dc=abs(ba(h)-cons),abs(ba(c)-cons)
            if dc<dh-0.002: closer+=1
            elif dc>dh+0.002: farther+=1
            else: eq+=1
        # s refusals of healthy head fits: head within 0.01 of consensus and s output not profile
        healthy=[t for t in ts if acc(V['head'][t]) and V['head'][t].get('status')=='profile' and abs(ba(V['head'][t])-cons)<=0.01]
        sref=[t for t in healthy if V['s'][t].get('status')!='profile']
        bref=[t for t in healthy if V['b2'][t].get('status')!='profile']
        cmove=[t for t in ts if acc(V['head'][t]) and acc(V['c'][t]) and abs(ba(V['head'][t])-ba(V['c'][t]))>0.005]
        far=[t for t in ts if acc(V['cbs'][t]) and acc(V['head'][t]) and abs(ba(V['head'][t])-cons)<=0.01 and abs(ba(V['cbs'][t])-cons)>0.03]
        print(f"{b:10} {len(ts):3d} {sum(acc(V['head'][t]) for t in ts):3d} {sum(acc(V['cbs'][t]) for t in ts):3d} | cons {cons:.4f} spread(unchanged) {sp:.4f} ({len(unchanged)}) | changed {len(ch)} (newthrow {newthrow}) | closer {closer} farther {farther} eq {eq} | s-refused healthy {len(sref)}/{len(healthy)} | b2-refused healthy {len(bref)} | c moved>0.005: {len(cmove)} | cbs>0.03 off where head<=0.01: {len(far)}")
        tot['healthy']+=len(healthy); tot['sref']+=len(sref); tot['bref']+=len(bref); tot['closer']+=closer; tot['farther']+=farther; tot['eq']+=eq; tot['changed']+=len(ch); tot['n']+=len(ts); tot['cmove']+=len(cmove); tot['far']+=len(far); tot['newthrow']+=newthrow
print(dict(tot))
