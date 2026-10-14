from an2 import *
import statistics as st
R,names=cmp_sets("C")
sel=[n for n in names if R["head"][n]["tier"]=="clean" and R["head"][n]["status"]=="profile" and R["a"][n]["status"]=="profile"]
print("clean kept profile both ways:",len(sel))
dR=[abs(fl(R["a"][n],"dR")-fl(R["head"][n],"dR")) for n in sel]
dth=[abs(fl(R["a"][n],"dth")-fl(R["head"][n],"dth")) for n in sel]
dba=[abs(fl(R["a"][n],"dba")-fl(R["head"][n],"dba")) for n in sel]
print(" |ΔdR| max %.2e  >1e-4: %d   |Δdth| max %.2e >1e-3: %d  |Δdba| max %.2e"%(max(dR),sum(x>1e-4 for x in dR),max(dth),sum(x>1e-3 for x in dth),max(dba)))
for n in sel:
    if abs(fl(R["a"][n],"dR")-fl(R["head"][n],"dR"))>1e-4 or abs(fl(R["a"][n],"dth")-fl(R["head"][n],"dth"))>1e-3:
        print("  ",n,"gap",R["head"][n]["gap"],"dR head %.2e a %.2e | dth head %.2e a %.2e | dba head %.2e a %.2e"%(fl(R["head"][n],"dR"),fl(R["a"][n],"dR"),fl(R["head"][n],"dth"),fl(R["a"][n],"dth"),fl(R["head"][n],"dba"),fl(R["a"][n],"dba")))
# clean gapped, all: error of head (profile or conic) vs a
print("clean gapped all (any model): max|dR| head %.2e a %.2e ; max|dba| head %.2e a %.2e"%(
 max(abs(fl(R["head"][n],"dR")) for n in names if R["head"][n]["tier"]=="clean" and R["head"][n]["gap"]=="60"),
 max(abs(fl(R["a"][n],"dR")) for n in names if R["head"][n]["tier"]=="clean" and R["head"][n]["gap"]=="60"),
 max(abs(fl(R["head"][n],"dba")) for n in names if R["head"][n]["tier"]=="clean" and R["head"][n]["gap"]=="60"),
 max(abs(fl(R["a"][n],"dba")) for n in names if R["head"][n]["tier"]=="clean" and R["head"][n]["gap"]=="60")))
cg=[n for n in names if R["head"][n]["tier"]=="clean" and R["head"][n]["gap"]=="60" and R["head"][n]["status"]=="conic"]
print("clean gapped HEAD conic fallbacks:",len(cg),"conic dba max %.2e median %.2e ; same plants under a dba max %.2e median %.2e; dR conic max %.2e a max %.2e"%(
  max(abs(fl(R["head"][n],"dba")) for n in cg), st.median(abs(fl(R["head"][n],"dba")) for n in cg),
  max(abs(fl(R["a"][n],"dba")) for n in cg), st.median(abs(fl(R["a"][n],"dba")) for n in cg),
  max(abs(fl(R["head"][n],"dR")) for n in cg), max(abs(fl(R["a"][n],"dR")) for n in cg)))
