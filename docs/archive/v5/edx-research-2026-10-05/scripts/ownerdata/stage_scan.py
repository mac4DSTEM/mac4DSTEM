import h5py, json, datetime, sys
R=[json.loads(l) for l in open('emd_scan.jsonl')]
root='<owner-ssd>/'
sel=[r for r in R if 'GRK_LMW_LPBF_AlMgSi' in r['path'] and 'SpectrumStream' in r.get('types',{}) and 'archive' not in r['path']]
def meta(ds,col=0):
    raw=bytes(ds[:,col]).split(b'\x00')[0]; return json.loads(raw.decode('utf-8','replace'))
rows=[]
for r in sel:
    with h5py.File(root+r['path'],'r') as f:
        g=f['Data/SpectrumStream']; u=list(g.keys())[0]; m=meta(g[u]['Metadata'])
        st=m['Stage']; pos=st['Position']
        ts=int(m['Acquisition']['AcquisitionStartDatetime']['DateTime'])
        t=datetime.datetime.fromtimestamp(ts,datetime.timezone.utc)+datetime.timedelta(hours=2)
        rows.append((t.strftime('%Y-%m-%d %H:%M'), float(pos['x'])*1e6, float(pos['y'])*1e6, float(pos['z'])*1e6, float(st['AlphaTilt'])*57.29578, float(st['BetaTilt'])*57.29578, m['Optics'].get('SpotIndex'), m['Optics'].get('CameraLength'), m['Scan']['ScanSize'], m['Scan']['DwellTime'], r['SpectrumStream'][0].get('frames'), r['path'].split('/')[-1], r['size']))
for x in sorted(rows):
    print(f"{x[0]} CEST  stage x={x[1]:9.1f} y={x[2]:9.1f} z={x[3]:8.1f} um  a={x[4]:6.2f} b={x[5]:6.2f}  spot {x[6]} CL {float(x[7])*1e3:.0f}mm scan {x[8]['width']}x{x[8]['height']} dwell {float(x[9])*1e6:.2f}us frames {x[10]} {x[12]/1e6:.0f}MB  {x[11]}")
