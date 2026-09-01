# Disk-correlation baseline & parity gate

Pins the numerical result of the Bragg disk-correlation path — the workhorse of
the crystallographic pipeline — and measures its cost on both the serial and the
production parallel path.

```sh
tools/disk-correlation-parity/run.sh                        # verify (serial)
tools/disk-correlation-parity/run.sh --backend cpu-parallel # the shipping path
tools/disk-correlation-parity/run.sh --record               # re-pin the baseline
```

Part of `tools/run-tests.sh scientific`.

## What it guards

1. **Numerical stability of the correlation.** Any change that moves a detected
   peak fails the gate.
2. **The concurrent path agrees with the serial one.** `--backend cpu-parallel`
   mirrors `DiskDetection.detectAll` (one `DiskDetector` per worker, patterns
   strided across workers) and is checked against the *same* baseline. A data
   race or a work-splitting bug in the parallel detector shows up as a checksum
   mismatch.
3. **A measured cost**, so a future optimisation is judged rather than asserted.

## Measured cost (Apple M3, optimised build, 128×128 detector)

| Path | ms/pattern | Projected, 8,400-position scan |
|------|-----------:|-------------------------------:|
| Serial (one thread) | ~1.03 | ~8.7 s |
| **Parallel — what actually ships** | **~0.14–0.22** | **~1.2–1.9 s** |

Timing is deliberately **not** recorded in `baseline.json` — it is machine- and
thermal-dependent. Compare a before/after on the same machine and power mode,
as `tools/performance-baseline` does.

## The 250-px case (FFT speedup session, 2026-09-01)

`run.sh` now runs a second, fixed case: **250×250, 32 patterns, pinned in
`baseline-250.json`.** 250 = 2·5³ is no supported `vDSP_DFT` length and no
exact radix-3/5 plan, so it is the path `calibrationData_circularProbe.h5`
takes — until this session an O(N²) scalar loop with a per-element `sin`/`cos`
(**256 ms per pattern, single thread, `-O`**; the whole story behind the
14-minute Detect All Disks in `docs/s22-ux-design.md` §5.5 P1). It is now an
exact Bluestein (chirp-z) transform in `FFT2D`.

**How the baseline was pinned, so the parity claim is auditable.** The 250
baseline was FIRST recorded on the retired scalar path, then the Bluestein
path was run against it: **peak counts identical (288 / 288, every pattern),
position checksum within 3.9e-7**, but `intensityChecksum` and
`correlationMaximumChecksum` moved by **7.3e-6 and 4.7e-6 relative** — over
the 1e-6 tolerance. That shift is the OLD reference's error, not the new
path's: the scalar loop computed its angle as `Float(j·k)/N`, which reaches
~1560 rad at N = 250 and carries ~1e-4 rad of Float rounding. Measured against
a Double-precision direct DFT (`mac4DSTEMTests/FFT2DArbitraryLengthTests`,
plus a standalone `-O` run):

| Path | relative max error vs Double DFT |
|------|---------------------------------:|
| Retired scalar Float loop, 250-line | 2.1e-5 |
| **Bluestein, 250-line / 250×250** | **7.4e-8 / 8.5e-8** |
| vDSP native radix-2, 128×128 (for scale) | 4.6e-8 |
| Exact radix-5 plan, 125×125 (for scale) | 9.8e-8 |

`baseline-250.json` was therefore **re-pinned on the Bluestein path** — the
one that is closer to the exact DFT — and the scalar-path checksums are kept
here as the record of what moved: `positionChecksum 144000.26418318113`,
`intensityChecksum 22.0708162561059`, `correlationMaximumChecksum
8.754893481731415` (scalar) vs `144000.3197709527`, `22.070654947310686`,
`8.75485235452652` (Bluestein). No py4DSTEM deviation: both are the exact
N-point DFT and the data grid is never padded; the padding is internal to
Bluestein's convolution.

**What this baseline does and does not prove (Gate B, 2026-09-02).** It is a
*correlation* regression pin, not an FFT correctness pin. The refuter applied
20 mutations to `FFT2D`; the parity checksums went red for the chirp-sign,
scale, wrap and conjugation errors, but stayed **bit-identical** for a per-axis
re/im swap (a ky-axis flip of the forward transform), because any bug that
commutes with `FFT⁻¹(P · conj(K))` cancels in cross-correlation. Correctness of
the transform itself rests on `mac4DSTEMTests/FFT2DArbitraryLengthTests`
(which that mutation turns red) and the numpy `fft.fft2` comparison recorded
in `docs/s22-ux-design.md` §6 — not on this file.

