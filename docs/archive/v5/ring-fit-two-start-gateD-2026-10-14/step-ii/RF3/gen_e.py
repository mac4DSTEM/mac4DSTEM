#!/usr/bin/env python3
# RF3 own generator: steeper exponential tails than T-slope (exp25 amplitude 2 = registered worst): amp 2,3,4,6,10 at the ring.
import json, math, os, random, array
out="data/plantsE"; os.makedirs(out,exist_ok=True); cases=[]; k=0
H=W=512; R=120.0; sig=3.0
for amp in (2.0,3.0,4.0,6.0,10.0):
  for eps in (0.01,0.03):
    for th in (20.0,112.5):
      for noise in (0.03,):
        rng=random.Random(7_000_000+k)
        b=2*R/(2+eps); a=b*(1+eps); theta=math.radians(th)
        r0=H/2.0+0.31+5.0*math.sin(1.7*k+0.4); c0=W/2.0-0.27+5.0*math.cos(2.3*k+1.1)
        ct,st=math.cos(theta),math.sin(theta)
        px=array.array('f')
        for i in range(H):
          dr=i-r0
          for j in range(W):
            dc=j-c0
            u=dr*ct+dc*st; v=-dr*st+dc*ct
            rho=math.sqrt((u/a)**2+(v/b)**2)
            r=max(math.hypot(dr,dc),1.0)
            px.append(math.exp(-(((rho-1)*R)**2)/(2*sig**2))+amp*math.exp(-(r-R)/25.0)+rng.gauss(0,noise))
        name="E-exp25a%g-e%g-t%g-%03d"%(amp,eps*100,th,k)
        with open(os.path.join(out,name+".in.f32"),"wb") as f: px.tofile(f)
        cases.append(dict(name=name,file=name+".in.f32",tier="E-exp25a%g"%amp,rows=H,cols=W,r0=r0,c0=c0,R=R,a=a,b=b,theta=theta,eps=eps,noise=noise,gap_deg=0.0,sigma=sig,
            inner=b-20,outer=a+20,guess_row=r0+1.3,guess_col=c0-0.9)); k+=1
json.dump({"cases":cases},open(os.path.join(out,"planted.json"),"w"),indent=1); print(len(cases),"cases")
