import sys,os,math
SPD='/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3/logs'
NUM=set('R ba_true sigma_true gap seed_dR seed_dba seed_a seed_b seed_res dR dba depart fa fb resid cres I1 sin sout'.split())
def parse(path):
    rows={}
    for l in open(path):
        if not l.startswith('ROW|'): continue
        d={}
        for p in l.rstrip('\n').split('|')[1:]:
            k,_,v=p.partition('=')
            if k in NUM:
                try: d[k]=float(v)
                except: d[k]=math.nan
            else: d[k]=v
        rows[d['name']]=d
    return rows
def q(a,p):
    a=sorted(a); return a[min(len(a)-1,int(p*len(a)))] if a else math.nan
if __name__=='__main__':
    sets=sys.argv[1:] or ['S4','S3']
    for s in sets:
        V={}
        for v in ['none','a','c']:
            p=f'{SPD}/{s}_{v}.log'
            if os.path.exists(p): V[v]=parse(p)
        if not V: continue
        n0=len(V['none'])
        print(f'===== {s}: rows none={n0}', {v:len(r) for v,r in V.items()})
        # seed bias
        sb=[abs(r['seed_dR']) for r in V['none'].values() if r.get('seed')=='ok']
        sba=[abs(r['seed_dba']) for r in V['none'].values() if r.get('seed')=='ok']
        print(f' conic-seed |dR| : n={len(sb)} p50 {q(sb,.5):.4f} p90 {q(sb,.9):.4f} p99 {q(sb,.99):.4f} max {max(sb):.4f}; |dba| p50 {q(sba,.5):.4f} p90 {q(sba,.9):.4f} max {max(sba):.4f}')
        for v,rows in V.items():
            right_dep=[(abs(r['depart']),n) for n,r in rows.items() if r.get('status')=='profile' and abs(r['dR'])<=0.001]
            mid_dep=[(abs(r['depart']),n) for n,r in rows.items() if r.get('status')=='profile' and 0.001<abs(r['dR'])<=0.01]
            wr_dep=[(abs(r['depart']),n) for n,r in rows.items() if r.get('status')=='profile' and abs(r['dR'])>0.01]
            dd=lambda L:[x[0] for x in L]
            print(f' {v:4}: right profile fits {len(right_dep)}: |depart| p50 {q(dd(right_dep),.5):.4f} p99 {q(dd(right_dep),.99):.4f} max {max(dd(right_dep)) if right_dep else math.nan:.4f}  >.05:{sum(x>.05 for x in dd(right_dep))} >.06:{sum(x>.06 for x in dd(right_dep))} >.08:{sum(x>.08 for x in dd(right_dep))} | mid {len(mid_dep)} max {max(dd(mid_dep)) if mid_dep else math.nan:.4f} >.08:{sum(x>.08 for x in dd(mid_dep))} | wrong {len(wr_dep)}: >.08: {sum(x>.08 for x in dd(wr_dep))}, in (.05,.08]: {sum(.05<x<=.08 for x in dd(wr_dep))}')
