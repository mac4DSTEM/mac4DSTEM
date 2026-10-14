from an2 import *
import math
KEYS=["status","dR","dba","dth","cerr","resid","I1","sin","sout","s0"]
def parse2(path):
    rows={}
    for ln in open(path):
        if ln.startswith("ROW|"):
            d={}
            for kv in ln.rstrip("\n").split("|")[1:]:
                k,_,v=kv.partition("="); d[k]=v
            rows[d["name"]]=d
    return rows
def same9(x,y):
    if x==y: return True
    try: fx,fy=float(x),float(y)
    except: return False
    if fx==fy: return True
    return float("%.9g"%fx)==float(y) or abs(fx-fy)<=1e-8*max(abs(fx),abs(fy),1e-300)*1 and "%.9g"%fx==("%.9g"%fy)
