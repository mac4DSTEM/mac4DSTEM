#!/usr/bin/env python3
"""Lane M compare: P3 / R2 / P4 / P6 for the ring-fit Gate D, step 2 (2026-10-14).
usage: compare.py <logdir>      (reads <variant>_<set>.log for variant in head,a,b,ab and set in A,B)
Definitions (all on dR = (a+b)/2/R_true - 1, a fraction; printed as %):
  profile  = fitBestAvailable returned the profile model;  conic = it fell back to the conic;  THREW = it threw.
  right    = accepted profile fit with |dR| <= 0.1 %
  mid      = accepted profile fit with 0.1 % < |dR| <= 1 %
  wrong    = accepted profile fit with |dR| > 1 %            (step 1's definition)
  rescued  = (R2) a head-wrong plant that the variant returns as an accepted profile fit with |dR| <= 1 %
"""
import sys, os, math

VARS = ['head', 'a', 'b', 'ab']
SETS = ['A', 'B']
RIGHT, WRONG = 0.001, 0.01
CHANGE_TOL = 1e-4   # 0.01 % of R, for the printed tiers


def load(path):
    D = {}
    for line in open(path):
        if not line.startswith('ROW|'):
            continue
        rec = {}
        for kv in line.rstrip('\n').split('|')[1:]:
            k, _, v = kv.partition('=')
            try:
                rec[k] = float(v)
            except ValueError:
                rec[k] = v
        D[rec['name']] = rec
    return D


def status(r): return r.get('status', '?')
def isprof(r): return status(r) == 'profile'
def isconic(r): return status(r) == 'conic'
def threw(r): return status(r) == 'THREW'
def dR(r): return r.get('dR')
def right(r): return isprof(r) and abs(r['dR']) <= RIGHT
def mid(r): return isprof(r) and RIGHT < abs(r['dR']) <= WRONG
def wrong(r): return isprof(r) and abs(r['dR']) > WRONG
def within1(r): return isprof(r) and abs(r['dR']) <= WRONG
def pct(x): return '%+.4f%%' % (100 * x)
def f3(x): return '%.3g' % x
def minsig(r): return min(r['sin'], r['sout']) if isprof(r) and 'sin' in r else float('nan')


def desc(r):
    """One-token description of a result: status and dR."""
    if threw(r): return 'THREW'
    s = status(r)
    return '%s %s' % (s, pct(r['dR']))


def tier_names(D, tier):
    return sorted(n for n, r in D.items() if r['tier'] == tier)


def angle_err(a, b):
    raw = abs(a - b) % math.pi
    return min(raw, math.pi - raw)


def max_or(xs, default=0.0):
    xs = list(xs)
    return max(xs) if xs else default


def noisy_block(D, label):
    names = tier_names(D, 'noisy')
    prof = [D[n] for n in names if isprof(D[n])]
    con = [D[n] for n in names if isconic(D[n])]
    thr = [D[n] for n in names if threw(D[n])]
    W = [r for r in prof if wrong(r)]
    print('  %-5s noisy %d: accepted profile %d | conic fallback %d | threw %d' % (label, len(names), len(prof), len(con), len(thr)))
    print('        profile: right (<=0.1%%) %d, mid (0.1-1%%) %d, wrong (>1%%) %d' % (
        sum(right(r) for r in prof), sum(mid(r) for r in prof), len(W)))
    if W:
        print('        wrong: max|dR| %.4g%%, max|d(b/a)| %.4g, max dtheta(eps>0) %.4g rad, max centre err %.4g px' % (
            100 * max(abs(r['dR']) for r in W), max(abs(r['dba']) for r in W),
            max_or(r['dtheta'] for r in W if r['eps'] > 0), max(r['cerr'] for r in W)))
    else:
        print('        wrong: none')
    if con:
        print('        conic fallbacks: |dR|>1%%: %d, max|dR| %.4g%%, max|d(b/a)| %.4g, max dtheta(eps>0) %.4g rad, max centre err %.4g px' % (
            sum(abs(r['dR']) > WRONG for r in con), 100 * max(abs(r['dR']) for r in con), max(abs(r['dba']) for r in con),
            max_or(r['dtheta'] for r in con if r['eps'] > 0), max(r['cerr'] for r in con)))
        reasons = {}
        for r in con:
            k = r.get('fallback', '?')
            k = 'ring-width floor (b)' if 'floor' in k else ('residual over cap' if 'residual' in k else k)
            reasons[k] = reasons.get(k, 0) + 1
        print('        conic fallback reasons: ' + ', '.join('%s %d' % kv for kv in sorted(reasons.items())))
    for r in thr:
        print('        THREW: %s %s' % (r['name'], r.get('err', '')))
    return W


