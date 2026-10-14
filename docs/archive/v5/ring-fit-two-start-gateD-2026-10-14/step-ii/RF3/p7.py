import sys,math,re
SP='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad'
RUNS=SP+'/cubes/runs2'
SRC=['au','s1','s2','s3','s4','s5']
VAR=['head','none','c','b2','s','cb','cs','cbs']
def parse(path):
    rows={}; order=[]
    for l in open(path):
        if not l.startswith('ROW|'): continue
        d={}
        for p in l.rstrip('\n').split('|')[1:]:
            k,_,v=p.partition('=')
            d[k]=v
        order.append(d['tag']); rows[d['tag']]=d
    return rows,order
def fl(d,k): 
    try: return float(d[k])
    except: return math.nan
def ba(d): return fl(d,'b')/fl(d,'a')
def rad(d): return (fl(d,'a')+fl(d,'b'))/2
def srad(d): return (fl(d,'seed_a')+fl(d,'seed_b'))/2
def sba(d): return fl(d,'seed_b')/fl(d,'seed_a')
def depart(d): return rad(d)/srad(d)-1
R={}
for s in SRC:
    R[s]={}
    for v in VAR:
        R[s][v]=parse(f'{RUNS}/{s}-{v}.log')
if __name__=='__main__':
    for s in SRC:
        rows,order=R[s]['head']
        print('=====',s,'annuli',len(order))
        print(f"{'tag':8} {'status':8} {'rad':>8} {'b/a':>7} {'theta':>6} seedrad seed_b/a depart  flags  | variants differing from head (status, rad, b/a, depart)")
        for t in order:
            h=rows[t]
            st=h.get('status')
            if st=='profile':
                flags=[]
                if fl(h,'I1')==0: flags.append('I1=0')
                if min(fl(h,'sin'),fl(h,'sout'))<=0.30: flags.append('sig<=.3')
                if max(fl(h,'sin'),fl(h,'sout'))>=0.99*max(2,2*fl(h,'outer')): flags.append('sigCeil')
                if fl(h,'s0')<=0.26: flags.append('s0floor')
                inn,out=fl(h,'inner'),fl(h,'outer')
                if not (inn<=rad(h)<=out): flags.append('outside')
                print(f"{t:8} {st:8} {rad(h):8.3f} {ba(h):7.4f} {fl(h,'theta'):6.3f} {srad(h):8.3f} {sba(h):7.4f} {depart(h):+7.3f} {','.join(flags)}")
            elif st=='conic':
                print(f"{t:8} {st:8} {rad(h):8.3f} {ba(h):7.4f} {fl(h,'theta'):6.3f} {srad(h):8.3f} {sba(h):7.4f}  fallback: {h.get('reason','')[:50]}")
            else:
                print(f"{t:8} {st:8} {h.get('err','')[:70]}  seed_b/a={sba(h) if 'seed_a' in h else 'n/a'}")
            for v in ['none','c','b2','s','cb','cs','cbs']:
                x=R[s][v][0][t]
                diff = (x.get('status')!=h.get('status')) or any(x.get(k)!=h.get(k) for k in ('a','b','theta'))
                if diff:
                    if x.get('status') in ('profile','conic'):
                        print(f"      {v:4}: {x['status']:7} rad={rad(x):8.3f} b/a={ba(x):7.4f} theta={fl(x,'theta'):6.3f} depart={depart(x):+.3f} {x.get('reason','')[:60]}")
                    else:
                        print(f"      {v:4}: THREW {x.get('err','')[:70]}")