**Measured cost at 250×250 (Apple M3, `-O`):**

| Path | ms/pattern | Projected, 8,400-position scan |
|------|-----------:|-------------------------------:|
| Scalar loop, serial (retired) | 255.8 | 2,149 s |
| Bluestein, serial | 3.2 | 27 s |
| **Bluestein, `--backend cpu-parallel`** | **0.68** | **5.7 s** |

## What is pinned

Checksums are chosen to be sensitive rather than merely present:

- `perPatternPeakCounts` — exact; localises *which* pattern first diverges.
- `positionChecksum` — peak coordinates with asymmetric weights, so swapping
  two peaks changes the sum.
- `intensityChecksum`, `correlationMaximumChecksum` — magnitude sensitivity.

Counts must match exactly. Floats use a relative tolerance (default `1e-6`)
because the vDSP FFT is not bit-reproducible across OS revisions.

Verified to have teeth: perturbing `sigmaCC` from 2 to 2.0001 (0.005%) fails the
gate and names the offending checksums. The harness also fails on run-to-run
nondeterminism, since averaging over that would make any parity claim
meaningless.

## Input

Generated from a fixed seed, not read from `References/training_dataset`: the
loop stays seconds long and runs anywhere. Each pattern uses a differently
rotated lattice so an implementation cannot cache its way to a false speedup.
Real-data behaviour is covered separately by `tools/training-dataset-campaign`
and the QC playthrough.

---

## Finding: a Metal disk-correlation backend was built, measured, and removed

**Do not re-attempt this without reading this section.** (2026-08-03, Apple M3.)

A batched Metal correlation backend was written to close ROADMAP **B4** — a real
FFT (iterative Cooley-Tukey in threadgroup memory), chunked to a fixed ~67 MB
working set, with a streaming API. It reproduced the CPU result exactly:
identical per-pattern peak counts, checksums agreeing to ~1e-8.

**It was still slower than the CPU path that ships, so it was deleted.**

| Path | ms/pattern |
|------|-----------:|
| CPU, single thread | 1.037 |
| **CPU parallel (`detectAll`)** | **0.221** |
| Metal | 0.363 |

### The trap

Measured against the *single-threaded* path, Metal looked like a 2.86× win. That
comparison was meaningless: `DiskDetection.detectAll` already runs
`DispatchQueue.concurrentPerform` across every core, which is ~4.7× faster than
one thread on this 8-core M3. Against the real opponent the GPU **lost by 1.6×**.

This is the same trap the ACOM Metal backend fell into — likewise written,
likewise correct, likewise disabled for being slower
(`Core/Crystal/OrientationMatcher.swift:510`). **Always benchmark against
`--backend cpu-parallel`.** That backend exists in this harness for exactly that
reason.

### Why the GPU loses here

- **Unified memory.** On Apple Silicon the CPU and GPU share the same memory at
  the same bandwidth, so the usual discrete-GPU bandwidth advantage is absent.
- **The opponent is 8 cores of hand-tuned vDSP**, not "the CPU".
- **The work per unit is small** — a 128×128 FFT is tiny, so per-dispatch
  overhead is a meaningful fraction of it.

Known headroom in the removed kernel, if anyone revisits it: twiddles were
computed with `cos`/`sin` per butterfly rather than from a precomputed table;
there were four full round trips through device memory with the column passes
strided and therefore uncoalesced; and `waitUntilCompleted` per chunk serialised
CPU and GPU. Fixing all three might plausibly reach ~0.12–0.18 ms/pattern — a
real but uncertain 2–3×, against an opponent that is already fast.

### The bigger reason it was not worth it

Correlation is **not** where the wall-clock goes. Measured pure correlation for a
full scan is ~1.9 s, but disk detection on `sim_Au` took ~29 s end to end in the
QC playthrough. The other ~27 s is elsewhere — file I/O on a 501 MB dataset, tile
staging, and the slower radix-5 FFT a 125×125 detector requires.

**A perfect GPU correlator would have saved under 2 s out of 29.** Anyone
optimising this pipeline should measure that split first. That measurement has
not been done.

### Also note

`sim_Au` is 125×125 (5³). The removed kernel was power-of-two only, so that
dataset would have gained nothing regardless; only the 128×128 datasets
(`downsample_Si_SiGe_exp`, `polycrystal_2D_WS2`) were ever eligible. The CPU
`FFT2D` already handles radix-2, radix-3, radix-5 and a general fallback.