def transitions(Dh, Dv, tier):
    names = tier_names(Dh, tier)
    cnt = {}
    for n in names:
        k = (status(Dh[n]), status(Dv[n]))
        cnt[k] = cnt.get(k, 0) + 1
    return ', '.join('%s->%s %d' % (k[0], k[1], v) for k, v in sorted(cnt.items()))


def wrong_row(r):
    return ('%-44s dR %+9.4f%%  d(b/a) %+7.4f  dtheta %6.3f%s  cerr %7.3f  sin %6.3f sout %6.3f  I1/dyn %6.3f  I1 %9.4g  cost/truthfit %5.2f  noise %g gap %g' % (
        r['name'], 100 * r['dR'], r['dba'], r['dtheta'], '' if r['eps'] > 0 else '(eps0)', r['cerr'], r['sin'], r['sout'],
        r['I1'] / r['dyn'], r['I1'], r['cost_fit'] / r['cost_truthfit'], r['noise'], r['gap']))


def r2_table(Dh, Dv, vlabel):
    Wn = [n for n in tier_names(Dh, 'noisy') if wrong(Dh[n])]
    cls = {'right (profile <=0.1%)': [], 'mid (profile 0.1-1%)': [], 'conic within 1%': [], 'conic >1%': [],
           'threw': [], 'still wrong (profile >1%)': []}
    for n in Wn:
        v = Dv[n]
        if right(v): cls['right (profile <=0.1%)'].append(n)
        elif mid(v): cls['mid (profile 0.1-1%)'].append(n)
        elif isconic(v): cls['conic within 1%' if abs(v['dR']) <= WRONG else 'conic >1%'].append(n)
        elif threw(v): cls['threw'].append(n)
        else: cls['still wrong (profile >1%)'].append(n)
    resc = len(cls['right (profile <=0.1%)']) + len(cls['mid (profile 0.1-1%)'])
    print('  [%s] head wrong fits: %d. On %s they become:' % (vlabel, len(Wn), vlabel))
    for k, v in cls.items():
        print('      %-26s %3d' % (k, len(v)))
    print('      rescued (accepted profile within 1%%) %d of %d = %.1f%%' % (resc, len(Wn), 100.0 * resc / max(1, len(Wn))))
    return Wn, cls, resc


def head_right_names(Dh, tiers=('noisy',)):
    return [n for n, r in sorted(Dh.items()) if r['tier'] in tiers and right(r)]


