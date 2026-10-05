import h5py, json, numpy as np
root='<owner-backup>/'
files={
 '190330 0603 65kx':'01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/emd_files/SI HAADF 1006 65000 x 20260603.emd',
 '190330 0603 91kx':'01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/emd_files/SI HAADF 1038 91000 x 20260603.emd',
 '190330 0603 130kx':'01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/emd_files/SI HAADF 1122 130 kx 20260603.emd',
 '170330 0605 91kx':'01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_170330/emd_files/SI HAADF 1537 91000 x 20260605.emd',
 '170330 0512 46kx (7.4GB)':'00_inbox/hyperspy_edx/CA_DA_170330_EDX.emd',
 '170330 0512 EDX_2':'00_inbox/hyperspy_edx/CA_DA_170330_EDX_2.emd',
 'FeO 1610':'00_inbox/hyperspy_edx/SI HAADF 1610.emd',
 'NiCu lamB 1352':'01_projects/LMN_MA_4DSTEM/images/high_pressure_torsion/lamB/emd_files/SI HAADF 1352.emd',
 'AlSi10Mg 1637':'01_projects/LMN_EM_General/for_Temesgen/20242024_AlSi10Mg/SI HAADF 1637.emd',
 'Rh 1456':'01_projects/AGBeine_Katalyse/LR_PL_Rh_SiO_10M_EtOH/emd_files/Rh_SiO_10M_EtOH SI HAADF 33000 x 20260311 1456 0001.emd',
}
def meta(ds,col=0):
    return json.loads(bytes(ds[:,col]).split(b'\x00')[0].decode('utf-8','replace'))
for lab,rel in files.items():
    with h5py.File(root+rel,'r') as f:
        sp=f['Data/Spectrum']; u=list(sp.keys())[0]
        d=sp[u]['Data'][:,0].astype(np.int64); m=meta(sp[u]['Metadata'])
        disp=[v for v in m['Detectors'].values() if v.get('DetectorType')=='AnalyticalDetector']
        D=float(disp[0]['Dispersion'])/1000.; off=float(disp[0].get('OffsetEnergy',0))/1000.
        ch=np.arange(len(d)); E=off+ch*D
        # integer-ish energies: Velox offset-energy
        def win(lo,hi): return int(d[(E>=lo)&(E<hi)].sum())
        tot=int(d.sum())
        ss=f['Data/SpectrumStream']; us=list(ss.keys())[0]
        fr=ss[us]['FrameLocationTable'].shape[0]
        ms=meta(ss[us]['Metadata'])
        sc=ms['Scan']['ScanSize']; ar=ms['Scan'].get('ScanArea',{})
        try: fx=float(ar['right'])-float(ar['left']); fy=float(ar['bottom'])-float(ar['top'])
        except: fx=fy=1
        npx=int(sc['width'])*int(sc['height'])*fx*fy
        print(f"{lab:26s} total counts in summed spectrum {tot:>12,d} ; px {npx:>10,.0f} -> {tot/npx:7.1f} counts/px ; frames {fr} ; disp {D*1000:.0f} eV/ch off {off*1000:.0f} eV ; Mg/Al/Si K windows: Mg {win(1.15,1.35)} Al {win(1.40,1.58)} Si {win(1.65,1.83)} ; 0-0.2keV {win(-5,0.2)}")
