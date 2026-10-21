# Status

Updated 2026-10-21. What is live; history is in git and `CHANGELOG.md`, the earlier hand-offs are archived in the suite's private folder (`status-2026-10-21`).

## Version

Latest release v4.5.0 (2026-10-05, macOS 27+; v3.0.0 stays for older systems). `main` is v5.0 development: the kit switches since v4.5.0 are listed under "Unreleased" in `CHANGELOG.md`.

## Kits (exact tags in `Package.swift`, the truth)

SpectroKit 0.7.1, FormatoKit 0.8.0, DiffractoKit 0.8.1, CuboKit 0.7.1, ImagoKit 0.5.0. Science with a kit equivalent is the kit's; the app keeps its Float façades.
Stays in the app on purpose: the learned disk detector (training and refine), lineage and marks, the rank-3 reshape, header-less MIB, selected-area Metal diffraction and the resident cube (until CuboKit has a weighted-pattern Metal kernel; `open-items.md`, Kit asks).

## Rooms

Prepare, Imaging, Bragg Disks, Crystal Maps, Reconstruction, Results, Spectroscopy (EDX: fit, Auto ID, quantification, pooling).

## Badged unvalidated

Phase mapping, and any product that self-reports `validation:"none"`. `inventory` greps the badge and the key.

## Not yet verified

The final kit switch and the PCA projection ran the unit suite and the scientific harnesses; `sidecar-parity`, `real-data-acceptance` and an on-screen drive have not run on them (the nightly review runs the first two). Notarisation of the Developer ID archive is open (`open-items.md`, App work 1).

## Next

The owner pushes the kits and tags CuboKit 0.7.1, then the app; re-pin on the kit asks in `open-items.md`; kit audit sessions; a drive.
