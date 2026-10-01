import numpy as np
print("numpy", np.__version__)
rng = np.random.default_rng(1)
N = 108900
# binned counts: a bright centre ~ 2e5 (bin 4 of 60-count pixels x16... use several scales), Poisson-ish noise
for scale in (10.0, 1e3, 1e4, 2e5):
    data = (scale + rng.normal(0, np.sqrt(scale), size=(N, 1, 1))).astype(np.float32)
    data = np.broadcast_to(data, (N,1,1))  # one pixel, N patterns
    cube = np.ascontiguousarray(np.repeat(np.repeat(data, 2, axis=1), 2, axis=2))  # (N,2,2) float32
    m32 = np.mean(cube, axis=(0, 1))  # as py4DSTEM: axis=(0,1) on a (R0,R1,Q..) array; here (N,2)->mean over N and first Q axis
    m64 = np.mean(cube.astype(np.float64), axis=(0, 1))
    print(f"scale {scale:g}: max |mean32-mean64| = {np.max(np.abs(m32 - m64)):.4g} (relative {np.max(np.abs(m32-m64))/scale:.2e})")
# 4D shaped exactly like py4DSTEM: (Rx,Ry,Qx,Qy) = (300,363,4,4), mean axis=(0,1)
cube = (2e5 + rng.normal(0, 450, size=(300, 363, 4, 4))).astype(np.float32)
m32 = np.mean(cube, axis=(0,1)); m64 = cube.astype(np.float64).mean(axis=(0,1))
print(f"4D (300,363,4,4) at 2e5: max |mean32-mean64| = {np.max(np.abs(m32-m64)):.4g}")
cube = (1e3 + rng.normal(0, 30, size=(300, 363, 4, 4))).astype(np.float32)
m32 = np.mean(cube, axis=(0,1)); m64 = cube.astype(np.float64).mean(axis=(0,1))
print(f"4D (300,363,4,4) at 1e3: max |mean32-mean64| = {np.max(np.abs(m32-m64)):.4g}")
