#!/usr/bin/env python3
# RF2 step 1: re-derive counts from RF's raw logs with my own parser. Output goes to logs/step1_summary.txt (via shell redirect).
from an2 import *
import statistics as st
def acc(d): return None if d["status"]=="THREW" else abs(fl(d,"dR"))
def dba(d): return None if d["status"]=="THREW" else abs(fl(d,"dba"))
def row(S, scope, R, names):
    sel=[n for n in names if scope=="ALL" or R["head"][n]["tier"]==scope]
    H=R["head"]
    hr=[n for n in sel if acc(H[n]) is not None and acc(H[n])<0.001]
    hw=[n for n in sel if H[n]["status"]=="profile" and acc(H[n])>0.01]
    print("%s/%s n=%d | head: right(any model, <0.1%%)=%d wrongProfile(>1%%)=%d  wrongProfile with |d(b/a)|>0.01=%d" % (
        S,scope,len(sel),len(hr),len(hw),sum(1 for n in hw if dba(H[n])>0.01)))
    for v in VARS:
        D=R[v]
        wp=[n for n in sel if D[n]["status"]=="profile" and acc(D[n])>0.01]
        wc=[n for n in sel if D[n]["status"]=="conic" and acc(D[n])>0.01]
        th=[n for n in sel if D[n]["status"]=="THREW"]
        refused=[n for n in sel if H[n]["status"]=="profile" and D[n]["status"]!="profile"]
        lost=[n for n in hr if acc(D[n]) is None or acc(D[n])>=0.001]
        lost1=[n for n in hr if acc(D[n]) is None or acc(D[n])>0.01]
        newW=[n for n in sel if not (H[n]["status"]=="profile" and acc(H[n])>0.01) and ((D[n]["status"]!="THREW") and acc(D[n])>0.01)]
        fixed=[n for n in hw if acc(D[n]) is not None and acc(D[n])<=0.01]
        bad_ba=[n for n in sel if D[n]["status"]!="THREW" and dba(D[n])>0.01]
        mxba=max([dba(D[n]) for n in wp+wc] or [0])
        print("   %-4s wrongProf=%3d wrongConic=%2d wrongAcc=%3d threw=%2d | profile->nonprofile=%3d | rightLost(>=0.1%%)=%2d rightLost(>1%%)=%2d newlyWrong(not W at head)=%2d | headWrongFixed(<=1%%)=%3d/%d | acc fits with |d(b/a)|>0.01: %3d, max|d(b/a)| among wrong %.3f" % (
            v,len(wp),len(wc),len(wp)+len(wc),len(th),len(refused),len(lost),len(lost1),len(newW),len(fixed),len(hw),len(bad_ba),mxba))
for S,scopes in (("C",["ALL","noisy","clean","refusal"]),("P",["ALL","P-a10","P-a20","P-a50","P-a200"]),("N",["ALL","N-clean","N-g1","N-g3","N-pois","N-ss4"]),("T",["ALL","T-neigh","T-neigh2","T-slope","T-gap","T-wide","T-edge"])):
    R,names=cmp_sets(S)
    for sc in scopes: row(S,sc,R,names)
