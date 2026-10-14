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
