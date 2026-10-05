import h5py, json
R=[json.loads(l) for l in open('emd_scan.jsonl')]
root='<owner-ssd>/'
def meta(ds,col=0):
    raw=bytes(ds[:,col]).split(b'\x00')[0]; return json.loads(raw.decode('utf-8','replace'))
sel=[r for r in R if r.get('SpectrumStream') and r['SpectrumStream'][0].get('frames')]
seen=set(); out=[]
for r in sel:
    s=r['SpectrumStream'][0]
    key=(r['size'],s.get('start'))
    if key in seen: continue
    seen.add(key)
    try:
        with h5py.File(root+r['path'],'r') as f:
            g=f['Data/SpectrumStream']; u=list(g.keys())[0]
            nc=g[u]['Metadata'].shape[1]
            m=meta(g[u]['Metadata'],nc-1)
            det=[v for v in m['Detectors'].values() if v.get('DetectorType')=='AnalyticalDetector' and v.get('Enabled')=='true']
            ndet=len(det)
            d=det[0] if det else {}
            ocr=float(d.get('OutputCountRate',0)); icr=float(d.get('InputCountRate',0))
            lt=float(d.get('LiveTime',0)); rt=float(d.get('RealTime',0))
            sc=s['scan']; npx=int(sc['width'])*int(sc['height']) if sc else 0
            # scan area fraction
            a=s.get('area') or {}
            try:
                fx=float(a['right'])-float(a['left']); fy=float(a['bottom'])-float(a['top'])
            except: fx=fy=1
            npx_eff=npx*fx*fy
            dw=float(s['dwell']); fr=s['frames']
            cpp=ocr*dw*fr
            out.append((r['path'].split('/')[-1],r['size']/1e6,s.get('start_iso'),ndet,icr,ocr,npx,round(fx*fy,3),dw*1e6,fr,cpp, s['data_shape'][0], s['data_shape'][0]/max(npx_eff*fr,1)))
    except Exception as e:
        out.append((r['path'],'err',str(e)[:50]))
json.dump(out,open('rates.json','w'))
for o in sorted(out,key=lambda x:str(x[2])):
    if len(o)>3: print(f"{o[2]} {o[1]:8.1f}MB ndet={o[3]} ICR={o[4]/1e3:6.1f}k OCR={o[5]/1e3:6.1f}k scan_px={o[6]} area_frac={o[7]} dwell={o[8]:.2f}us frames={o[9]} est_counts/px(OCR*dwell*frames)={o[10]:.1f} streamlen/(px*frames)={o[12]:.3f} {o[0][:55]}")
