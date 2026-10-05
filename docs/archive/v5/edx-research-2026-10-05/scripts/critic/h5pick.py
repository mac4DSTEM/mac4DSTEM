# Emulates mac4DSTEM H5Reader.discoverPrimaryDataset ordering (H5Reader.swift:267-370) on structure only.
import h5py, sys
canon = ["/dm_dataset_root/dm_dataset/data","/4DSTEM_experiment/data/datacubes/datacube_0/data","/4DSTEM/data/datacubes/datacube_root/data","/datacube_root/datacube/data","/Experiments/__unnamed__/data","/Experiments/__unnamed__/data/data"]
for p in sys.argv[1:]:
    with h5py.File(p, 'r') as f:
        paths = []
        f.visit(lambda n: paths.append('/' + n))
        def key(s): return (0 if s.endswith('/data') else 1, s.count('/'), s)
        hit = [c for c in canon if c in f and isinstance(f[c], h5py.Dataset) and f[c].ndim in (3,4)]
        chosen = None; promoted = None
        if hit: chosen = hit[0]
        else:
            for s in sorted(paths, key=key):
                o = f[s]
                if isinstance(o, h5py.Dataset) and o.ndim in (3, 4):
                    if o.ndim == 4: chosen = s; break
                    if promoted is None: promoted = s
            chosen = chosen or promoted
        if chosen:
            sh = f[chosen].shape; sh4 = sh if len(sh) == 4 else (1,) + sh
            print(p.split('/')[-1], '->', chosen.replace(chosen.split('/')[3] if chosen.count('/')>3 else '', '<uuid>'), f[chosen].dtype, 'stored', sh, '=> opened as [ry,rx,qy,qx] =', sh4)
        else:
            print(p.split('/')[-1], '-> no rank-3/4 dataset (named refusal)')
