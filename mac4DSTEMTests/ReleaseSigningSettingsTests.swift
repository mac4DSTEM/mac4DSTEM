//
//  ReleaseSigningSettingsTests.swift
//  Notarization refuses an executable without the hardened runtime. v5.0.0's first notarization came back Invalid (2026-10-23,
//  submission 4a414148): the two Quick Look extensions added on 2026-10-22 had ENABLE_HARDENED_RUNTIME = NO in Release. Every
//  target's Release configuration must enable it.
//

import XCTest

final class ReleaseSigningSettingsTests: XCTestCase {
    /// Mutation: one Release block back to NO (or the key dropped from a new target's Release block) - red.
    func testEveryReleaseConfigurationEnablesTheHardenedRuntime() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mac4DSTEM.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: project, encoding: .utf8)
        var current = "", checked = 0
        for line in text.split(separator: "\n") {
            if line.contains("configuration for PBXNativeTarget"), line.hasSuffix("= {") { current = String(line) }
            guard current.contains("/* Release configuration"), line.contains("ENABLE_HARDENED_RUNTIME") else { continue }
            checked += 1
            XCTAssertTrue(line.contains("= YES;"), "hardened runtime off in \(current.trimmingCharacters(in: .whitespaces))")
        }
        XCTAssertGreaterThanOrEqual(checked, 3, "the app and both Quick Look extensions state the setting in Release")
    }
}
