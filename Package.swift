// swift-tools-version: 5.9
//
//  Package.swift
//  Role: REFERENCE ONLY for this Xcode-app project.
//
//  IMPORTANT: Because FourDSTEM is built as an Xcode .xcodeproj *app target*
//  (not a Swift package), you do NOT add MLX through this file. You add it
//  through Xcode's GUI:  File ▸ Add Package Dependencies… ▸ paste the URL
//      https://github.com/ml-explore/mlx-swift
//  and add the `MLX` (and optionally `MLXNN`) library products to the app
//  target. See the setup guide, step 4.
//
//  This manifest is included only so you can see the dependency declaration,
//  and in case you later restructure part of the code as a reusable package.
//

import PackageDescription

let package = Package(
    name: "FourDSTEM",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0")
        // ^ Pin/adjust the version to whatever is current when you build.
        //   Check the repo's "Releases" tab; the API moves fairly fast.
    ],
    targets: [
        .executableTarget(
            name: "FourDSTEM",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift")
            ]
        )
    ]
)
