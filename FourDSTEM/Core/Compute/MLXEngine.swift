//
//  MLXEngine.swift
//  Role: The seam where machine-learning features will plug in later. For now
//        it just initializes the MLX default device, logs what hardware MLX
//        sees, and offers a passthrough `runInference`. No models yet.
//
//  WHY A STUB: the master spec wants the project wired for MLX from day one so
//  that adding a real `Module` subclass later is a drop-in, not a refactor.
//  Everything ML-related funnels through this one type.
//
//  DEPENDENCY: MLX is added via Xcode ▸ File ▸ Add Package Dependencies
//  (https://github.com/ml-explore/mlx-swift). Until you add it, keep the
//  `import MLX` lines below commented — the file still compiles and the app
//  still runs, it just reports "MLX not linked".
//

import Foundation

// Once mlx-swift is added as a package, uncomment these:
// import MLX
// import MLXNN

// MARK: - MLXEngine

/// Single entry point for all (future) on-device ML.
///
/// NOTE: marked `@unchecked Sendable` only so it can be a global `shared`
/// singleton touched from background tasks. The passthrough stub holds no
/// mutable state; when real models arrive, guard their state with an actor or
/// a lock and revisit this.
final class MLXEngine: @unchecked Sendable {

    static let shared = MLXEngine()

    /// True once a real MLX backend is linked and initialized.
    private(set) var isAvailable = false

    private init() {
        configure()
    }

    // MARK: Setup

    private func configure() {
        #if canImport(MLX)
        // When MLX is linked, this block compiles and runs.
        // MLX.Device.setDefault(device: .gpu)          // prefer the Apple GPU
        // let d = MLX.Device.defaultDevice()
        // print("[MLXEngine] MLX device: \(d)")
        isAvailable = true
        #else
        isAvailable = false
        print("[MLXEngine] MLX not linked — ML features disabled. "
              + "Add ml-explore/mlx-swift via Xcode to enable.")
        #endif
    }

    // MARK: Inference (passthrough stub)

    /// FUTURE: run a real model. For now this returns the input unchanged so
    /// callers can be written and tested against the final signature today.
    ///
    /// - Parameters:
    ///   - pattern: flattened input values (e.g. a normalized CBED pattern).
    ///   - shape: logical shape of `pattern`, e.g. [Qy, Qx].
    /// - Returns: same values, unchanged.
    func runInference(pattern: [Float], shape: [Int]) -> [Float] {
        // FUTURE: build an MLXArray from `pattern`/`shape`, run a Module,
        // and return the evaluated result as [Float].
        return pattern
    }
}
