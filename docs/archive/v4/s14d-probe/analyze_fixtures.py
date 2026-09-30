import numpy as np, re, os, sys
O=os.environ['SP']+'/s14d/out/'; L=open(os.environ['SP']+'/s14d/logs/fixture.log').read()
names=[l.split()[1] for l in L.splitlines() if l.startswith('===')]
rs={l.split()[1]:float(re.search(r'r ([\d.]+) centre',l).group(1)) for l in L.splitlines() if l.startswith('===')}
def rd(n,c): return np.fromfile(O+f'fx_{n}.{c}.f32',np.float32).reshape(-1,2).astype(float)
# twin (numpy, float64), line for line the shader: block seed then iterated CoM
def block_coarse(pat,r):
    b=max(1,int(round(r))); qy,qx=pat.shape; best=-np.inf; cx=0.5*(qx-1); cy=0.5*(qy-1)
    for by in range(0,qy,b):
        ye=min(by+b,qy)
        for bx in range(0,qx,b):
            xe=min(bx+b,qx); s=pat[by:ye,bx:xe].sum()
            if s>best: best=s; cx=0.5*(bx+xe-1); cy=0.5*(by+ye-1)
    return cx,cy
def com(pat,cx,cy,win,passes,yy,xx):
    p=np.maximum(pat,0)
    for _ in range(passes):
        m=(xx-cx)**2+(yy-cy)**2<=win*win; s=p[m].sum()
        if not s>0: break
        nx=(p*xx)[m].sum()/s; ny=(p*yy)[m].sum()/s; st=abs(nx-cx)<1e-4 and abs(ny-cy)<1e-4; cx,cy=nx,ny
        if st: break
    return cx,cy
yy,xx=np.mgrid[:250,:250]
cands=['ship','k1.5','k1.75','k2.0','k2.5','k3.0','p1','py1','p10','p30']
out=[]
def P(s): print(s); out.append(s)
P("== per fixture: |measured - truth| median / max px (GPU probe; ship = the unmodified shipped kernel)")
P(f"{'fixture':22s} {'r':>5s} {'win':>5s} "+" ".join(f"{c:>13s}" for c in cands))
for n in names:
    tr=np.loadtxt(O+f'fixt_{n}.truth.txt').reshape(-1,2); r=rs[n]
    row=[]
    for c in cands:
        e=np.hypot(*(rd(n,c)-tr).T); row.append(f"{np.median(e):6.3f}/{e.max():6.3f}")
    sh=np.hypot(*(rd(n,'SHIPPED')-tr).T)
    P(f"{n:22s} {r:5.2f} {max(1.2*r,r+1.5):5.2f} "+" ".join(f"{x:>13s}" for x in row))
P("\n== twin vs GPU shipped (4 passes, floor), max |diff| px, and twin per-pass trace for F2_rho8p5 pattern 12 (centre (127.3,127.6))")
for n in names:
    cube=np.fromfile(O+f'fixt_{n}.f32',np.float32).reshape(-1,250,250).astype(np.float64); r=rs[n]
    win=max(1.2*r,r+1.5); md=0
    for i in range(len(cube)):
        bx,by=block_coarse(cube[i],r); t=com(cube[i],bx,by,win,4,yy,xx); g=rd(n,'ship')[i]
        md=max(md,abs(t[0]-g[0]),abs(t[1]-g[1]))
    P(f"  {n:22s} twin-vs-GPU max |diff| {md:.2e}")
n='F2_rho8p5'; cube=np.fromfile(O+f'fixt_{n}.f32',np.float32).reshape(-1,250,250).astype(np.float64); r=rs[n]; win=max(1.2*r,r+1.5); tr=np.loadtxt(O+f'fixt_{n}.truth.txt').reshape(-1,2)
i=12; bx,by=block_coarse(cube[i],r); P(f"  trace F2_rho8p5 #12 truth {tr[i]} block seed ({bx},{by}) win {win:.3f}")
for p in (0,1,2,3,4,6,10,30):
    t=com(cube[i],bx,by,win,p,yy,xx) if p else (bx,by); P(f"    passes {p:2d}: ({t[0]:.3f},{t[1]:.3f}) err {np.hypot(t[0]-tr[i][0],t[1]-tr[i][1]):.3f}")
P("\n== gain d(new centre)/d(offset) at truth, ONE pass, seeds = truth +-0.25 px (GPU; gain = (c(+d)-c(-d))/(2 d)), median over patterns")
P(f"{'fixture':22s} "+" ".join(f"{'k='+str(k):>9s}" for k in (1.2,1.5,2.0,3.0)))
for n in names:
    tr=np.loadtxt(O+f'fixt_{n}.truth.txt').reshape(-1,2); row=[]
    for k in (1.2,1.5,2.0,3.0):
        gx=(rd(n,f'gainpx_k{k}')[:,0]-rd(n,f'gainmx_k{k}')[:,0])/0.5; gy=(rd(n,f'gainpy_k{k}')[:,1]-rd(n,f'gainmy_k{k}')[:,1])/0.5
        row.append(f"{np.median(np.r_[gx,gy]):9.3f}")
    P(f"{n:22s} "+" ".join(row))
P("\n== truth as a fixed point: 4 passes at the shipped window seeded AT truth, |result - truth| median/max; and seeded truth+0.25 in x")
for n in names:
    tr=np.loadtxt(O+f'fixt_{n}.truth.txt').reshape(-1,2)
    e0=np.hypot(*(rd(n,'holdt0_k1.2')-tr).T); e1=np.hypot(*(rd(n,'holdpx_k1.2')-tr).T)
    P(f"  {n:22s} from truth: {np.median(e0):.4f}/{e0.max():.4f}   from truth+0.25: {np.median(e1):.4f}/{e1.max():.4f}")
open(os.environ['SP']+'/s14d/logs/fixture_analysis.log','w').write("\n".join(out)+"\n")
