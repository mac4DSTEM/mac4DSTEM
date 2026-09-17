# 014 — Learned disk detector: NE-native design, Core ML runtime, 256px, default 0.7, labels in sidecar

Dates: 2026-09-06, 2026-09-07, 2026-09-08

Status: live

## Decision

A plain-conv U-Net on three channels (pattern, probe, the Metal correlation),
trained by this project, own simulator, own weights; the net proposes,
classical refinement measures. It ships on Core ML, not Core AI: measured
speed is a wash (0.305–0.338ms vs 0.344–0.363ms per pattern), Core ML runs on
the macOS 14 floor where Core AI is macOS 27 and beta, and the Core AI branch
recorded a segfaulting stateful asset. Judged on a frozen 40-position,
306-centre hand-labelled set: the 256px net earns its place over the
classical detector (0.667/0.840 vs 0.487/0.485 recall/precision), shipped
default threshold 0.7 (the measured knee), with a Classical/Neural net picker
in Disk detection. `simulate.S` stays 128 by default; every entry point takes
`--size`; `fit_to` centre-crops or zero-pads, never rescales. A sidecar label
is a set of hand-clicked disk centres at one scan position in the detector's
native frame, stored as one JSON attribute on the session sidecar's root
group.

## Why

The ANE is reached only through Core ML, which has no FFT, ruling out
FCU-Net's Fourier layer there; MLX runs on the GPU, not the ANE. The net does
not add disks the classical path misses — it finds the same real disks with
far fewer invented ones. Labels as centres, not confirmed/rejected verdicts,
match the format the C6 verdict was measured against and let a detector be
scored per disk.

## Governs

`mac4DSTEM/Core/ML/LearnedDiskDetector.swift`, `Models/DiskDetector/`
(gitignored except this path), `DiskCentreLabelStore`, the `detector_class` /
`learned_threshold` / `learned_model_sha256` provenance keys.

## Sources

- 2026-09-06 "Learned disk detector is Neural-Engine-native, trained by us", log line 399
- 2026-09-07 "The learned detector ships on Core ML", log line 432
- 2026-09-07 23:45 "C6's size session, the design as briefed", log line 550
- 2026-09-08 "C6 verdict: ... 256-px model; ... default threshold 0.7", log line 561
- 2026-09-08 "Labels in the sidecar: centres, as one attribute", log line 663

Evidence: `docs/archive/v3/learned-detector-2026-09-06.md`, `tools/disk-detector/README.md` (verified present).
