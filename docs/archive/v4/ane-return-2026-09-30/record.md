# The learned detector back on the Neural Engine — Gate D record, 2026-09-30 night (M5 Pro, macOS 27.0.1)

Follows `../newmac-gateD-2026-09-30/record.md` §2 (on this Mac Core ML's `.all` runs the detector on the GPU; owner: back on
the Neural Engine). Every prediction below was written before its run. Session logs are not retained; what a reader
reproduces is the probe beside this file, the unit test and `tools/disk-detector/scan-bench/`.

**Change (as landed, after Gate B).** `LearnedDiskDetector.load` loads on `.cpuAndNeuralEngine` (was `.all`), sends the
package's default batch as before, and **runs one fixed batch at load: if the result equals a `.cpuOnly` load bit for bit
the Neural Engine did not run and the load throws** (`neuralEngineDidNotRun`). Another unit or batch is reachable only
through `loadForComparison` (tools and tests). What holds the app to the Neural Engine is a test on the detector
`LearnedDetectionSession.prepare` hands back (zero values may differ from a direct Neural Engine run); the inventory grep
for app callers of `loadForComparison` is a tripwire, not a barrier (a wrapper inside the detector file passes it). Why `.all` picks the GPU
here, and why only the default batch is served, is **not known** and not claimed.

## E1 — the units and the batches (`batch-and-unit-probe.swift <mlpackage>`, `xcrun swiftc -O -parse-as-library`)

Predicted: plan 39/39 on the Neural Engine under `.cpuAndNeuralEngine`; batch 32 differs from `.cpuOnly`, other batches equal
it bit for bit; a zero-padded batch of 32 keeps the Neural Engine; repeat and fresh load identical. **All held.**

| Compute units | `MLComputePlan` preferred device (39 ops carry one, 130 none) |
|---|---|
| `.all` | GPU 39 |
| `.cpuAndNeuralEngine` | Neural Engine 39 |
| `.cpuAndGPU` / `.cpuOnly` | GPU 39 / CPU 39 |

| Batch (real patterns) under `.cpuAndNeuralEngine` | vs `.cpuOnly` | ms: NE / CPU / `.all` |
|---|---|---|
| 32 (32), 32 (16), 32 (1) | differs at 98.8 % of pixels | 13–15 / 74–93 / 20–48 |
| 1, 16, 31, 33, 64 | **bit-identical** | as the CPU |

The plan names the Neural Engine at every batch, so the plan alone cannot see the fallback. `.all` never equals either.
**Gate B corrected the reading of this table:** on package variants (spec-edited copies) the Neural Engine ran each
package's *declared default* batch and no other tried — default 16: 16 runs, 32 and 48 fall to the CPU; 33…64 default 48:
48 runs; enumerated {16, 32} and an unbounded range: both run. "32" is the shipped package's default, not the engine's number.

## E3 — the unit tests, their mutations, and Gate B

First version (a fixed `neuralEngineBatch = 32` guard; the test asserted the plan and "differs from the CPU"): four
predicted mutations red. **The independent refuter then broke it** (its logs are not retained; its mutations are repeatable):
- "differs from the CPU" is true of the GPU too (94–97 % of values against 98.8 %), and the plan was the test's own, so
  a load that quietly used `.all` stayed green on both (red only on the 8-extras bar); the app session or the fine-tuning
  candidate loading on `.all`, and `.all` only on the stored-model path, all **survived** with every test green.
- the batch guard accepted a default-16 package, sent it 32, and got the CPU's numbers; an unbounded range overflowed.
- `loadDetector()` turned a refusal into a skip.

As landed — the six learned classes 45 passed / 0 failed / 0 skipped; mutations over nine classes (83 tests), each
predicted, each red, file restored `cmp`-identical:

