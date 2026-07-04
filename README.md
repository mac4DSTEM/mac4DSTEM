# mac4DSTEM

mac4DSTEM is a macOS SwiftUI application project for 4D-STEM workflows.

## Project Structure

The app is organized around a SwiftUI shell with domain code migrated in small, buildable slices:

```text
mac4DSTEM/
  mac4DSTEM/
    App/
      mac4DSTEMApp.swift
      AppState.swift
    Core/
      Analysis/
      Data/
    UI/
      ContentView.swift
      DatasetInspector.swift
      ApertureControl.swift
      Colormaps.swift
    Shaders/
    Support/
```

## Current State

Migrated so far:

- App entry and shared state using `mac4DSTEM` naming
- Core data/value types for datasets, diffraction patterns, calibration, and orientation results
- Colormap definitions
- Lightweight UI shell with sidebar, inspector toggle, dataset inspector, and aperture control

Still deferred:

- HDF5 reader and file import implementation
- Metal display and compute pipeline
- FFT, virtual detector, DPC, disk detection, and calibration workflows
- Full migrated sidebar and image views
- Shaders and bridging/header support

## Requirements

- macOS with Xcode installed
- SwiftUI support through the active Xcode toolchain

## Getting Started

1. Open the project in Xcode.
2. Select the `mac4DSTEM` scheme.
3. Build and run the app.

## Migration Notes

Use `MigrationSource/` as read-only reference material. Bring code over in small batches and build after each batch.

Recommended order from here:

1. FFT and pure compute helpers
2. Metal engine and shader resources
3. HDF5 reader and file import wiring
4. Virtual detector and calibration flows
5. DPC and disk detection
6. Full UI views that depend on those services

Avoid copying old project scaffolding such as `.xcodeproj`, `Package.swift`, `Package.resolved`, generated build folders, or DerivedData into this project unless you intentionally want to replace the project configuration.

## Development Notes

- Keep one `@main` app type in `App/mac4DSTEMApp.swift`.
- Keep root UI in `UI/ContentView.swift`.
- Views should describe UI; move data loading, parsing, processing, and persistence into `Core` or dedicated services.
- Keep project documentation updated as features are added.
