import math, random
random.seed(7)

# ---------- helpers ----------
def chev(): return '<svg class="chev" width="8" height="12" viewBox="0 0 8 12"><path d="M1.2 4.6 4 1.8l2.8 2.8M1.2 7.4 4 10.2l2.8-2.8" fill="none" stroke="#555" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>'
def pop(t, w=None, sub=None):
    st = f' style="width:{w}px"' if w else ''
    return f'<span class="pop"{st}><span class="pt">{t}</span>{chev()}</span>'
def seg(items, sel, w=None):
    s=''.join(f'<span class="sg{" on" if i==sel else ""}">{t}</span>' for i,t in enumerate(items))
    return f'<span class="seg">{s}</span>'
def chk(on=True): return '<span class="cb on"><svg width="10" height="10" viewBox="0 0 10 10"><path d="M1.8 5.4 4 7.6 8.2 2.4" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></span>' if on else '<span class="cb"></span>'
def field(v, w=60): return f'<span class="fld" style="width:{w}px">{v}</span>'
def stepper(): return '<span class="stp"><svg width="10" height="16" viewBox="0 0 10 16"><path d="M2 6 5 3 8 6M2 10 5 13 8 10" fill="none" stroke="#555" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
def badge(t="unvalidated"): return f'<span class="badge">{t}</span>'
def row(label, ctl, cls=''): return f'<div class="row {cls}"><span class="lab">{label}</span><span class="ctl">{ctl}</span></div>'
def disc(t, open_=False): 
    d = 'M2 3.5 5 6.5 8 3.5' if open_ else 'M3.5 2 6.5 5 3.5 8'
    return f'<div class="row disc"><svg width="10" height="10" viewBox="0 0 10 10" style="margin-right:6px"><path d="{d}" fill="none" stroke="#666" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg><span class="lab" style="width:auto;font-weight:600">{t}</span></div>'
def dot(c, r=5): return f'<svg width="{2*r+2}" height="{2*r+2}" style="flex:none"><circle cx="{r+1}" cy="{r+1}" r="{r}" fill="{c}"/></svg>'

COL = dict(Al="#4f8ef7", Mg="#2fb36b", Si="#e5484d", Cu="#f0a020")

# ---------- icons ----------
def icon(kind, c="#555", s=16):
    p = {
     'point':  '<circle cx="8" cy="8" r="2" fill="%s"/><circle cx="8" cy="8" r="5.5" fill="none" stroke="%s" stroke-width="1.2"/>',
     'rect':   '<rect x="2.5" y="3.5" width="11" height="9" fill="none" stroke="%s" stroke-width="1.3" stroke-dasharray="2.2 1.6"/>',
     'ellipse':'<ellipse cx="8" cy="8" rx="5.8" ry="4.4" fill="none" stroke="%s" stroke-width="1.3" stroke-dasharray="2.2 1.6"/>',
     'poly':   '<path d="M3 11 4.5 4 9 2.8 13 7 10 13Z" fill="none" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>',
     'line':   '<path d="M3 13 13 3" stroke="%s" stroke-width="1.4" stroke-linecap="round"/><circle cx="3" cy="13" r="1.4" fill="%s"/><circle cx="13" cy="3" r="1.4" fill="%s"/>',
     'sidebar':'<rect x="1.5" y="3" width="13" height="10" rx="2" fill="none" stroke="%s" stroke-width="1.2"/><path d="M6 3v10" stroke="%s" stroke-width="1.2"/>',
     'inspector':'<rect x="1.5" y="3" width="13" height="10" rx="2" fill="none" stroke="%s" stroke-width="1.2"/><path d="M10 3v10" stroke="%s" stroke-width="1.2"/>',
     'save':   '<rect x="2" y="3" width="12" height="3" rx="1" fill="none" stroke="%s" stroke-width="1.2"/><path d="M3 6v6.5h10V6M6.5 9h3" fill="none" stroke="%s" stroke-width="1.2" stroke-linecap="round"/>',
     'folder': '<path d="M2 4.5h4l1.2 1.5H14v6.5H2Z" fill="none" stroke="%s" stroke-width="1.2" stroke-linejoin="round"/>',
     'cube':   '<path d="M8 1.8 13.5 5v6L8 14.2 2.5 11V5ZM2.5 5 8 8.2 13.5 5M8 8.2v6" fill="none" stroke="%s" stroke-width="1.2" stroke-linejoin="round"/>',
     # sidebar steps
     's_si':   '<rect x="2" y="2" width="12" height="12" fill="none" stroke="%s" stroke-width="1.2"/><path d="M2 6h12M2 10h12M6 2v12M10 2v12" stroke="%s" stroke-width="1"/>',
     's_el':   '<circle cx="5" cy="9" r="3.2" fill="none" stroke="%s" stroke-width="1.2"/><circle cx="11" cy="6" r="3.2" fill="none" stroke="%s" stroke-width="1.2"/>',
     's_reg':  '<rect x="2.5" y="3.5" width="11" height="9" fill="none" stroke="%s" stroke-width="1.3" stroke-dasharray="2.2 1.6"/><circle cx="8" cy="8" r="1.6" fill="%s"/>',
     's_q':    '<path d="M12 3H4.5L9 8l-4.5 5H12" fill="none" stroke="%s" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',
     's_ex':   '<path d="M8 2v8M5 5l3-3 3 3M3 9v4.5h10V9" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>',
     'warn':   '<path d="M8 2 14.5 13.5h-13Z" fill="#f5a623"/><path d="M8 6.5v3.4" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/><circle cx="8" cy="11.8" r=".9" fill="#fff"/>',
    }[kind]
    n = p.count('%s')
    return f'<svg width="{s}" height="{s}" viewBox="0 0 16 16" style="flex:none">{p % tuple([c]*n)}</svg>'

# ---------- plots ----------
def gauss(x, mu, h, fw=0.08):
    s = fw/2.355
    return h*math.exp(-0.5*((x-mu)/s)**2)
def spec(e, comp):
    # per-channel expected counts (10 eV channels)
    bg = 38*math.exp(-(e-0.5)/0.9)+14 + (6 if e>1.56 else 0)*0 
    if e<1.5596: bg*= 1.0
    else: bg*=0.82   # Al K-edge step
    y = bg
    lines = [(0.930,comp['Cu']*0.9,0.075),(1.098,comp['Ga'],0.080),(1.254,comp['Mg'],0.085),(1.486,comp['Al'],0.092),(1.740,comp['Si'],0.098),(2.12,comp['Cu']*0.0,0.1)]
    for mu,h,fw in lines: y += gauss(e,mu,h,fw)
    y += gauss(e,1.486*0+0.525,comp['O'],0.07)
    # Al sum/tail shoulder
    y += 0.0018*comp['Al']*math.exp(-((e-1.60)/0.08)**2) if e>1.5 else 0
    return y

def bgonly(e):
    bg = 38*math.exp(-(e-0.5)/0.9)+14
    return bg*(0.82 if e>=1.5596 else 1.0)

