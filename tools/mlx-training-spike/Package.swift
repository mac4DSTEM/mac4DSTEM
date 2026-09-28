// swift-tools-version:6.0
// tools/mlx-training-spike — ROADMAP C2 (2026-09-28): can an MLX-Swift mirror of the shipped
// disk-detector graph be fine-tuned on this Mac and written back into the shipped Core ML spec so
// the convs still run on the Neural Engine? A diagnostic, never a gate. MLX stays out of DSTEMCore
// (SwiftPM from the command line cannot build MLX's Metal shaders): build with `run.sh`, which
// uses xcodebuild.
import PackageDescription

let package = Package(
    name: "mlx-training-spike",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.6"),
    ],
    targets: [
        .executableTarget(
            name: "mlx-spike",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
            ],
            path: "Sources"
        ),
    ]
)