| Mutation | Red on |
|---|---|
| `load` passes `.all` | units; "plans 0 of 39"; 2 085 434 values differ from a direct Neural Engine run; 8 extras (2.26 %) |
| Neural Engine silently mapped to `.all` inside the loader (refuter's R2) | differs from a direct Neural Engine run (parity and stored-model tests); the refusal test |
| `.all` only when a compiled copy is given (R3) | the stored-model test: differs from a direct Neural Engine run |
| default batch 16 | 18 tests **fail** (not skip): "the Neural Engine did not run this model (batch 16)" |
| load-time check disabled | `testLoadRefusesAModelTheNeuralEngineDidNotRun` |
| app session calls `loadForComparison(.all)` (R1) | `run-tests.sh inventory` exit 1 |

**Second refuter pass, on the landed design:** no false refusal on eight changed-weights packages (noise, negated or zeroed
head, NaN, × 1000), each bit-identical to a direct Neural Engine run at 14.3–14.7 ms per batch (CPU 78 ms). Survivors, and
what was done: a wrapper in the detector file with the session loading on `.all` passed tests and inventory → the
`prepare` test above (red on it: 2 085 434 values differ); the check skipped on the compiled-copy path → the refusal test
now covers that path; "never refuses at the default batch" survives and cannot be shown here (no package whose default
batch falls to the CPU was found). Simulating no Neural Engine, four tests failed instead of skipping → guarded.
Not pinned: the fine-tuning candidate's unit (it uses `load`; a wrapper could move it), a partial Neural Engine plan
(the 39-of-39 assertion covers the bundled model only), and a re-route by Core ML after the load.
**Cost of the check** (M5 Pro): a load takes 0.29–0.31 s on the compile path (0.07 s without) and 0.13 s from a compiled
copy (0.007 s); a machine that refuses repeats it on every live preview, since only a success is cached.

## E2 — whole scans, per compute unit (`scan-bench … --units ane|all|gpu|cpu --peaks`, `compare_peaks.py`, 0.05 px)

Datasets: the 2026-09-08 bullseye dump (525 patterns, 250 px, one window); Thronsen A stride-3 cube at dump stride 3 (3 249
patterns, 128 px); `Si-SiGe_calibrated.h5` at stride 2 (351 patterns, 448 × 480, several windows per pattern). The last two
use `dump.py`'s data-built bench probe, not the app's. Run twice (an agent's, then on a quiet machine): peak counts equal,
the Neural Engine's peak files byte-identical across the two runs and across repeats.

Accepted peaks, threshold 0.7 (shipped) / 0.9, and end-to-end seconds at 0.7 (quiet run):

| Dataset (classical peaks) | Neural Engine | `.all` (GPU here) | `.cpuAndGPU` | `.cpuOnly` |
|---|---|---|---|---|
| bullseye (2 017) | 4 547 / 3 090 · 0.30 s | 4 564 / 3 135 · 0.40 s | 4 563 / 3 136 · 0.46 s | 4 562 / 3 128 · 1.37 s |
| Thronsen A (30 662) | 74 400 / 55 885 · 1.79 s | 74 365 / 56 007 · 2.40 s | 74 366 / 56 015 · 2.78 s | 74 392 / 55 985 · 8.54 s |
| Si-SiGe (3 402) | 11 571 / 3 718 · 0.70 s | 11 622 / 3 902 · 0.95 s | 11 621 / 3 905 · 1.13 s | 11 623 / 3 859 · 3.68 s |

- **Against the pinned reference** (previous Mac's Neural Engine, 2026-09-08, same asset `0f53d270`: 4 544 / 3 086, classical
  2 017): 4 547 / 3 090, +0.07 % / +0.13 %; classical exact. Predicted "within 0.5 %, not exact": **held**.
- **Between units** — predicted "within 2 % in count, ≥ 98 % of the Neural Engine's peaks matched": the count **held at
  0.7** (≤ 0.45 %) and was **refuted at 0.9** on Si-SiGe (`.all` +4.9 %) and close on bullseye (+1.5 %); the matching held
  (≥ 99.9 %). A matched peak sits at the same position (worst 0.015 px, and widening the tolerance to 4 px pairs nothing
  more). At 0.9, the peaks only `.all` accepts are in the Neural Engine's own 0.7 list in 45 of 45 (bullseye), 184 of 185
  (Si-SiGe) and 148 of 148 (Thronsen) cases; at 0.7 that was not measured. On these three dumps only.
- **What the change moves on this Mac, at the shipped threshold**: against a run on the GPU under `.all`, the peaks that
  change (in one list and not the other) are 25 of 4 547 (bullseye), 93 of 74 400 (Thronsen) and 71 of 11 571 (Si-SiGe);
  net −17, +35, −51. The last two use the bench probe, so they are not what the app's own Detect All on those files
  moves. Other Macs: **not measured** — none is left to run it.
- **Throughput**: the Neural Engine is 25–27 % faster end to end than `.all` on all three (predicted "not slower": held).
  The ratio to the classical scan (2.4 × bullseye, 2.5 × Si-SiGe, 15.6 × Thronsen) is a property of this machine and these
  cubes, not a bar.
- `compare_peaks.py` was given a doctored input once (one peak shifted 0.2 px, one deleted, at 0.7): it reported exactly
  those. The refuter's own optimal matcher gives the same counts as its greedy one.

## Not verified

Any Mac but this one. A macOS update can change either finding: the load-time check then refuses (the detector says
"the Neural Engine did not run this model") rather than compute elsewhere, and the refusal test goes red if another batch
starts being served. On a machine with no Neural Engine (a virtual machine; every Apple-silicon Mac has one) the learned
detector is now refused where it used to run on other numerics unannounced, and its tests skip. The app was
not driven: nothing it draws changed; the refusal reaches the existing "could not be prepared" line.
