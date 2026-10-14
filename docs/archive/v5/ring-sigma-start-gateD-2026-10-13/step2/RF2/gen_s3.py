#!/usr/bin/env python3
import json, math, os, numpy as np
out="data/plantsS3"; os.makedirs(out,exist_ok=True); cases=[]; k=0; seed0=5_500_000
def centre(Hh,W,k): return Hh/2.0+0.31+5.0*math.sin(1.7*k+0.4), W/2.0-0.27+5.0*math.cos(2.3*k+1.1)
for rep in (1,2):
  for R in (80.0,140.0,200.0):
    for eps in (0.01,0.03):
      for bg in (("none",0),("const",0.3),("r2",0.4),("r2",0.8),("exp25",0.8)):
        for noise in (0.15,0.30):
          th=(20.0,112.5)[(k+rep)%2]
          Hh=W=512; b=2*R/(2+eps); a=b*(1+eps); theta=math.radians(th); r0,c0=centre(Hh,W,k)
          rr,cc=np.mgrid[0:Hh,0:W].astype(float); dr,dc=rr-r0,cc-c0
          u,v=dr*math.cos(theta)+dc*math.sin(theta),-dr*math.sin(theta)+dc*math.cos(theta)
          rho=np.sqrt((u/a)**2+(v/b)**2); img=np.exp(-(((rho-1)*R)**2)/(2*3.0**2))
          r=np.maximum(np.hypot(dr,dc),1.0)
          if bg[0]=="const": img=img+bg[1]
          elif bg[0]=="r2": img=img+bg[1]*(R/r)**2
          elif bg[0]=="exp25": img=img+bg[1]*np.exp(-(r-R)/25.0)
          img=img+np.random.default_rng(seed0+k).normal(0,noise,img.shape)
          name="S3-%s%g-n%g-R%d-e%g-t%g-%03d"%(bg[0],bg[1],noise*100,R,eps*100,th,k)
          img.astype("<f4").tofile(os.path.join(out,name+".in.f32"))
          cases.append(dict(name=name,file=name+".in.f32",tier="S3-%s%g"%bg,rows=Hh,cols=W,r0=r0,c0=c0,R=R,a=a,b=b,theta=theta,eps=eps,noise=noise,gap_deg=0.0,sigma=3.0,
              inner=b-20,outer=a+20,guess_row=r0+1.3,guess_col=c0-0.9)); k+=1
json.dump({"cases":cases},open(os.path.join(out,"planted.json"),"w"),indent=1); print(len(cases),"cases")