def report_set(S, L):
    Dh = L['head']
    print('=' * 110)
    print('SET %s   (%d plants per variant; head %d, a %d, b %d, ab %d rows)' % (S, len(Dh), len(L['head']), len(L['a']), len(L['b']), len(L['ab'])))
    print('=' * 110)
    for v in VARS:
        if set(L[v]) != set(Dh):
            print('!! plant names of %s differ from head' % v)

    print('\n--- 0. Reproduction of step 1 (head, noisy tier) ---')
    Wh = [r for r in (Dh[n] for n in tier_names(Dh, 'noisy')) if wrong(r)]
    print('  head accepted profile fits off by >1%% in (a+b)/2: %d   (step 1: A 35, B 32)' % len(Wh))
    for thr in (0.10, 0.01, 0.001):
        print('    |dR| > %g%%: %d' % (100 * thr, sum(1 for n in tier_names(Dh, 'noisy') if isprof(Dh[n]) and abs(Dh[n]['dR']) > thr)))

    print('\n--- (a) Noisy tier, per variant ---')
    Wv = {}
    for v in VARS:
        Wv[v] = noisy_block(L[v], v)
    for v in VARS[1:]:
        print('  head->%s status transitions (noisy): %s' % (v, transitions(Dh, L[v], 'noisy')))
    # what the app applies = every returned fit, profile or conic
    print('  errors of what the app applies (every returned noisy fit, profile or conic): median | max')
    for v in VARS:
        rs = [L[v][n] for n in tier_names(L[v], 'noisy') if not threw(L[v][n])]
        def med(xs):
            xs = sorted(xs); k = len(xs)
            return (xs[k // 2] if k % 2 else 0.5 * (xs[k // 2 - 1] + xs[k // 2])) if xs else float('nan')
        dth = [r['dtheta'] for r in rs if r['eps'] > 0]
        print('    %-4s |dR| %.4f%% | %.4f%%   |d(b/a)| %.5f | %.5f   dtheta(eps>0) %.4f | %.4f rad   centre %.4f | %.4f px' % (
            v, 100 * med([abs(r['dR']) for r in rs]), 100 * max(abs(r['dR']) for r in rs), med([abs(r['dba']) for r in rs]), max(abs(r['dba']) for r in rs),
            med(dth), max(dth), med([r['cerr'] for r in rs]), max(r['cerr'] for r in rs)))
    gained = [n for n in tier_names(Dh, 'noisy') if isconic(Dh[n]) and isprof(L['a'][n])]
    if gained:
        Da = L['a']
        print('  noisy plants head returned as conic and a returns as profile: %d. Against truth (head conic | a profile): mean|dR| %.4f%% | %.4f%%; max|d(b/a)| %.5f | %.5f; max dtheta(eps>0) %.4f | %.4f rad; max centre %.4f | %.4f px' % (
            len(gained), 100 * sum(abs(Dh[n]['dR']) for n in gained) / len(gained), 100 * sum(abs(Da[n]['dR']) for n in gained) / len(gained),
            max(abs(Dh[n]['dba']) for n in gained), max(abs(Da[n]['dba']) for n in gained),
            max_or(Dh[n]['dtheta'] for n in gained if Dh[n]['eps'] > 0), max_or(Da[n]['dtheta'] for n in gained if Da[n]['eps'] > 0),
            max(Dh[n]['cerr'] for n in gained), max(Da[n]['cerr'] for n in gained)))

    # ---- (b) P3 ----
    Dv = L['a']
    print('\n--- (b) P3, candidate a ---')
    print('  P3 wrong count on a (noisy), predicted 0: %d' % len(Wv['a']))
    H = head_right_names(Dh)
    bad = [n for n in H if not right(Dv[n])]
    print('  head accepted-profile fits within 0.1%% (noisy): %d; not accepted-profile-within-0.1%% on a (predicted none): %d' % (len(H), len(bad)))
    for n in bad:
        v = Dv[n]
        how = 'became WRONG' if wrong(v) else ('became mid (0.1-1%)' if mid(v) else ('became CONIC' if isconic(v) else 'THREW'))
        print('     %-44s head %s -> a %s   [%s]' % (n, desc(Dh[n]), desc(v), how))
    lit = [n for n in tier_names(Dh, 'noisy') if (isprof(Dh[n]) or isconic(Dh[n])) and abs(Dh[n]['dR']) <= RIGHT
           and (threw(Dv[n]) or abs(Dv[n]['dR']) > RIGHT)]
    nlit = sum(1 for n in tier_names(Dh, 'noisy') if (isprof(Dh[n]) or isconic(Dh[n])) and abs(Dh[n]['dR']) <= RIGHT)
    print('  registered wording, any status (profile or conic) within 0.1%% on head (noisy) = %d; outside 0.1%% (or threw) on a = %d' % (nlit, len(lit)))
    for n in lit:
        print('     %-44s head %s -> a %s' % (n, desc(Dh[n]), desc(Dv[n])))
    both_r = [n for n in tier_names(Dh, 'noisy') if isprof(Dh[n]) and isprof(Dv[n]) and abs(Dh[n]['dR']) <= RIGHT and abs(Dv[n]['dR']) <= RIGHT]
    if both_r:
        print('  noisy profile fits within 0.1%% on both head and a (%d): max |change in (a+b)/2| %.5f%% of R; max |change in b/a| %.4g; max |change in theta| eps>0 %.4g rad; max centre change %.4g px' % (
            len(both_r), 100 * max(abs(Dv[n]['dR'] - Dh[n]['dR']) for n in both_r), max(abs(Dv[n]['ba'] - Dh[n]['ba']) for n in both_r),
            max_or(angle_err(Dv[n]['theta'], Dh[n]['theta']) for n in both_r if Dh[n]['eps'] > 0),
            max(math.hypot(Dv[n]['cx'] - Dh[n]['cx'], Dv[n]['cy'] - Dh[n]['cy']) for n in both_r)))
    # all other tiers
    for tier in sorted(set(r['tier'] for r in Dh.values()) - {'noisy'}):
        hn = [n for n in tier_names(Dh, tier) if (isprof(Dh[n]) or isconic(Dh[n])) and abs(Dh[n]['dR']) <= RIGHT]
        bn = [n for n in hn if threw(Dv[n]) or abs(Dv[n]['dR']) > RIGHT]
        if bn:
            print('  tier %-14s head fits within 0.1%%: %d; outside 0.1%% (or threw) on a: %d' % (tier, len(hn), len(bn)))
            for n in bn:
                print('     %-44s head %s -> a %s' % (n, desc(Dh[n]), desc(Dv[n])))
    print('  (tiers not listed above have no head-within-0.1% fit outside 0.1% on a)')

    # ---- (c) R2 ----
    print('\n--- (c) R2 (rescued = accepted profile within 1%) ---')
    Wn, cls, resc = r2_table(Dh, L['a'], 'a')
    turned = [n for n in tier_names(Dh, 'noisy') if right(Dh[n]) and wrong(L['a'][n])]
    turned1 = [n for n in tier_names(Dh, 'noisy') if within1(Dh[n]) and wrong(L['a'][n])]
    print('  right (<=0.1%%) head fits turned wrong (>1%%) on a: %d; head profile fits within 1%% turned wrong: %d' % (len(turned), len(turned1)))
    ok = (Wn and 100.0 * resc / len(Wn) >= 90 and not turned)
    print('  R2 refuting observations: rescued<90%% -> %s; a right fit turned wrong -> %s   => R2 %s' % (
        'YES' if (Wn and 100.0 * resc / len(Wn) < 90) else 'no', 'YES' if turned else 'no', 'NOT refuted' if ok else 'REFUTED'))
    still = [Dv[n] for n in Wn if wrong(Dv[n])]
    print('  for reference, the same table for b and ab:')
    r2_table(Dh, L['b'], 'b')
    r2_table(Dh, L['ab'], 'ab')

    # ---- (d) P4 ----
    Db = L['b']
    print('\n--- (d) P4, candidate b ---')
    refused = [n for n in Wn if not isprof(Db[n])]
    kept = [n for n in Wn if isprof(Db[n])]
    conic_ok = [n for n in refused if isconic(Db[n]) and abs(Db[n]['dR']) <= WRONG]
    conic_bad = [n for n in refused if isconic(Db[n]) and abs(Db[n]['dR']) > WRONG]
    thrw = [n for n in refused if threw(Db[n])]
    floor_reason = [n for n in refused if isconic(Db[n]) and 'floor' in str(Db[n].get('fallback', ''))]
    print('  head wrong fits (%d): b refuses %d (pred >= 10): to conic within 1%% %d, to conic >1%% %d, threw %d; refusals carrying the ring-width reason: %d'
          % (len(Wn), len(refused), len(conic_ok), len(conic_bad), len(thrw), len(floor_reason)))
    print('  head wrong fits b leaves accepted as profile: %d (b leaves them bit-identical to head: %s)' % (
        len(kept), 'yes' if all(Db[n]['dR'] == Dh[n]['dR'] for n in kept) else 'NO'))
    for n in kept:
        print('     ' + wrong_row(Db[n]))
    Hn = head_right_names(Dh)
    ref0 = [n for n in Hn if not isprof(Db[n])]
    print('  head accepted-profile fits within 0.1%% (noisy): %d; b refuses (pred 0): %d' % (len(Hn), len(ref0)))
    for n in ref0:
        print('     %-44s head %s -> b %s  sin %.3f sout %.3f (head)' % (n, desc(Dh[n]), desc(Db[n]), Dh[n]['sin'], Dh[n]['sout']))
    for tier in sorted(set(r['tier'] for r in Dh.values()) - {'noisy'}):
        hn = [n for n in tier_names(Dh, tier) if right(Dh[n])]
        bn = [n for n in hn if not isprof(Db[n])]
        if bn:
            print('  tier %-14s head profile fits within 0.1%%: %d; refused by b: %d' % (tier, len(hn), len(bn)))
            for n in bn:
                print('     %-44s head %s -> b %s' % (n, desc(Dh[n]), desc(Db[n])))
    mids = [n for n in tier_names(Dh, 'noisy') if mid(Dh[n]) and not isprof(Db[n])]
    print('  head mid fits (0.1-1%%) that b refuses: %d' % len(mids))
    # integrity: b's refusals should be exactly head profile fits with min ring sigma <= 0.30
    allrefused = [n for n in Dh if isprof(Dh[n]) and not isprof(Db[n])]
    predicted = [n for n in Dh if isprof(Dh[n]) and minsig(Dh[n]) <= 0.30]
    print('  integrity: b refusals (all tiers, head profile -> b not profile) = %d; head profile fits with min(sin,sout) <= 0.30 = %d; sets equal: %s' % (
        len(allrefused), len(predicted), 'yes' if set(allrefused) == set(predicted) else 'NO (symmetric difference: %s)' % sorted(set(allrefused) ^ set(predicted))))
    changed_non_prof = [n for n in Dh if not isprof(Dh[n]) and (status(Dh[n]) != status(Db[n]) or dR(Dh[n]) != dR(Db[n]))]
    print('  b changes any plant that was conic/THREW on head: %d' % len(changed_non_prof))
    b_wrong_after = Wv['b']
    print('  b noisy wrong count after refusal: %d (of head %d)' % (len(b_wrong_after), len(Wn)))

    # ---- (e) P6 ----
    Dab = L['ab']
    print('\n--- (e) P6, candidate ab ---')
    print('  ab wrong count (noisy), pred 0: %d' % len(Wv['ab']))
    Hr = head_right_names(Dh)
    bad6 = [n for n in Hr if not right(Dab[n])]
    print('  head accepted-profile fits within 0.1%% (noisy): %d; refused or outside 0.1%% on ab (pred 0): %d' % (len(Hr), len(bad6)))
    for n in bad6:
        v = Dab[n]
        how = 'became WRONG' if wrong(v) else ('mid (0.1-1%)' if mid(v) else ('REFUSED to conic' if isconic(v) else 'THREW'))
        print('     %-44s head %s -> ab %s   [%s]' % (n, desc(Dh[n]), desc(v), how))
    lit6 = [n for n in tier_names(Dh, 'noisy') if (isprof(Dh[n]) or isconic(Dh[n])) and abs(Dh[n]['dR']) <= RIGHT
            and (threw(Dab[n]) or abs(Dab[n]['dR']) > RIGHT)]
    print('  registered wording, any status within 0.1%% on head (noisy), outside 0.1%% (or threw) on ab: %d' % len(lit6))
    for n in lit6:
        print('     %-44s head %s -> ab %s' % (n, desc(Dh[n]), desc(Dab[n])))
    for tier in sorted(set(r['tier'] for r in Dh.values()) - {'noisy'}):
        hn = [n for n in tier_names(Dh, tier) if right(Dh[n])]
        bn = [n for n in hn if not right(Dab[n])]
        if bn:
            print('  tier %-14s head profile fits within 0.1%%: %d; refused or outside 0.1%% on ab: %d' % (tier, len(hn), len(bn)))
            for n in bn:
                print('     %-44s head %s -> ab %s' % (n, desc(Dh[n]), desc(Dab[n])))
    print('  (the R2-style table for ab is in (c))')

    # ---- (f) clean tier ----
    print('\n--- (f) Clean tier (%d plants), each variant against head ---' % len(tier_names(Dh, 'clean')))
    cn = tier_names(Dh, 'clean')
    for v in VARS[1:]:
        Dv = L[v]
        chg = [n for n in cn if status(Dh[n]) != status(Dv[n])]
        both = [n for n in cn if isprof(Dh[n]) and isprof(Dv[n])]
        d_r = [abs(Dv[n]['dR'] - Dh[n]['dR']) for n in both]
        d_th = [(Dv[n]['eps'] > 0, angle_err(Dv[n]['theta'], Dh[n]['theta'])) for n in both]
        d_c = [math.hypot(Dv[n]['cx'] - Dh[n]['cx'], Dv[n]['cy'] - Dh[n]['cy']) for n in both]
        d_ba = [abs(Dv[n]['ba'] - Dh[n]['ba']) for n in both]
        print('  %-3s model choice changed (profile<->conic/threw): %d (pred none); profile fits kept both ways: %d; head profile %d, %s profile %d'
              % (v, len(chg), len(both), sum(isprof(Dh[n]) for n in cn), v, sum(isprof(Dv[n]) for n in cn)))
        for n in chg:
            print('       CHANGED %-44s head %s -> %s %s' % (n, desc(Dh[n]), v, desc(Dv[n])))
        if both:
            print('       max |change in (a+b)/2| = %.5f%% of R (pred <= 0.01%%); max |d theta| eps>0 = %.3g rad, all = %.3g rad (pred <= 1e-3, eps>0); max |d(b/a)| = %.3g; max centre change = %.4g px' % (
                100 * max(d_r), max_or(t for e, t in d_th if e), max_or(t for e, t in d_th), max(d_ba), max(d_c)))
            ex = [n for n, d in zip(both, d_r) if d > 1e-4]
            exth = [n for n, (e, t) in zip(both, d_th) if e and t > 1e-3]
            print('       plants over 0.01%% of R: %d; plants over 1e-3 rad (eps>0): %d' % (len(ex), len(exth)))
            for n in ex[:12]:
                print('         dR  %-44s head %s %s %s' % (n, pct(Dh[n]['dR']), v, pct(Dv[n]['dR'])))
            for n in exth[:12]:
                print('         dth %-44s head %.5f %s %.5f' % (n, Dh[n]['theta'], v, Dv[n]['theta']))
        wr = [n for n in cn if wrong(Dv[n])]
        print('       clean accepted profile wrong (>1%%) on %s: %d (head: %d)' % (v, len(wr), sum(wrong(Dh[n]) for n in cn)))
        if chg:
            gained = [n for n in chg if isconic(Dh[n]) and isprof(Dv[n])]
            lost = [n for n in chg if isprof(Dh[n]) and not isprof(Dv[n])]
            print('       of the %d changed: conic->profile %d, profile->conic/threw %d' % (len(chg), len(gained), len(lost)))
            if gained:
                print('       the %d conic->profile plants against truth (head conic | %s profile): mean|dR| %.4f%% | %.4f%%; max|dR| %.4f%% | %.4f%%; max|d(b/a)| %.4g | %.4g; max dtheta(eps>0) %.3g | %.3g rad; max centre err %.3g | %.3g px; variant closer in |dR| for %d of %d' % (
                    len(gained), v,
                    100 * sum(abs(Dh[n]['dR']) for n in gained) / len(gained), 100 * sum(abs(Dv[n]['dR']) for n in gained) / len(gained),
                    100 * max(abs(Dh[n]['dR']) for n in gained), 100 * max(abs(Dv[n]['dR']) for n in gained),
                    max(abs(Dh[n]['dba']) for n in gained), max(abs(Dv[n]['dba']) for n in gained),
                    max_or(Dh[n]['dtheta'] for n in gained if Dh[n]['eps'] > 0), max_or(Dv[n]['dtheta'] for n in gained if Dv[n]['eps'] > 0),
                    max(Dh[n]['cerr'] for n in gained), max(Dv[n]['cerr'] for n in gained),
                    sum(abs(Dv[n]['dR']) < abs(Dh[n]['dR']) for n in gained), len(gained)))
                print('       head residual over cap on those (head fallback text): ' + ', '.join(sorted(set(str(Dh[n].get('fallback', '?')) for n in gained)))[:300])
        movers = [n for n, d, (e, t) in zip(both, d_r, d_th) if d > 1e-4 or (e and t > 1e-3)]
        if movers:
            print('       kept-both-ways plants that moved more than the prediction allows: %d. Against truth (head | %s), and fit cost on the pixels (variant/head, < 1 = variant found the lower cost):' % (len(movers), v))
            for n in sorted(movers, key=lambda n: -abs(Dv[n]['dR'] - Dh[n]['dR'])):
                h, x = Dh[n], Dv[n]
                print('         %-44s |dR| %.4f%% | %.4f%%   dtheta %.3f | %.3f%s   |d(b/a)| %.4f | %.4f   cerr %.3f | %.3f   cost x%.6f' % (
                    n, 100 * abs(h['dR']), 100 * abs(x['dR']), h['dtheta'], x['dtheta'], '' if h['eps'] > 0 else '(eps0)', abs(h['dba']), abs(x['dba']),
                    h['cerr'], x['cerr'], x['cost_fit'] / h['cost_fit']))
            print('       movers: variant closer to truth in |dR| for %d of %d; in dtheta (eps>0) for %d of %d; lower or equal fit cost for %d of %d; every mover is gap-%s' % (
                sum(abs(Dv[n]['dR']) < abs(Dh[n]['dR']) for n in movers), len(movers),
                sum(Dv[n]['dtheta'] < Dh[n]['dtheta'] for n in movers if Dh[n]['eps'] > 0), sum(1 for n in movers if Dh[n]['eps'] > 0),
                sum(Dv[n]['cost_fit'] <= Dh[n]['cost_fit'] for n in movers), len(movers),
                '/'.join(sorted(set('%g' % Dh[n]['gap'] for n in movers)))))

    # ---- (g) printed and refusal tiers ----
    print('\n--- (g) Printed and refusal tiers: plants whose status differs, or dR by > 0.01% of R, between head and a variant ---')
    other = sorted(n for n, r in Dh.items() if r['tier'] not in ('noisy', 'clean'))
    for v in VARS[1:]:
        Dv = L[v]
        lines = []
        for n in other:
            h, x = Dh[n], Dv[n]
            diff = status(h) != status(x) or (not threw(h) and not threw(x) and abs(x['dR'] - h['dR']) > CHANGE_TOL)
            if diff:
                extra = ''
                if threw(h) or threw(x):
                    extra = '  [err head: %s; %s: %s]' % (h.get('err', '-'), v, x.get('err', '-'))
                lines.append('     %-14s %-44s head %-22s %-3s %-22s%s' % (h['tier'], n, desc(h), v, desc(x), extra))
        print('  %s: %d of %d plants differ' % (v, len(lines), len(other)))
        for l in lines:
            print(l)

    # ---- integrity: refusal tier, ab vs a ----
    print('\n--- integrity ---')
    for v in VARS:
        rs = [L[v][n] for n in tier_names(L[v], 'refusal')]
        print('  refusal tier on %-4s: %s' % (v, ', '.join('%s' % (r.get('err', r.get('status'))) if threw(r) else status(r) for r in rs)))
    refdiff = [n for n in tier_names(Dh, 'refusal') if any(desc(L[v][n]) != desc(Dh[n]) or L[v][n].get('err') != Dh[n].get('err') for v in VARS[1:])]
    print('  refusal-tier plants whose result differs between head and any variant: %d of %d' % (len(refdiff), len(tier_names(Dh, 'refusal'))))
    abd = [n for n in Dh if desc(L['ab'][n]) != desc(L['a'][n]) or L['ab'][n].get('dtheta') != L['a'][n].get('dtheta')]
    print('  plants (all tiers) where ab differs from a in status, dR or dtheta: %d of %d' % (len(abd), len(Dh)))
    for n in abd[:10]:
        print('     %-44s a %s  ab %s' % (n, desc(L['a'][n]), desc(L['ab'][n])))

    # ---- (h) wrong fits that remain ----
    print('\n--- (h) Wrong fits that remain (noisy), with ring sigmas, I1 and centre error ---')
    for v in VARS[1:]:
        W = Wv[v]
        print('  %s: %d' % (v, len(W)))
        for r in sorted(W, key=lambda r: -abs(r['dR'])):
            print('     ' + wrong_row(r))
    print()


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else '.'
    for S in SETS:
        L = {v: load(os.path.join(d, '%s_%s.log' % (v, S))) for v in VARS}
        report_set(S, L)
    # the cross-set summary of the pre-registered numbers
    print('=' * 110)
    print('CROSS-SET SUMMARY (noisy tier)')
    print('=' * 110)
    for S in SETS:
        L = {v: load(os.path.join(d, '%s_%s.log' % (v, S))) for v in VARS}
        Dh = L['head']
        Wn = [n for n in tier_names(Dh, 'noisy') if wrong(Dh[n])]
        Hr = head_right_names(Dh)
        out = ['set %s: head wrong %d' % (S, len(Wn))]
        for v in VARS[1:]:
            Dv = L[v]
            nw = sum(1 for n in tier_names(Dv, 'noisy') if wrong(Dv[n]))
            resc = sum(1 for n in Wn if within1(Dv[n]))
            ref = sum(1 for n in Wn if not isprof(Dv[n]))
            badr = sum(1 for n in Hr if not right(Dv[n]))
            out.append('%s: wrong %d, rescued %d/%d, head-wrong not accepted %d, head-right lost %d/%d' % (v, nw, resc, len(Wn), ref, badr, len(Hr)))
        print('  ' + ' | '.join(out))


if __name__ == '__main__':
    main()