def plot(W,H,res_h,comp,over=None,xmin=0.5,xmax=2.4,ymin=10,ymax=2e5,markers=True,fit=True,seed=1,legend=None, resid_label=True):
    rnd = random.Random(seed)
    L,R,T = 46,12,10
    ph = H-res_h-26-T   # plot height
    pw = W-L-R
    def X(e): return L+(e-xmin)/(xmax-xmin)*pw
    def Y(v): 
        v=max(v,ymin); return T+ph-(math.log10(v)-math.log10(ymin))/(math.log10(ymax)-math.log10(ymin))*ph
    o=[f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,Helvetica Neue,Arial" font-size="10">']
    o.append(f'<rect width="{W}" height="{H}" fill="#fff"/>')
    # grid
    k=int(math.log10(ymin))
    while 10**k<=ymax:
        yy=Y(10**k); o.append(f'<line x1="{L}" x2="{W-R}" y1="{yy:.1f}" y2="{yy:.1f}" stroke="#ececec"/><text x="{L-6}" y="{yy+3:.1f}" text-anchor="end" fill="#777">10<tspan dy="-4" font-size="7">{k}</tspan></text>'); k+=1
    xt=xmin
    while xt<=xmax+1e-9:
        xx=X(xt); o.append(f'<line x1="{xx:.1f}" x2="{xx:.1f}" y1="{T}" y2="{T+ph}" stroke="#f1f1f1"/>'); xt=round(xt+0.2,2)
    # markers
    if markers:
        for nm,mu,c in [('Cu Lα',0.930,COL['Cu']),('Ga Lα?',1.098,'#9a9a9a'),('Mg Kα',1.254,COL['Mg']),('Al Kα',1.486,COL['Al']),('Si Kα',1.740,COL['Si'])]:
            xx=X(mu); o.append(f'<line x1="{xx:.1f}" x2="{xx:.1f}" y1="{T}" y2="{T+ph}" stroke="{c}" stroke-width="1" stroke-dasharray="3 3" opacity=".75"/><text x="{xx+3:.1f}" y="{T+10}" fill="{c}" font-weight="{'400' if '?' in nm else '600'}" font-style="{'italic' if '?' in nm else 'normal'}">{nm}<title>{'Possible Ga L from FIB preparation. A suggestion, not an included element: accept it in Elements and maps to fit it.' if '?' in nm else nm}</title></text>')
        xx=X(1.5596); o.append(f'<line x1="{xx:.1f}" x2="{xx:.1f}" y1="{T+ph-34}" y2="{T+ph}" stroke="#888" stroke-dasharray="1 2"/><text x="{xx+2:.1f}" y="{T+ph-24}" fill="#888" font-size="9">Al K edge</text>')
    # data (grey steps)
    pts=[];fitp=[];resid=[]
    e=xmin; 
    while e<xmax:
        mu=spec(e+0.005,comp)
        n=max(0,rnd.gauss(mu,math.sqrt(mu)))
        # model slightly off at the Mg/Al overlap to look real
        fitv=mu
        pts.append((e,n)); fitp.append((e,fitv)); resid.append((e,(n-fitv)/math.sqrt(max(fitv,1))))
        e+=0.01
    d=' '.join(f'{X(a):.1f},{Y(b):.1f}' for a,b in pts)
    o.append(f'<polyline points="{d}" fill="none" stroke="#9a9a9a" stroke-width="1"/>')
    if over:
        d2=' '.join(f'{X(a):.1f},{Y(spec(a,over)):.1f}' for a,_ in pts)
        o.append(f'<polyline points="{d2}" fill="none" stroke="{over["col"]}" stroke-width="1.3" stroke-dasharray="4 2"/>')
    dbg=' '.join(f'{X(a):.1f},{Y(bgonly(a)):.1f}' for a,_ in pts)
    o.append(f'<polyline points="{dbg}" fill="none" stroke="#a9772a" stroke-width="1.2" stroke-dasharray="1.5 2.5"/>')
    if fit:
        d3=' '.join(f'{X(a):.1f},{Y(b):.1f}' for a,b in fitp)
        o.append(f'<polyline points="{d3}" fill="none" stroke="#0a60ff" stroke-width="1.4"/>')
    o.append(f'<rect x="{L}" y="{T}" width="{pw}" height="{ph}" fill="none" stroke="#c9c9c9"/>')
    # residual strip
    ry=T+ph+4; rh=res_h
    o.append(f'<rect x="{L}" y="{ry}" width="{pw}" height="{rh}" fill="#fafafa" stroke="#d6d6d6"/><line x1="{L}" x2="{W-R}" y1="{ry+rh/2}" y2="{ry+rh/2}" stroke="#bbb"/>')
    dr=' '.join(f'{X(a):.1f},{ry+rh/2-max(-3,min(3,b))/3*(rh/2-2):.1f}' for a,b in resid)
    o.append(f'<polyline points="{dr}" fill="none" stroke="#444" stroke-width=".8"/>')
    if resid_label: o.append(f'<text x="{L-6}" y="{ry+rh/2+3}" text-anchor="end" fill="#777">res σ</text><text x="{W-R-4}" y="{ry+9}" text-anchor="end" fill="#999" font-size="9">±3</text>')
    # axis
    ay=ry+rh
    xt=xmin
    while xt<=xmax+1e-9:
        xx=X(xt); o.append(f'<line x1="{xx:.1f}" x2="{xx:.1f}" y1="{ay}" y2="{ay+4}" stroke="#888"/><text x="{xx:.1f}" y="{ay+15}" text-anchor="middle" fill="#666">{xt:.1f}</text>'); xt=round(xt+0.2,2)
    o.append(f'<text x="{W-R}" y="{ay+15}" text-anchor="end" fill="#888" font-size="9">keV</text>')
    o.append(f'<text x="12" y="{T+ph/2}" fill="#777" transform="rotate(-90 12 {T+ph/2})" text-anchor="middle">counts / 10 eV</text>')
    o.append('</svg>'); return ''.join(o)

PREC=dict(Al=46000,Mg=1250,Si=1150,Cu=300,Ga=40,O=60,col='#e8590c')
MAT =dict(Al=47500,Mg=330,Si=260,Cu=60,Ga=28,O=55,col='#8e8e93')
MATn=dict(Al=46000,Mg=320,Si=252,Cu=58,Ga=27,O=53,col='#8e8e93')   # matrix normalised to Al K

def mapimg(S, kind='mix', cursor=None, region=None, seed=3):
    r=random.Random(seed)
    o=[f'<svg width="{S}" height="{S}" viewBox="0 0 {S} {S}" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,Helvetica Neue,Arial" font-size="10">',
       '<defs><filter id="nz%d"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="4"/><feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 .5 0"/></filter><filter id="bl%d"><feGaussianBlur stdDeviation="1.1"/></filter></defs>'%(S,S),
       f'<rect width="{S}" height="{S}" fill="#101a33"/>']
    if kind=='mix':
        o.append(f'<g filter="url(#bl{S})">')
        for i in range(34):
            cx=r.uniform(10,S-10);cy=r.uniform(10,S-10);a=r.choice([0,0,90,45,-45])
            l=r.uniform(S*0.05,S*0.17)
            o.append(f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="{l:.0f}" ry="{l*0.14:.1f}" transform="rotate({a} {cx:.0f} {cy:.0f})" fill="#c8c14a" opacity=".85"/>')
        for i in range(8):
            cx=r.uniform(10,S-10);cy=r.uniform(10,S-10)
            o.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{S*0.022:.1f}" fill="{COL["Cu"]}"/>')
        # cell boundary Si segregation
        o.append(f'<path d="M0 {S*.35} Q{S*.4} {S*.25} {S*.6} {S*.5} T{S} {S*.62}" stroke="{COL["Si"]}" stroke-width="2.5" fill="none" opacity=".8"/>')
        o.append('</g>')
        o.append(f'<rect width="{S}" height="{S}" filter="url(#nz{S})"/>')
    return o

def map_pane_img(S):
    o=mapimg(S)
    # selected region (polygon drawn) around needles + scale bar
    o.append(f'<path d="M{S*.22} {S*.30} L{S*.52} {S*.22} L{S*.74} {S*.46} L{S*.58} {S*.70} L{S*.28} {S*.62}Z" fill="#e8590c" fill-opacity=".14" stroke="#e8590c" stroke-width="1.5" stroke-dasharray="4 3"/>')
    o.append(f'<circle cx="{S*.58}" cy="{S*.40}" r="3" fill="#fff" stroke="#000"/>')
    o.append(f'<rect x="8" y="{S-14}" width="40" height="2.5" fill="#fff"/><text x="8" y="{S-18}" fill="#fff">50 nm</text>')
    o.append('</svg>'); return ''.join(o)

def phasemap(S):
    r=random.Random(11)
    o=[f'<svg width="{S}" height="{S}" viewBox="0 0 {S} {S}" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,Helvetica Neue,Arial" font-size="10"><defs><filter id="bl2"><feGaussianBlur stdDeviation=".8"/></filter></defs>',
       f'<rect width="{S}" height="{S}" fill="#8aa6cf"/>']
    o.append('<g filter="url(#bl2)">')
    sel=[]
    for i in range(30):
        cx=r.uniform(12,S-12);cy=r.uniform(12,S-12);a=r.choice([0,90,0,90,45])
        l=r.uniform(S*.05,S*.15)
        o.append(f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="{l:.0f}" ry="{l*.15:.1f}" transform="rotate({a} {cx:.0f} {cy:.0f})" fill="#2fb36b"/>')
    for i in range(7):
        cx=r.uniform(12,S-12);cy=r.uniform(12,S-12)
        o.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{S*.024:.1f}" fill="#f0a020"/>')
    o.append('</g>')
    # selected-region highlight: outline all beta'' needles (white halo) -> approximated via hatch tint
    o.append(f'<rect width="{S}" height="{S}" fill="none" stroke="#fff" stroke-opacity=".0"/>')
    cx,cy=S*.56,S*.42
    o.append(f'<g stroke="#fff" stroke-width="1.4"><line x1="{cx-12}" x2="{cx+12}" y1="{cy}" y2="{cy}"/><line x1="{cx}" x2="{cx}" y1="{cy-12}" y2="{cy+12}"/></g><circle cx="{cx}" cy="{cy}" r="7" fill="none" stroke="#fff" stroke-width="1.4"/>')
    o.append(f'<rect x="8" y="{S-14}" width="40" height="2.5" fill="#fff"/><text x="8" y="{S-18}" fill="#fff">50 nm</text>')
    # legend
    o.append(f'<g transform="translate({S-104},{S-64})"><rect width="98" height="58" rx="6" fill="#fff" fill-opacity=".88"/>'
             f'<circle cx="12" cy="14" r="5" fill="#8aa6cf"/><text x="22" y="17" fill="#222">Al matrix</text>'
             f'<circle cx="12" cy="30" r="5" fill="#2fb36b"/><text x="22" y="33" fill="#222" font-weight="700">β″  (selected)</text>'
             f'<circle cx="12" cy="46" r="5" fill="#f0a020"/><text x="22" y="49" fill="#222">Q (Cu)</text></g>')
    o.append('</svg>'); return ''.join(o)

def dp(S):
    o=[f'<svg width="{S}" height="{S}" viewBox="0 0 {S} {S}" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,Helvetica Neue,Arial" font-size="10"><defs><radialGradient id="g"><stop offset="0" stop-color="#fff"/><stop offset=".35" stop-color="#cfd8ff" stop-opacity=".9"/><stop offset="1" stop-color="#7f8cff" stop-opacity="0"/></radialGradient></defs><rect width="{S}" height="{S}" fill="#05060c"/>']
    c=S/2; a=S*.155
    for i in range(-3,4):
        for j in range(-3,4):
            x=c+i*a;y=c+j*a
            d=math.hypot(i,j)
            if x<6 or y<6 or x>S-6 or y>S-6: continue
            if d==0: rr=11
            else: rr=max(3.2,8.5-d*1.1)
            op=1 if d==0 else max(.25,.95-d*.17)
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rr*1.9:.1f}" fill="url(#g)" opacity="{op:.2f}"/>')
    # beta'' weak extra spots
    for i,j in [(.4,.2),(-.4,-.2),(.6,.8),(-.6,-.8),(1.4,.2),(-1.4,-.2),(.4,1.2),(-.4,-1.2)]:
        o.append(f'<circle cx="{c+i*a:.1f}" cy="{c+j*a:.1f}" r="2.4" fill="#9fb0ff" opacity=".45"/>')
    o.append(f'<rect x="8" y="{S-14}" width="46" height="2.5" fill="#fff"/><text x="8" y="{S-18}" fill="#ddd">5 mrad</text>')
    o.append('</svg>'); return ''.join(o)

# ---------- chrome ----------
def toolbar(verb="Quantify", tools_on=0, display="Al-Mg-Si_190330.emd · Spectroscopy · 256 × 256 px", linked=False, W=1280, IW=320, dleft=None, dw=330):
    cube=W-IW-44; fol=cube-36; sav=fol-36; vb=sav-104
    if dleft is None: dleft=vb-dw-24
    return f'''<div class="tb" style="width:{W}px"><div class="tl"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>
<div class="tbicon" style="left:92px">{icon('sidebar','#555',18)}</div>
<div class="tbdisp" style="left:{dleft}px;width:{dw}px">{display}</div>
<div class="verb" style="left:{vb}px">{verb}</div>
<div class="tbicon" style="left:{sav}px">{icon('save','#555',18)}</div>
<div class="tbicon" style="left:{fol}px">{icon('folder','#555',18)}</div>
<div class="tbicon" style="left:{cube}px">{icon('cube','#555',18)}</div>
<div class="tbicon" style="left:{W-44}px">{icon('inspector','#555',18)}</div></div>'''

def tools_hdr(on=1):
    return '<span class="tools2">'+''.join(f'<span class="tool{" on" if i==on else ""}">{icon(k,"#444",14)}</span>' for i,k in enumerate(['point','rect','ellipse','poly','line']))+'</span>'

ROOMS=['Prepare','Imaging','Bragg Disks','Crystal Maps','Reconstruction','Spectroscopy','Results']
RIC=['scope','','','','','','']
STEPS=[('Spectrum image','s_si'),('Elements &amp; maps','s_el'),('Regions','s_reg'),('Quantify','s_q'),('Export','s_ex')]
def sidebar(step, regions, selreg):
    h='<div class="sb"><div class="sh">Workspace</div>'
    for i,r in enumerate(ROOMS):
        on = r=='Spectroscopy'
        h+=f'<div class="si{" on" if on else ""}"><span class="ricon">{icon("s_si" if on else "point","#666" if not on else "#0a60ff",15)}</span>{r}<span class="kb">⌘{i+1 if i<5 else (6 if r=="Spectroscopy" else 7)}</span></div>'
    h+='<div class="sh" style="margin-top:6px">Spectroscopy</div>'
    for i,(t,ic) in enumerate(STEPS):
        h+=f'<div class="si{" on" if i==step else ""}"><span class="ricon">{icon(ic,"#0a60ff" if i==step else "#666",15)}</span>{t}</div>'
    h+='<div class="sh" style="margin-top:6px">Regions</div>'
    for i,(c,n,px,ct) in enumerate(regions):
        h+=f'<div class="reg{" on" if i==selreg else ""}">{dot(c,5)}<div class="rt"><div class="rn">{n}</div><div class="rs">{px} px · {ct}</div></div></div>'
    h+='</div>'
    return h

def statusstrip(left,W=1280):
    return f'<div class="ss" style="width:{W}px"><span>{left}</span><span class="sr">Metal · 3.1 GB · resident</span></div>'

def pane_hdr(title, right='', left_x=0, w=0, top=0):
    return f'<div class="ph" style="left:{left_x}px;top:{top}px;width:{w}px"><span class="phl">{title}</span><span class="phr">{right}</span></div>'

def tgl(t,on): return f'<span class="tg{" on" if on else ""}">{t}</span>'

# ---------- SCREEN 1 ----------
def screen1(step=3, insp=None, wid='s1', W=1280, sb=True, IW=320, SBW=230):
    CX=SBW if sb else 0; CW=W-CX-IW; top=52; th=330; MW=290
    regs=[('#9aa0a6','Whole map','65 536','41.2 M'),('#8e8e93','Matrix (drawn)','52 900','31.6 M'),(COL['Mg'],'β″ precipitates (drawn)','1 842','4.31 M'),(COL['Cu'],'Cu-rich (drawn)','212','0.52 M')]
    sbh=sidebar(step,regs,2).replace('class="sb"',f'class="sb" style="width:{SBW}px"') if sb else ''
    o=[f'<div class="win" id="{wid}" style="width:{W}px">{toolbar("Quantify",W=W,IW=IW,dw=330 if W>1000 else 190)}{sbh}']
    o.append(f'<div class="pane" style="left:{CX}px;top:{top}px;width:{MW}px;height:{th}px;border-right:1px solid var(--sep);overflow:visible">')
    o.append(f'<div class="ph"><span class="phl">Map · ColorMix</span><span class="phr">{tools_hdr(1)}<span class="tg" style="margin-left:4px">⋯</span></span></div>')
    o.append(f'<div style="position:absolute;left:{(MW-246)//2}px;top:32px">{map_pane_img(246)}</div>')
    th_=''
    def sym(role,c):
        if role=='Quantify': return f'<svg width="9" height="9"><circle cx="4.5" cy="4.5" r="3.6" fill="{c}"/></svg>'
        if role=='Fit only': return '<svg width="9" height="9"><circle cx="4.5" cy="4.5" r="3.2" fill="none" stroke="#777" stroke-width="1.3"/></svg>'
        return ''
    for el,ct,on,role in [('Al',COL['Al'],True,'Quantify'),('Mg',COL['Mg'],True,'Quantify'),('Si',COL['Si'],True,'Quantify'),('Cu',COL['Cu'],False,'Quantify'),('O','#999',False,'Fit only')]:
        th_+=f'<span class="tile{" on" if on else ""}" title="{el} · {role} (set in the periodic table)"><span class="tt" style="background:linear-gradient(135deg,#111,{ct})">{chk(on)}</span><span class="nm">{el}{sym(role,ct)}</span></span>'
    o.append(f'<div style="position:absolute;left:7px;top:284px;display:flex;gap:4px">{th_}</div>')
    o.append('</div>')
    # results
    RX=CX+MW; RW=CW-MW
    o.append(f'<div class="pane" style="left:{RX}px;top:{top}px;width:{RW}px;height:{th}px">')
    o.append(f'<div class="ph"><span class="phl">Results · β″ pooled{badge("unvalidated")}</span><span class="phr">{seg(["at%","wt%"],0)}</span></div>')
    hdr=''.join(f'<span style="position:absolute;left:{x}px">{t}</span>' for x,t in [(10,'Element'),(96,'Net counts ± σ'),(230,'k-free ratio'),(350,'at% ± σ')])
    o.append(f'<div class="th">{hdr}</div>')
    data=[('Al',COL['Al'],'412 380 ± 650','1','88.1 ± 0.9',False),('Mg',COL['Mg'],'9 840 ± 130','0.0239 ± 0.0003','5.6 ± 1.1',True),('Si',COL['Si'],'9 010 ± 125','0.0219 ± 0.0003','5.1 ± 1.0',False),('Cu',COL['Cu'],'2 100 ± 60','0.0051 ± 0.0001','1.2 ± 0.3',False)]
    yy=48
    for el,c,n,k,a_,ex in data:
        o.append(f'<div class="tr" style="top:{yy-2}px"><span style="position:absolute;left:10px;display:flex;align-items:center;gap:6px"><svg width="10" height="10"><path d="M2 2.5 5 5.5 8 2.5" fill="none" stroke="#666" stroke-width="1.4" transform="{"" if ex else "rotate(-90 5 5)"}"/></svg>{dot(c,4)}<b>{el}</b></span><span style="position:absolute;left:96px" class="mono">{n}</span><span style="position:absolute;left:230px" class="mono">{k}</span><span style="position:absolute;left:350px" class="mono"><b>{a_}</b></span></div>')
        yy+=24
        if ex:
            o.append(f'<div class="sig" style="top:{yy-2}px;height:38px;line-height:17px;white-space:normal;padding-top:2px">Mg σ terms: counting 0.6 % · fit 0.4 % · k-factor 20 % flat<br>absorption 3 % · thickness 4 % → ±1.1 at% (k dominates)</div>'); yy+=40
    o.append(f'<div style="position:absolute;left:10px;top:{yy+8}px;font-size:12px;border-top:1px solid var(--sep);padding-top:8px;right:10px">Mg / Si net ratio <b class="mono">1.092 ± 0.021</b> <span class="sm">· k-free, counting only</span></div>')
    o.append('</div>')
    # spectrum
    sy=top+th; sh=714-th
    o.append(f'<div class="pane" style="left:{CX}px;top:{sy}px;width:{CW}px;height:{sh}px;border-top:1px solid var(--sep)">')
    o.append(f'<div class="ph"><span class="phl">Spectrum · β″ pooled <span class="sm">· ○ matrix, norm. to Al Kα</span></span><span class="phr">{tgl("Spectrum",True)}{tgl("Background",True)}{tgl("Model",True)}{tgl("Residual",True)}{tgl("Overlay",True)}{tgl("Log",True)}</span></div>')
    o.append(f'<div style="position:absolute;left:0;top:26px">{plot(CW,sh-26-26,44,PREC,over=MATn,seed=2)}</div>')
    o.append(f'<div class="foot">Least squares · empirical continuum + Al edge · Brown-Powell k (ε Super-X G1) · absorption 80 ± 15 nm · no escape peaks {badge("unvalidated")}</div>')
    o.append('</div>')
    o.append((insp or inspector_quantify()).replace('class="insp"',f'class="insp" style="left:{W-IW}px;width:{IW}px"'))
    o.append(statusstrip('Last run · Quantify — 0.4 s',W))
    o.append('</div>')
    return ''.join(o)

def insp_tabs(): return '<div class="itabs"><div class="cap"><span class="on">Settings</span><span>Info</span></div></div>'

def inspector_quantify(expert=False):
    r=insp_tabs()
    r+=row('Method', pop('Mg/Si in Al · LS · BP k',178))
    r+=row('Background', pop('Empirical + Al edge',178))
    r+=row('k-factors', pop('Brown-Powell (computed)',178))
    r+=row('Absorption', chk(True)+'<span class="v" style="margin-left:6px">4 detectors · TOA from file</span>')
    r+=row('Thickness', field('80',54)+'<span class="v" style="margin:0 5px">±</span>'+field('15',44)+'<span class="v" style="margin-left:5px">nm</span>')
    r+=row('Fit quality', '<span class="v mono">χ²ᵣ 1.04</span><span class="ok">●</span>')
    r+=disc('Expert', expert)
    return f'<div class="insp">{r}</div>'

# ---------- SCREEN 2 ----------
def screen2():
    CX=230; CW=730; top=52
    regs=[('#8aa6cf','Al matrix (phase)','52 900','31.6 M'),(COL['Mg'],'β″ (phase)','1 842','4.31 M'),(COL['Cu'],'Q (phase)','212','0.52 M'),('#e8590c','Needle 3 (object)','96','0.23 M')]
    o=[f'<div class="win" id="s2">{toolbar("Quantify",1,"Al-Mg-Si_190330 · Spectroscopy · scan + EDX")}{sidebar(2,regs,1)}']
    # notice
    o.append(f'<div class="notice" style="left:{CX}px;top:{top}px;width:{CW}px">{icon("warn","#f5a623",15)}<span style="white-space:nowrap"><b>Scan shapes differ</b> — 4D 256×256, EDX 256×255 (flyback): last row has no spectrum, excluded</span><span class="lnk" style="flex:none">Details</span></div>')
    ty=top+30
    pw1=365
    # scan pane
    o.append(f'<div class="pane" style="left:{CX}px;top:{ty}px;width:{pw1}px;height:300px">'
             f'<div class="ph"><span class="phl">Scan · phase map {badge("unvalidated")}</span><span class="phr">{tools_hdr(0)}</span></div>'
             f'<div style="position:absolute;left:{(pw1-262)//2}px;top:30px">{phasemap(262)}</div></div>')
    o.append(f'<div class="pane" style="left:{CX+pw1}px;top:{ty}px;width:{CW-pw1}px;height:300px;border-left:1px solid var(--sep)">'
             f'<div class="ph"><span class="phl">Diffraction · cursor (142, 87)</span><span class="phr">{tgl("Mean of region",False)}</span></div>'
             f'<div style="position:absolute;left:{(CW-pw1-262)//2}px;top:30px">{dp(262)}</div></div>')
    sy=ty+300; sh=714-30-300
    o.append(f'<div class="pane" style="left:{CX}px;top:{sy}px;width:{CW}px;height:{sh}px;border-top:1px solid var(--sep)">'
             f'<div class="ph"><span class="phl">Spectrum · β″ pooled, 1 842 px <span class="sm">· ○ matrix, norm. to Al Kα</span></span><span class="phr">{tgl("Spectrum",True)}{tgl("Background",True)}{tgl("Model",True)}{tgl("Residual",True)}{tgl("Overlay",True)}{tgl("Log",True)}</span></div>'
             f'<div style="position:absolute;left:0;top:26px">{plot(CW,sh-26,40,PREC,over=MATn,seed=5)}</div></div>')
    # inspector
    r=insp_tabs()
    r+=row('Source', pop('Phase',150))
    r+=row('Phase', pop('β″ (Mg₅Si₆)',130)+badge())
    r+=row('Pixels', '<span class="v mono">1 842 · 2.8 %</span>')
    r+=row('Counts', '<span class="v mono">4.31 M</span>')
    r+=row('Live time', '<span class="v mono">37 s total · 20 ms/px mean</span>')
    r+=row('Line width', pop('3 px',70)+stepper(), 'dim')
    r+=row('Compare', pop('Al Kα · live time',160))
    o.append(f'<div class="insp">{r}<div class="note">Line width appears only for a drawn line (7th row). “Compare” names its basis: live time when the file stores it, otherwise the Al Kα reference.</div></div>')
    o.append(statusstrip('Last run · Phase map — 3.2 s'))
    o.append('</div>')
    return ''.join(o)


ROWS=[
 [(0,'H'),(17,'He')],
 [(0,'Li'),(1,'Be'),(12,'B'),(13,'C'),(14,'N'),(15,'O'),(16,'F'),(17,'Ne')],
 [(0,'Na'),(1,'Mg'),(12,'Al'),(13,'Si'),(14,'P'),(15,'S'),(16,'Cl'),(17,'Ar')],
 [(i,e) for i,e in enumerate('K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr'.split())],
 [(i,e) for i,e in enumerate('Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe'.split())],
 [(0,'Cs'),(1,'Ba'),(2,'*')]+[(i+3,e) for i,e in enumerate('Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn'.split())],
 [(0,'Fr'),(1,'Ra'),(2,'**')]+[(i+3,e) for i,e in enumerate('Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og'.split())],
]
QSET={'Al':COL['Al'],'Mg':COL['Mg'],'Si':COL['Si'],'Cu':COL['Cu']}
FSET={'O'}
SSET={'Ar':'Al sum or Ar?','Ga':'Ga L from FIB?'}
NOMEAS={'H','He','Li','Be'}
def ptable(top=8, X0=16, menu=False, bubbles=True):
    o=[]
    for r,row_ in enumerate(ROWS):
        for c,e in row_:
            x=X0+c*16; y=top+r*16
            if e in('*','**'):
                o.append(f'<div class="pc x" style="left:{x}px;top:{y}px">{e}</div>'); continue
            if e in QSET: o.append(f'<div class="pc q" style="left:{x}px;top:{y}px;background:{QSET[e]}" title="{e} · Quantify">{e}</div>')
            elif e in FSET: o.append(f'<div class="pc f" style="left:{x}px;top:{y}px" title="{e} · Fit only (deconvolution only)">{e}</div>')
            elif e in SSET: o.append(f'<div class="pc s" style="left:{x}px;top:{y}px" title="{SSET[e]}">{e}<i>?</i></div>')
            elif e in NOMEAS: o.append(f'<div class="pc x" style="left:{x}px;top:{y}px" title="{e}: no usable line in a Super-X EDX spectrum (below the window cut-off)">{e}</div>')
            else: o.append(f'<div class="pc o" style="left:{x}px;top:{y}px" title="{e} · Off">{e}</div>')
    yb=top+7*16+4
    o.append(f'<div class="row" style="position:absolute;left:4px;top:{yb}px;height:18px;width:312px;font-size:10.5px;color:#555"><svg width="10" height="10" style="margin-right:5px"><path d="M3.5 2 6.5 5 3.5 8" fill="none" stroke="#666" stroke-width="1.5"/></svg>Lanthanides · actinides</div>')
    yl=yb+20
    o.append(f'<div class="lgd" style="top:{yl}px"><span><b style="background:{COL["Mg"]}"></b>Quantify</span><span><b style="border:1.4px solid #777;background:#fff"></b>Fit only</span><span><b style="border:1.4px dotted #666;background:#fff"></b>Suggested ?</span><span><b style="background:#eeeef1"></b>Off</span></div>')
    if bubbles:
        o.append(f'<div class="bub" style="left:{X0+3*16}px;top:{top-1}px">Ga: from FIB?</div>')
        o.append(f'<div class="bub" style="left:{X0+8*16+2}px;top:{top-1}px">Ar: Al sum or Ar?</div>')
    if menu:
        mx=X0+1*16+10; my=top+2*16+16
        o.append(f'<div class="menu" style="left:{mx}px;top:{my}px;width:124px;z-index:8"><div style="font-size:10px;color:#888;height:16px;line-height:16px">Mg</div><div>✓ Quantify</div><div class="hl">Fit only</div><div>Off</div><div class="sep"></div><div>Lines  ▸  <span style="color:#888">K</span></div></div>')
    return f'<div class="pt" style="height:{yl+22}px">{"".join(o)}</div>', yl+22

# ---------- SCREEN 3 strip ----------
def card(title, rows_html, nrows, pts, extra=''):
    return f'<div class="card"><div class="ct">{title}</div><div class="insp flat">{rows_html}</div><div class="cost"><b>{nrows} rows</b> × 28 pt = <b>{pts} pt</b>{extra}</div></div>'

def inspector_elements():
    tbl,h=ptable(8,16,menu=True)
    rows=row('Suggestions','<span class="v">2 pending · Ar, Ga</span><span class="mini">Review</span>')+row('Map shows',pop('Net counts',120))+row('Smoothing',pop('3 × 3 · σ 1 px',120))
    return f'<div class="insp">{insp_tabs()}{tbl}<div style="height:6px"></div>{rows}</div>'

def strip():
    c=[]
    r=row('Source', '<span class="v" title="Linked to the 4D scan: EDX 256 × 255 vs scan 256 × 256 (hover: details)">Linked 4D · shape differs</span>'+icon('warn','#f5a623',13))
    r+=row('Frame range', field('1',40)+'<span class="v" style="margin:0 4px">–</span>'+field('24',40)+'<span class="v" style="margin-left:4px">of 24</span>')
    r+=row('Energy axis', pop('Refined',90)+'<span class="v mono" style="margin-left:6px">+4 eV, 9.98 eV/ch</span>')
    r+=row('Counts / px', '<svg width="120" height="18"><g fill="#8aa6cf">'+''.join(f'<rect x="{i*6}" y="{18-h}" width="5" height="{h}"/>' for i,h in enumerate([16,13,10,8,6,5,3,2,2,1]))+'</g></svg><span class="v mono" style="margin-left:6px">median 11</span>')
    r+=row('Live / dead', '<span class="v mono">1311 s total · dead 52 %</span>')
    r+=row('Geometry', '<span class="v">TOA 18° · 4 det. · 0.12 sr</span>')
    c.append(card('1 · Spectrum image', r, 6, 168, '<br><span class="sm">5 of 6 are readouts. Source merges source + registration; the warning icon opens the shapes on hover</span>'))
    c.append(card('2 · Elements &amp; maps', '<div class="row"><span class="v">Periodic table + 3 rows: drawn in screen 4</span></div>', 3, 84, ' + table 168 pt = <b>252 pt</b>'))
    r=row('Source', pop('Phase',110))+row('Phase', pop('β″ (Mg₅Si₆)',110)+badge())+row('Pixels','<span class="v mono">1 842</span>')+row('Counts','<span class="v mono">4.31 M</span>')+row('Live time','<span class="v mono">37 s · 20 ms/px</span>')+row('Line width',pop('3 px',60),'dim')+row('Compare',pop('Al Kα · live time',140))
    c.append(card('3 · Regions', r, 6, 168, '<br><span class="sm">6 rows in use (168 pt); the 7th, Line width (dimmed), appears only for a drawn line = 196 pt</span>'))
    r=row('Method', pop('Mg/Si in Al',110))+row('Background', pop('Empirical + Al edge',150))+row('k-factors', pop('Brown-Powell',110))+row('Absorption', chk()+'<span class="v" style="margin-left:6px">4 det.</span>')+row('Thickness', field('80',46)+'<span class="v" style="margin:0 3px">±</span>'+field('15',40)+'<span class="v"> nm</span>')+row('Fit quality','<span class="v mono">χ²ᵣ 1.04</span>')+disc('Expert',True)
    r+=row('Estimator', pop('Least squares',110))+row('σ_k', field('20',44)+'<span class="v"> %</span>')+row('Poly order', pop('4',60))+row('Energy axis', pop('Refined',90)+'<span class="v">·</span>'+chk(True)+'<span class="v">lock</span>')
    c.append(card('4 · Quantify (Expert open)', r, 11, 308, '<br><span class="sm">7 rows closed = 196 pt; Expert adds 4 = 308 pt</span>'))
    r=row('Format', pop('CSV',100))+row('Include', chk()+'<span class="v" style="margin-left:6px">method and σ terms</span>')+row('', '<span class="btn">Export…</span>')
    c.append(card('5 · Export', r, 3, 84, '<br><span class="sm">Plain (non-prominent) button; the toolbar verb stays Quantify. Also File › Export…</span>'))
    return '<div class="stripwrap">'+''.join(c)+'</div>'

CSS = '''
.pt{position:relative;width:320px;background:#f6f6f8}.pc{position:absolute;width:16px;height:16px;font-size:8.5px;line-height:16px;text-align:center;border-radius:3px;box-sizing:border-box;font-weight:600}.pc.q{color:#fff}.pc.f{border:1.4px solid #777;line-height:13px;color:#333;background:#fff}.pc.s{border:1.4px dotted #666;line-height:13px;color:#333;background:#fff}.pc.o{background:#e9e9ee;border:1px solid #d9d9df;line-height:14px;color:#555;font-weight:500}.pc.x{color:#c3c3c8;font-weight:500}.pc.s i{position:absolute;right:-1px;top:-6px;font-size:7px;font-style:normal;color:#a35a00;background:#fff0d6;border-radius:4px;padding:0 2px;line-height:9px}.bub{position:absolute;background:#2b2b2e;color:#fff;font-size:10.5px;padding:3px 7px;border-radius:5px;white-space:nowrap;z-index:6}.menu .sep{height:1px;background:#e2e2e6;margin:3px 2px;padding:0}.menu .dis{color:#999}.lgd{position:absolute;left:16px;font-size:10px;color:#555;display:flex;gap:10px;align-items:center}.lgd span{display:inline-flex;align-items:center;gap:3px}.lgd b{display:inline-block;width:10px;height:10px;border-radius:2px;box-sizing:border-box}.panel{display:flex;gap:0;width:max-content;border:1px solid var(--sep);border-radius:8px;overflow:hidden;background:#fff}.pcol{width:230px;background:#eeeef2;padding:6px 8px}.pins{width:320px;background:#f6f6f8;border-left:1px solid var(--sep);position:relative}.card .row.tall{height:auto}
:root{--sep:#d9d9de;--bg:#f6f6f8;--ink:#1d1d1f;--sec:#6e6e73;--acc:#0a60ff}
*{box-sizing:border-box}
body{margin:0;background:#e9e9ee;font-family:-apple-system,"SF Pro Text","Helvetica Neue",Arial,sans-serif;font-size:13px;color:var(--ink)}
.page{width:1320px;margin:0 auto;padding:16px 20px 40px}
h1{font-size:18px;margin:6px 0 2px} .banner{background:#fff3cd;border:1px solid #e0c36a;color:#6b5200;padding:6px 10px;border-radius:6px;font-weight:600;display:inline-block;margin-bottom:6px}
.cap1{color:#555;margin:4px 0 8px;font-size:12px;max-width:1280px}
.win{position:relative;width:1280px;height:800px;background:#fff;border:1px solid #b9b9bf;border-radius:14px;overflow:hidden;box-shadow:0 8px 30px rgba(0,0,0,.18);margin-bottom:6px}
.tb{position:absolute;left:0;top:0;width:1280px;height:52px;background:#f3f3f6;border-bottom:1px solid var(--sep)}
.tl{position:absolute;left:18px;top:19px;display:flex;gap:8px}.tl i{width:12px;height:12px;border-radius:6px;display:block}
.tbicon{position:absolute;top:14px;width:28px;height:24px;display:flex;align-items:center;justify-content:center}
.tbdisp{position:absolute;top:12px;height:28px;border-radius:14px;background:#e8e8ed;display:flex;align-items:center;justify-content:center;font-size:12px;color:#444;white-space:nowrap;overflow:hidden}
.tools{position:absolute;top:11px;height:30px;border-radius:15px;background:#e8e8ed;display:flex;padding:2px;gap:0}
.tools2{display:inline-flex;background:#e8e8ed;border-radius:11px;padding:1px;margin-left:4px}.tools2 .tool{width:24px;height:20px;border-radius:10px}.tool{width:30px;height:26px;display:flex;align-items:center;justify-content:center;border-radius:13px}.tool.on{background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.18)}
.tbtip{position:absolute;top:38px;font-size:9px;color:#999;display:none}
.verb{position:absolute;top:11px;height:30px;padding:0 16px;border-radius:15px;background:var(--acc);color:#fff;font-weight:600;font-size:13px;display:flex;align-items:center}
.sb{position:absolute;left:0;top:52px;width:230px;height:714px;background:#eeeef2;border-right:1px solid var(--sep);padding:6px 8px;overflow:hidden}
.sh{font-size:11px;font-weight:600;color:var(--sec);padding:4px 8px 2px;height:22px}
.si{height:28px;display:flex;align-items:center;padding:0 8px;border-radius:7px;font-size:13px;gap:8px}.si.on{background:rgba(10,96,255,.15);color:#0a3fa8;font-weight:500}
.ricon{width:16px;display:flex}.kb{margin-left:auto;color:#999;font-size:11px}
.reg{height:38px;display:flex;align-items:center;gap:8px;padding:0 8px;border-radius:7px}.reg.on{background:rgba(10,96,255,.15)}
.rn{font-size:13px;line-height:15px}.rs{font-size:11px;color:var(--sec);line-height:14px}.rt{min-width:0}
.insp{position:absolute;left:960px;top:52px;width:320px;height:714px;background:#f6f6f8;border-left:1px solid var(--sep);padding:0 0 0 0}
.insp.flat{position:static;width:auto;height:auto;border:0;background:transparent}
.itabs{height:40px;padding:7px 12px}.cap{height:26px;border-radius:13px;background:#e6e6eb;display:flex;padding:2px}.cap span{flex:1;text-align:center;line-height:22px;font-size:12px;border-radius:11px;color:#555}.cap .on{background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.15);color:#111}
.row{height:28px;display:flex;align-items:center;padding:0 12px;font-size:12px}.row .lab{width:86px;color:#444;flex:none}.row .ctl{flex:1;display:flex;align-items:center;justify-content:flex-end;gap:0;min-width:0}
.row.disc{color:#333}.row.dim{opacity:.45}.row.sub{padding:0 12px}
.v{font-size:12px;color:#333;white-space:nowrap}.mono{font-variant-numeric:tabular-nums}
.pop{position:relative;display:inline-flex;align-items:center;height:20px;border-radius:5px;background:#fff;border:1px solid #d3d3d8;box-shadow:0 1px 1px rgba(0,0,0,.06);padding:0 6px 0 8px;font-size:12px;gap:6px;justify-content:space-between;max-width:100%}
.pt{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.chev{flex:none}
.seg{display:inline-flex;background:#e6e6eb;border-radius:6px;padding:2px}.sg{padding:1px 12px;font-size:12px;border-radius:5px;color:#444}.sg.on{background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.2);color:#000}
.cb{display:inline-flex;width:15px;height:15px;border-radius:4px;border:1px solid #c4c4c9;background:#fff;align-items:center;justify-content:center;flex:none}.cb.on{background:var(--acc);border-color:var(--acc)}
.fld{display:inline-flex;height:20px;border:1px solid #d3d3d8;background:#fff;border-radius:4px;align-items:center;justify-content:flex-end;padding:0 6px;font-size:12px;font-variant-numeric:tabular-nums}
.stp{display:inline-flex;margin-left:4px;width:16px;height:20px;border:1px solid #d3d3d8;background:#fff;border-radius:4px;align-items:center;justify-content:center}
.badge{display:inline-block;padding:0 6px;height:16px;line-height:16px;border-radius:8px;background:#fff0d6;color:#a35a00;border:1px solid #f0c27a;font-size:10px;font-weight:600;margin-left:6px;white-space:nowrap}
.ok{color:#28a745;font-size:10px;margin-left:6px}
.mini{margin-left:6px;height:18px;line-height:16px;padding:0 7px;border:1px solid #d3d3d8;border-radius:4px;background:#fff;font-size:11px}
.note{font-size:11px;color:var(--sec);padding:10px 14px;line-height:1.35}
.pane{position:absolute;background:#fff;overflow:hidden}
.ph{white-space:nowrap;position:absolute;left:0;top:0;right:0;height:26px;background:#f6f6f8;border-bottom:1px solid var(--sep);display:flex;align-items:center;justify-content:space-between;padding:0 8px;font-size:11px;font-weight:600;color:#444}
.phr{display:flex;gap:4px;align-items:center;font-weight:400}.tile{width:52px;height:40px;border:1px solid #d3d3d8;border-radius:6px;background:#fff;overflow:hidden;position:relative}.tile.on{border-color:#b5cdf7}.tile .tt{display:block;height:22px;position:relative}.tile .tt .cb{position:absolute;left:3px;top:3px;width:12px;height:12px;border-radius:3px}.tile .nm{display:flex;justify-content:space-between;align-items:center;padding:0 4px 0 6px;height:16px;font-size:11px;font-weight:600;color:#333}.rg{display:inline-flex;width:14px;height:12px;border-radius:6px;background:#ececf0;align-items:center;justify-content:center}.menu{position:absolute;width:104px;background:#fff;border:1px solid #cfcfd4;border-radius:7px;box-shadow:0 6px 18px rgba(0,0,0,.25);padding:3px;font-size:12px;z-index:5}.menu div{height:20px;line-height:20px;padding:0 8px;border-radius:4px}.menu .hl{background:#0a60ff;color:#fff}.btn{display:inline-flex;height:22px;align-items:center;padding:0 12px;border:1px solid #cfcfd4;border-radius:6px;background:#fff;font-size:12px;box-shadow:0 1px 1px rgba(0,0,0,.08)}.sm{font-size:10.5px;color:var(--sec);font-weight:400}
.tg{padding:1px 7px;border-radius:9px;font-size:10.5px;color:#666;border:1px solid #d3d3d8;background:#fff}.tg.on{background:#e3edff;color:#0a3fa8;border-color:#b5cdf7}
.maplg{position:absolute;font-size:11px;line-height:1.5;width:500px;color:#333}
.strip{position:absolute;display:flex;gap:6px;align-items:stretch;height:34px}
.thumb{display:inline-flex;align-items:center;gap:5px;padding:2px 6px 2px 3px;border:1px solid #d3d3d8;border-radius:6px;background:#fff}.thumb.on{border-color:#b5cdf7;background:#f2f7ff}
.tm{width:26px;height:26px;border-radius:3px;display:block}.tn{font-weight:700;font-size:12px}.tc{display:inline-flex}
.th{position:absolute;left:0;right:0;top:26px;height:20px;border-bottom:1px solid var(--sep);font-size:11px;color:var(--sec);font-weight:600;background:#fcfcfd}.th span{top:3px}
.tr{position:absolute;left:0;right:0;height:24px;font-size:12px;line-height:24px}.tr>span{top:0}
.sig{position:absolute;left:30px;right:10px;height:22px;font-size:11px;line-height:22px;background:#f4f6fb;border-left:2px solid #9bb7f0;padding-left:8px;color:#333;white-space:nowrap;overflow:hidden}
.foot{position:absolute;left:0;right:0;bottom:0;height:26px;border-top:1px solid var(--sep);background:#f6f6f8;font-size:11px;color:#444;display:flex;align-items:center;padding:0 10px;white-space:nowrap;overflow:hidden}
.ss{position:absolute;left:0;top:766px;width:1280px;height:34px;background:#f0f0f3;border-top:1px solid var(--sep);display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-size:11px;color:#555}
.notice{position:absolute;height:30px;background:#fff6dd;border-bottom:1px solid #ecd48c;display:flex;align-items:center;gap:8px;padding:0 10px;font-size:11px;color:#5b4500;white-space:nowrap;overflow:hidden}.lnk{color:var(--acc);margin-left:auto}
.stripwrap{display:flex;gap:12px;align-items:flex-start;width:1280px;flex-wrap:wrap}
.card{width:306px;background:#f6f6f8;border:1px solid var(--sep);border-radius:8px;overflow:hidden;font-size:12px}.ct{font-weight:600;padding:8px 12px;border-bottom:1px solid var(--sep);background:#fff}
.cost{padding:6px 12px 8px;border-top:1px dashed #ccc;font-size:11.5px;color:#333;background:#fff}
h2{font-size:15px;margin:22px 0 4px}
.ann{width:1280px;font-size:12px;color:#444;margin:4px 0 14px}
'''
html=f'''<!doctype html><html><head><meta charset="utf-8"><title>Spectroscopy room mock</title><style>{CSS}</style></head><body><div class="page">
<div class="banner">MOCK — numbers illustrative. Static picture for structure review; no app code. Light appearance, 1:1 points, window 1280 × 800.</div>
<h1>Spectroscopy room — mac4DSTEM v5.0 (ADR 054 item 8)</h1>
<div class="cap1">Anatomy copied from the live shell: toolbar 52 (display · verb · icons), sidebar 230, inspector 320, pane headers 26, status strip 34. Sidebar keeps the real two sections (Workspace rooms; the room's tasks) and adds Regions.</div>
<h2>Screen 1 — spectrum image alone · step “Quantify”</h2>
{screen1()}
<div class="ann">Content 730 × 714 pt: top row 330 (map pane 290 wide: header 26 + 246-pt square image + 40-pt tile strip; results 440 wide) · spectrum 384 (header 26 + plot 332 + fit footer 26). Draw tools sit in the map header; the Cu role menu is drawn open for illustration. Inspector 7 rows × 28 = 196 pt; the toolbar verb is the only filled button.</div>
<h2>Screen 2 — linked to a 4D scan · step “Regions”</h2>
{screen2()}
<div class="ann">Content: registration notice 30 · scan (draw tools in its header) | diffraction 300 · pooled spectrum 354. Inspector 6 rows (+1 conditional) = 168 pt (196).</div>
<h2>Screen 4 — Elements &amp; maps step selected (periodic table in place)</h2>
{screen1(1, inspector_elements(), "s4")}

<div class="ann">Inspector: periodic table 18 × 16-pt cells (288 pt wide) = <b>168 pt</b> (7 rows × 16 + collapsed f-block row + legend + padding) plus 3 rows × 28 = 84 pt → <b>252 pt</b>. Click a cell: Quantify ↔ Off. Right-click: Quantify · Fit only · Off · Lines (menu drawn open on Mg). Hover bubbles on the dotted cells are drawn for illustration. H, He, Li, Be are greyed (reason on hover). Lanthanides/actinides sit in a collapsed row (not omitted). Auto ID never removes a pick; there is no Apply step, the fit is live.</div>
<h2>Screen 3 — the other steps' inspectors (rows only)</h2>
{strip()}
<h2>Narrow checks (915 pt)</h2><div class="ann">A: policy behaviour (sidebar collapses below 1095, inspector 320). B: sidebar 190 + inspector 280 both kept.</div>{screen1(3,None,'s915a',915,False,320)}<div style="height:14px"></div>{screen1(3,None,'s915b',915,True,280,190)}</div></body></html>'''
open('/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/728f2f43-fd1b-42d1-b3b3-d9a24002fb3e/scratchpad/mock/spectroscopy-mock.html','w').write(html)
print(len(html))
