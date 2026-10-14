#!/usr/bin/env python3
"""RF2 own generator: one-sided sharp ring edges (asymmetric Gaussian = the model's own profile shape). Same geometry convention as the model:
major axis a along (cos t, sin t) in (row, col); R=(a+b)/2; guess = centre + (1.3,-0.9); annulus [b-20, a+20]."""
import json, math, os, numpy as np
out="data/plantsS1"; os.makedirs(out,exist_ok=True)
cases=[]; k=0; seed0=4_400_000
def centre(Hh,W,k): return Hh/2.0+0.31+5.0*math.sin(1.7*k+0.4), W/2.0-0.27+5.0*math.cos(2.3*k+1.1)
for R in (120.0,):
  for eps in (0.01,0.03):
    for (sin_,sout) in ((0.30,3.0),(3.0,0.30),(0.5,3.0),(3.0,0.5),(0.30,0.30),(3.0,3.0),(0.30,6.0),(1.0,3.0)):
      for noise in (0.0,0.01,0.03,0.10):
        for th in (20.0,112.5):
          Hh=W=512
          b=2*R/(2+eps); a=b*(1+eps); theta=math.radians(th)
          r0,c0=centre(Hh,W,k)
          rr,cc=np.mgrid[0:Hh,0:W].astype(float)
          dr,dc=rr-r0,cc-c0; st,ct=math.sin(theta),math.cos(theta)
          u,v=dr*ct+dc*st,-dr*st+dc*ct; rho=np.sqrt((u/a)**2+(v/b)**2)
          x=(rho-1.0)*R; s=np.where(x<0,sin_,sout)
          img=np.exp(-(x*x)/(2*s*s))
          # supersample 3x3 to integrate pixel-wise like a detector (so narrow edges are physical)
          acc=np.zeros_like(img); offs=(np.arange(3)+0.5)/3-0.5
          for oy in offs:
            for ox in offs:
              dr2,dc2=rr+oy-r0,cc+ox-c0; u2,v2=dr2*ct+dc2*st,-dr2*st+dc2*ct
              x2=(np.sqrt((u2/a)**2+(v2/b)**2)-1.0)*R; s2=np.where(x2<0,sin_,sout); acc+=np.exp(-(x2*x2)/(2*s2*s2))
          img=acc/9
          if noise>0: img=img+np.random.default_rng(seed0+k).normal(0,noise,img.shape)
          name="S1-in%g-out%g-e%g-n%g-t%g-%03d"%(sin_,sout,eps*100,noise*100,th,k)
          img.astype("<f4").tofile(os.path.join(out,name+".in.f32"))
          cases.append(dict(name=name,file=name+".in.f32",tier="S1-in%g-out%g"%(sin_,sout),rows=Hh,cols=W,r0=r0,c0=c0,R=R,a=a,b=b,theta=theta,eps=eps,
              noise=noise,gap_deg=0.0,sigma=min(sin_,sout),inner=b-20,outer=a+20,guess_row=r0+1.3,guess_col=c0-0.9,sigma_in=sin_,sigma_out=sout))
          k+=1
json.dump({"cases":cases},open(os.path.join(out,"planted.json"),"w"),indent=1)
print(len(cases),"cases")
