import sys, math, statistics as st
def load(f):
    D = {}
    for l in open(f):
        if not l.startswith('ROW|'): continue
        rec = {}
        for kv in l.strip().split('|')[1:]:
            k, _, v = kv.partition('=')
            try: rec[k] = float(v)
            except ValueError: rec[k] = v
        D[rec['name']] = rec
    return D
def accepted_profile(r): return r.get('status') == 'profile'
def wrong(r, thr): return accepted_profile(r) and abs(r['dR']) > thr
def sbound(r): return min(r['sin'], r['sout'])
def fmt(x, n=3): return ('%.'+str(n)+'g') % x
def summarize(D, label):
    n = len(D)
    prof = [r for r in D.values() if accepted_profile(r)]
    conic = [r for r in D.values() if r.get('status') == 'conic']
    thrw = [r for r in D.values() if r.get('status') == 'THREW']
    print('== %s: %d plants; profile %d, conic fallback %d, threw %d' % (label, n, len(prof), len(conic), len(thrw)))
    for thr in (0.1, 0.01, 0.005, 0.001):
        w = [r for r in prof if abs(r['dR']) > thr]
        print('   accepted profile fits with |d(a+b)/2 / R| > %g%%: %d' % (thr*100, len(w)))
    return prof
def wrong_detail(D, thr=0.01, show=True):
    W = [r for r in D.values() if wrong(r, thr)]
    if not W: print('   (none wrong at %g%%)' % (thr*100)); return W
    # I1 below a tenth of its start (start I1 = annulus dynamic range)
    a = [r for r in W if r['I1']/r['dyn'] < 0.1]
    b = [r for r in W if sbound(r) <= 0.30]
    both = [r for r in W if r['I1']/r['dyn'] < 0.1 or sbound(r) <= 0.30]
    print('   wrong>%g%%: %d; I1<0.1*start: %d; min ring sigma <=0.30: %d; either: %d' % (thr*100, len(W), len(a), len(b), len(both)))
    ratio_t = [r['cost_fit']/r['cost_truthfit'] for r in W]
    ratio_a = [r['cost_fit']/r['cost_truth'] for r in W]
    print('   cost(fit)/cost(truth, amplitudes fitted): min %s median %s max %s; >=1.2x: %d of %d' % (fmt(min(ratio_t)), fmt(st.median(ratio_t)), fmt(max(ratio_t)), sum(x>=1.2 for x in ratio_t), len(W)))
    print('   cost(fit)/cost(truth analytic, macTEM def):         min %s median %s max %s; >=1.2x: %d of %d' % (fmt(min(ratio_a)), fmt(st.median(ratio_a)), fmt(max(ratio_a)), sum(x>=1.2 for x in ratio_a), len(W)))
    print('   |dR/R|: max %s%%; |d(b/a)| max %s, median %s; dtheta (eps>0) max %s rad; centre err max %s px' % (fmt(100*max(abs(r['dR']) for r in W)), fmt(max(abs(r['dba']) for r in W)), fmt(st.median(abs(r['dba']) for r in W)), fmt(max([r['dtheta'] for r in W if r['eps']>0] or [0])), fmt(max(r['cerr'] for r in W))))
    # fits costing no more than truth
    cheap = [r for r in W if r['cost_fit'] <= r['cost_truthfit']*1.0]
    print('   wrong fits costing <= the true ring model (fitted amplitudes): %d' % len(cheap))
    if show:
        for r in sorted(W, key=lambda r: -abs(r['dR'])):
            print('     %-46s dR %+8.3f%% ba_err %+7.4f dth %6.3f cerr %6.3f I1/start %6.3f sin %6.3f sout %6.3f cost x%5.2f (x%5.2f analytic) seed dR %+6.3f%%' % (r['name'], 100*r['dR'], r['dba'], r['dtheta'], r['cerr'], r['I1']/r['dyn'], r['sin'], r['sout'], r['cost_fit']/r['cost_truthfit'], r['cost_fit']/r['cost_truth'], 100*r.get('seed_dR', float('nan'))))
    return W
if __name__ == '__main__':
    for f in sys.argv[1:]:
        D = load(f)
        summarize(D, f)
        wrong_detail(D, 0.01)
