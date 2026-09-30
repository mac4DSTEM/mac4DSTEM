# Review row 9 — odd-length DFT upsample wrap: reproducible check (supervisor, 2026-09-30 night, read-only)
Swift (Core/Compute/MatrixDFTCorrelation.swift:149-152, :174-177): wrapped = k < N/2 ? k : k − N (integer N/2).
numpy (the review's reference, = np.fft.fftfreq(N)·N): ifftshift(arange(N)) − floor(N/2).
Run (py4dstem env python, numpy): N=4 → equal; N=5 → Swift [0,1,−3,−2,−1] vs numpy [0,1,2,−2,−1]; N=7 → Swift [0,1,2,−4,−3,−2,−1] vs
numpy [0,1,2,3,−3,−2,−1]; N=8 → equal. So every ODD axis maps its middle bin to the wrong alias. Inside the upsampled DFT the aliases
are not equivalent: exp(−2πi(2−(−3))x/(N·u)) at N=5, u=16 reads 0.995−0.098i at x=0.25 … 0.924−0.383i at x=1 (a phase ramp, not 1).
Verdict: REPRODUCES. Reached from DiskDetection.swift:1229 (multicorrRefine) on any odd detector axis (an odd crop reaches it); a
Gate D with an odd-axis fixture in the multicorr parity harness before the one-token fix (`< (N + 1) / 2`).
py4DSTEM's own upsampler (References/py4DSTEM-dev/py4DSTEM/process/utils/multicorr.py:186, :195) uses exactly ifftshift(arange(N)) − floor(N/2) on both axes.
