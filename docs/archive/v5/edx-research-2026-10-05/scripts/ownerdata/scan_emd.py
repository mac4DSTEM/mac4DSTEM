import h5py, sys, json, os, time, datetime
files=[l.rstrip('\n') for l in open('find_ext.txt') if l.strip().lower().endswith('.emd')]
root='<owner-ssd>/'
def meta(ds,col=0):
    raw=bytes(ds[:,col]).split(b'\x00')[0]
    return json.loads(raw.decode('utf-8','replace'))
def g(m,*ks):
    for k in ks:
        if not isinstance(m,dict) or k not in m: return None
        m=m[k]
    return m
out=open('emd_scan.jsonl','w')
for rel in files:
    p=root+rel[2:]
    rec={'path':rel[2:]}
    try:
        st=os.stat(p); rec['size']=st.st_size; rec['mtime']=datetime.datetime.fromtimestamp(st.st_mtime).isoformat(timespec='minutes')
        with h5py.File(p,'r') as f:
            rec['top']=list(f.keys())
            rec['app']=list(f['Application'].keys()) if 'Application' in f else None
            d=f.get('Data')
            if d is None:
                rec['note']='no Data group'; out.write(json.dumps(rec)+'\n'); continue
            rec['types']={t:len(d[t]) for t in d.keys()}
            if 'Features' in f: rec['features']=list(f['Features'].keys())
            # images
            imgs=[]
            if 'Image' in d:
                for u,gg in d['Image'].items():
                    try:
                        sh=gg['Data'].shape
                        det=None
                        if 'Metadata' in gg:
                            m=meta(gg['Metadata']); det=g(m,'BinaryResult','Detector')
                            t0=g(m,'Acquisition','AcquisitionStartDatetime','DateTime')
                        imgs.append([det,list(sh)])
                    except Exception as e:
                        imgs.append(['err',str(e)[:60]])
            rec['images']=imgs[:12]
            if 'Spectrum' in d:
                sp=[]
                for u,gg in d['Spectrum'].items():
                    try: sp.append(list(gg['Data'].shape))
                    except Exception as e: sp.append('err')
                rec['spectra']=sp[:6]
            for T in ['SpectrumStream','SpectrumImage']:
                if T in d:
                    L=[]
                    for u,gg in d[T].items():
                        e={}
                        try:
                            e['data_shape']=list(gg['Data'].shape); e['dtype']=str(gg['Data'].dtype)
                            if 'FrameLocationTable' in gg: e['frames']=gg['FrameLocationTable'].shape[0]
                            if 'Metadata' in gg:
                                m=meta(gg['Metadata'])
                                e['start']=g(m,'Acquisition','AcquisitionStartDatetime','DateTime')
                                if e['start']:
                                    try: e['start_iso']=datetime.datetime.fromtimestamp(int(e['start']),datetime.timezone.utc).isoformat(timespec='minutes')
                                    except: pass
                                e['scan']=g(m,'Scan','ScanSize'); e['dwell']=g(m,'Scan','DwellTime'); e['area']=g(m,'Scan','ScanArea'); e['frametime']=g(m,'Scan','FrameTime')
                                e['fov']=g(m,'Optics','FullScanFieldOfView','x'); e['kv']=g(m,'Optics','AccelerationVoltage'); e['spot']=g(m,'Optics','SpotIndex'); e['cl']=g(m,'Optics','CameraLength'); e['conv']=g(m,'Optics','BeamConvergence')
                                e['inst']=g(m,'Instrument','InstrumentModel'); e['pix']=g(m,'BinaryResult','PixelSize','width'); e['bindet']=g(m,'BinaryResult','Detector')
                                dets=g(m,'Detectors') or {}
                                e['adets']=[ (v.get('DetectorName'), v.get('Dispersion'), v.get('BeginEnergy')) for v in dets.values() if isinstance(v,dict) and v.get('DetectorType')=='AnalyticalDetector' and v.get('Enabled')=='true']
                                e['scandets']=[v.get('DetectorName') for v in dets.values() if isinstance(v,dict) and v.get('DetectorType')=='ScanningDetector' and v.get('Enabled')=='true']
                                e['imgdets']=[(v.get('DetectorName'), v.get('Binning',{}).get('width') if isinstance(v.get('Binning'),dict) else None, v.get('ExposureTime')) for v in dets.values() if isinstance(v,dict) and v.get('DetectorType')=='ImagingDetector']
                                e['custom_det']=[k for k in (g(m,'CustomProperties') or {}) if 'Detector' not in k and 'Aperture' not in k][:8]
                        except Exception as ex:
                            e['err']=str(ex)[:100]
                        L.append(e)
                    rec[T]=L[:4]
    except Exception as ex:
        rec['error']=type(ex).__name__+': '+str(ex)[:120]
    out.write(json.dumps(rec)+'\n'); out.flush()
out.close()
print('done',len(files))
