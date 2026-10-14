#!/usr/bin/env python3
# RF3 own generator V: Bragg-vector-map-like rings. Exact point peaks on an ellipse, bilinear deposition (DiskDetection.map), stray peaks.
import json, math, os, random, array
out="data/plantsV"; os.makedirs(out,exist_ok=True); cases=[]; k=0
H=W=128
for R in (20.0,35.0,50.0):
  for sc in (0.0,0.05,0.15,0.3):
    for eps,th in ((0.01,20.0),(0.03,112.5)):
      for half in (3.0,6.0):
        rng=random.Random(13_000_000+k)
        b=2*R/(2+eps); a=b*(1+eps); theta=math.radians(th)
        r0=H/2.0+0.31+1.5*math.sin(1.7*k+0.4); c0=W/2.0-0.27+1.5*math.cos(2.3*k+1.1)
        ct,st=math.cos(theta),math.sin(theta)
        img=[0.0]*(H*W)
        def dep(x,y,w):
            x0=math.floor(x); y0=math.floor(y); fx=x-x0; fy=y-y0
            for xi,yi,ww in ((x0,y0,(1-fx)*(1-fy)),(x0+1,y0,fx*(1-fy)),(x0,y0+1,(1-fx)*fy),(x0+1,y0+1,fx*fy)):
                if 0<=xi<H and 0<=yi<W: img[xi*W+yi]+=ww*w
        for _ in range(2000):
            t=rng.uniform(0,2*math.pi)
            # point on ellipse (semi-axes a along u, b along v), mean radius R; scatter along the local normal approx
            u=a*math.cos(t); v=b*math.sin(t)
            nrm=math.hypot(u/a**2, v/b**2); nu=(u/a**2)/nrm; nv=(v/b**2)/nrm
            d=rng.gauss(0,sc) if sc>0 else 0.0
            u+=nu*d; v+=nv*d
            x=r0+u*ct-v*st; y=c0+u*st+v*ct
            dep(x,y,rng.uniform(0.5,1.5))
        for _ in range(200):
            rr=rng.uniform(5,60); t=rng.uniform(0,2*math.pi)
            dep(r0+rr*math.cos(t),c0+rr*math.sin(t),rng.uniform(0.5,1.5))
        name="V-R%g-s%g-e%g-t%g-h%g-%03d"%(R,sc*100,eps*100,th,half,k)
        px=array.array('f',img)
        with open(os.path.join(out,name+".in.f32"),"wb") as f: px.tofile(f)
        cases.append(dict(name=name,file=name+".in.f32",tier="V-s%g"%(sc*100),rows=H,cols=W,r0=r0,c0=c0,R=R,a=a,b=b,theta=theta,eps=eps,noise=0.0,gap_deg=0.0,sigma=sc,
            inner=R-half,outer=R+half,guess_row=r0+1.3,guess_col=c0-0.9)); k+=1
json.dump({"cases":cases},open(os.path.join(out,"planted.json"),"w"),indent=1); print(len(cases),"cases")
