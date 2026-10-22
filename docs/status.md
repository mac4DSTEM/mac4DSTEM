# Status

Updated 2026-10-22. What is live; history is in git and `CHANGELOG.md`, the earlier hand-offs are archived in the suite's private folder (`status-2026-10-21`).

## Version

Latest release v4.5.0 (2026-10-05, macOS 27+; v3.0.0 stays for older systems). `main` is v5.0 development: the kit switches since v4.5.0 are listed under "Unreleased" in `CHANGELOG.md`.

## Kits (exact tags in `Package.swift`, the truth)

SpectroKit 0.10.0, FormatoKit 0.11.0, DiffractoKit 0.10.0, CuboKit 0.9.0, ImagoKit 0.8.0; the window shell, controls and the spectroscopy rooms' shared pieces are MacEMUI 0.2.0 (an app package, `../macEM-suite/docs/macemui.md`). Science with a kit equivalent is the kit's; the app keeps its Float façades.
Stays in the app on purpose: the learned disk detector (training and refine), lineage and marks, the rank-3 reshape, header-less MIB, selected-area Metal diffraction and the resident cube (until CuboKit has a weighted-pattern Metal kernel; `open-items.md`, Kit asks).

## Rooms

Prepare, Imaging, Bragg Disks, Crystal Maps, Reconstruction, Results, Spectroscopy (EDX: fit, Auto ID, quantification, pooling; several regions with a list, a line tool with a Profile tab, a Table tab with the fitted composition per region and the map means; tile size and solo tiles). Precipitates: objects, N_V, composition and strain per object, and the variant map (task 40: variants per needle direction, legend, colours, table and CSV columns).

## Badged unvalidated

Phase mapping, and any product that self-reports `validation:"none"`. `inventory` greps the badge and the key.

## Not yet verified

The Spectroscopy room's journey runs green (tiles, regions, profile, table); the variant map, the hover chip, the solo tile and line dragging are not driven (`open-items.md`, App work). `sidecar-parity` and `real-data-acceptance` have not run on the latest kit pins (the nightly review runs them). Notarisation of the Developer ID archive is open (`open-items.md`, App work 1).

## Next

MacEMUI 0.2.1 (the drawing layer's drag geometry, contrast and gamma in the map colour controls), then adopt both in the room; a Precipitates journey for the variant map; the Thronsen figure comparison; a drive.
