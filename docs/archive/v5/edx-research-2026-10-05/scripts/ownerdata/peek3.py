import h5py, sys, json
p=sys.argv[1]
def meta(ds,col=0):
    raw=bytes(ds[:,col]).split(b'\x00')[0]
    return json.loads(raw.decode('utf-8','replace'))
with h5py.File(p,'r') as f:
    g=f['Data/SpectrumStream']
    u=list(g.keys())[0]
    m=meta(g[u]['Metadata'])
    for k in ['Detectors','BinaryResult','Sample','CustomProperties']:
        print('==',k); print(json.dumps(m[k],indent=1)[:3500])
    s=g[u]['AcquisitionSettings'][0]
    print(type(s), str(s)[:1500])
    t=f['Data/SpectrumImage']; u2=list(t.keys())[0]
    print(str(t[u2]['SpectrumImageSettings'][0])[:1500])
    print(str(f['Data/Text'][list(f['Data/Text'].keys())[0]][()])[:300])
