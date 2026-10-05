import h5py, json
Z='H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U'.split()
R=[json.loads(l) for l in open('emd_scan.jsonl')]
root='<owner-ssd>/'
seen=set(); res={}
for r in R:
    if not r.get('SpectrumStream'): continue
    s=r['SpectrumStream'][0]; key=(r['size'],s.get('start'))
    if key in seen: continue
    seen.add(key)
    try:
        with h5py.File(root+r['path'],'r') as f:
            if 'Operations/SpectrumQuantificationOperation' not in f: res[r['path']]=None; continue
            for u,ds in f['Operations/SpectrumQuantificationOperation'].items():
                d=json.loads(ds[0].decode() if isinstance(ds[0],bytes) else ds[0])
                el=[Z[int(x)-1] for x in d.get('elementSelection',[]) if str(x).isdigit()]
                res[r['path']]=(el,d.get('ionizationCrossSectionModel'),d.get('absorptionCorrection',{}).get('useAbsorptionCorrection'))
                break
    except Exception as e:
        res[r['path']]=('err',str(e)[:60])
json.dump(res,open('elems.json','w'))
for k,v in sorted(res.items()):
    print(k.split('/')[-1][:60], v)
