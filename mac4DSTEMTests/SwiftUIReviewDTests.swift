//
//  SwiftUIReviewDTests.swift
//  Lane D of the 2026-10-07 SwiftUI review: the spectrum strip's keyboard / VoiceOver view actions and its drawing cost.
//  Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class SwiftUIReviewDTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    private func zoomed() -> SpectrumViewport {
        var vp = SpectrumViewport(domain: 0...10, minimumSpan: 0.02)
        vp.lo = 2; vp.hi = 6
        return vp
    }

    // MARK: D2 - drawing cost

}
