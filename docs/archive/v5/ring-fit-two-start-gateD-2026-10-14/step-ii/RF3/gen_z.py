#!/usr/bin/env python3
# RF3 own generator: small-ring, real-pattern-like plants (Au_ref-like geometry): 96x96, central beam + 1/r^2 tail + noise.
import json, math, os, random, struct, array
out="data/plantsZ"; os.makedirs(out,exist_ok=True); cases=[]; k=0
H=W=96
for R in (10.0,17.5,25.0,34.0):
  for sig in (1.5,2.5):
    for eps in (0.01,0.03):
      for tail in (0.1,0.5,1.5):
        for noise in (0.01,0.03):
          for ann in ("A","W"):
            for th in (20.0,112.5):
              rng=random.Random(9_000_000+k)
              b=2*R/(2+eps); a=b*(1+eps); theta=math.radians(th)
              r0=H/2.0+0.31+2.0*math.sin(1.7*k+0.4); c0=W/2.0-0.27+2.0*math.cos(2.3*k+1.1)
              ct,st=math.cos(theta),math.sin(theta)
              px=array.array('f')
              for i in range(H):
                for j in range(W):
                  dr,dc=i-r0,j-c0
                  u=dr*ct+dc*st; v=-dr*st+dc*ct
                  rho=math.sqrt((u/a)**2+(v/b)**2)
                  ring=math.exp(-(((rho-1)*R)**2)/(2*sig**2))
                  r=math.hypot(dr,dc)
                  beam=100.0*math.exp(-r*r/(2*2.75**2))
                  tl=tail*(R/max(r,2.0))**2
                  px.append(ring+beam+tl+rng.gauss(0,noise))
              inner,outer=(R-5,R+3) if ann=="A" else (R-6,R+5)
              name="Z-R%g-s%g-e%g-t%g-n%g-%s-th%g-%03d"%(R,sig,eps*100,tail,noise*100,ann,th,k)
              with open(os.path.join(out,name+".in.f32"),"wb") as f: px.tofile(f)
              cases.append(dict(name=name,file=name+".in.f32",tier="Z-%s-t%g"%(ann,tail),rows=H,cols=W,r0=r0,c0=c0,R=R,a=a,b=b,theta=theta,eps=eps,noise=noise,gap_deg=0.0,sigma=sig,
                  inner=inner,outer=outer,guess_row=r0+1.3,guess_col=c0-0.9)); k+=1
json.dump({"cases":cases},open(os.path.join(out,"planted.json"),"w"),indent=1); print(len(cases),"cases")
