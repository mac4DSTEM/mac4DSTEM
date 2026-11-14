//
//  UITestRunnerSigningTests.swift
//  The UI test runner (`com.mac4dstem.mac4DSTEMUITests.xctrunner`) keeps one signature in every kind of run (#200). Signed ad
//  hoc by `tools/run-tests.sh ui` and with the development identity by a drive run, the same identifier carried two signers, and
//  macOS stopped the journeys with "mac4DSTEMUITests-Runner differs from previously opened versions" until someone answered.
//  The target therefore names its signing: the team and the Apple Development identity, manual, no profile.
//

import XCTest

final class UITestRunnerSigningTests: XCTestCase {
    /// Mutation: one configuration back to `CODE_SIGN_STYLE = Automatic` without a team, or the identity dropped - red.
    func testTheUITestRunnerHasAFixedDevelopmentSigningInEveryConfiguration() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mac4DSTEM.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: project, encoding: .utf8)
        var blocks: [String: [String]] = [:]
        var current: String?
        for line in text.split(separator: "\n").map(String.init) {
            if line.contains("configuration for PBXNativeTarget \"mac4DSTEMUITests\""), line.hasSuffix("= {") { current = line; blocks[line] = [] }
            else if current != nil, line.hasPrefix("\t\t};") { current = nil }
            else if let c = current { blocks[c, default: []].append(line.trimmingCharacters(in: .whitespaces)) }
        }
        XCTAssertEqual(blocks.count, 3, "Debug, Develop and Release of the UI test target")
        for (name, settings) in blocks {
            for wanted in ["CODE_SIGN_STYLE = Manual;", "CODE_SIGN_IDENTITY = \"Apple Development\";", "DEVELOPMENT_TEAM = 3B8SMSSAX4;"] {
                XCTAssertTrue(settings.contains(wanted), "\(wanted) missing in \(name.trimmingCharacters(in: .whitespaces))")
            }
        }
    }
}
