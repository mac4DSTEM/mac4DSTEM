// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
// mac4dstem-mcp: the MCP bridge to mac4DSTEM's agent door. A package of its own, apart from the app's: it is not part of the
// app, is not in the App Store build, and needs nothing but Foundation. `swift build -c release` makes the one binary.
import PackageDescription

let package = Package(
    name: "mac4dstem-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mac4dstem-mcp", targets: ["mac4dstem-mcp"]),
    ],
    targets: [
        // Everything but `main`: the door's client and the MCP server, so the tests read them without a process or a port.
        .target(name: "AgentBridgeCore", path: "Sources/AgentBridgeCore"),
        .executableTarget(name: "mac4dstem-mcp", dependencies: ["AgentBridgeCore"], path: "Sources/mac4dstem-mcp"),
        .testTarget(name: "AgentBridgeTests", dependencies: ["AgentBridgeCore"], path: "Tests/AgentBridgeTests"),
    ],
    swiftLanguageModes: [.v5]
)
