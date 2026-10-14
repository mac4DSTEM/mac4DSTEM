#!/usr/bin/env python3
# RF3 own generator Y2: full rings, annulus half-width fraction h in {0.15,0.25,0.35,0.5}; image side 2*(ceil(R*(1+h))+10)
import json, math, os, random, array
out="data/plantsY2"; os.makedirs(out,exist_ok=True); cases=[]; k=0
for R in (30.0,60.0,100.0):
  for h in (0.15,0.25,0.35,0.5):
    for sig in (1.5,2.5):
      for tail in (0.1,0.3,0.7):
        for eps,th,noise in ((0.01,20.0,0.01),(0.03,112.5,0.03)):
          S=2*(int(math.ceil(R*(1+h)))+10); H=W=S
          rng=random.Random(11_000_000+k)
          b=2*R/(2+eps); a=b*(1+eps); theta=math.radians(th)
          r0=H/2.0+0.31+2.0*math.sin(1.7*k+0.4); c0=W/2.0-0.27+2.0*math.cos(2.3*k+1.1)
          ct,st=math.cos(theta),math.sin(theta)
          px=array.array('f')
          for i in range(H):
            dr=i-r0
            for j in range(W):
              dc=j-c0
              u=dr*ct+dc*st; v=-dr*st+dc*ct
              rho=math.sqrt((u/a)**2+(v/b)**2)
              ring=math.exp(-(((rho-1)*R)**2)/(2*sig**2))
              r=math.hypot(dr,dc)
              beam=100.0*math.exp(-r*r/(2*2.75**2))
              tl=tail*(R/max(r,2.0))**2
              px.append(ring+beam+tl+rng.gauss(0,noise))
          name="Y2-R%g-h%g-s%g-t%g-e%g-n%g-%03d"%(R,h*100,sig,tail,eps*100,noise*100,k)
          with open(os.path.join(out,name+".in.f32"),"wb") as f: px.tofile(f)
          cases.append(dict(name=name,file=name+".in.f32",tier="Y2",rows=H,cols=W,r0=r0,c0=c0,R=R,a=a,b=b,theta=theta,eps=eps,noise=noise,gap_deg=0.0,sigma=sig,
              inner=R*(1-h),outer=R*(1+h),guess_row=r0+1.3,guess_col=c0-0.9)); k+=1
json.dump({"cases":cases},open(os.path.join(out,"planted.json"),"w"),indent=1); print(len(cases),"cases")
