//
//  VirtualDetectorEmptySelectionTests.swift
//  A virtual detector that covers no detector pixel is refused, not computed as an all-zero image that reads as a real,
//  dark one (#302).
//

import XCTest
import DSTEMCore

final class VirtualDetectorEmptySelectionTests: XCTestCase {
    private func run(_ shape: DetectorShape) async throws -> FloatImage {
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        return try await VirtualDetector.tiledImage(data: FourDArray(reader: source, descriptor: descriptor),
                                                    descriptor: descriptor, shape: shape)
    }

    /// Mutation: the old all-zero image for a nil geometry - no error, red.
    func testARectangleOffTheDetectorIsRefused() async {
        do {
            _ = try await run(.rectangle(xMin: 10_000, xMax: 10_010, yMin: 10_000, yMax: 10_010))
            XCTFail("a detector off the pattern must be refused")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("covers no detector pixel"), "\(error)")
        }
    }

    func testAPointOffTheDetectorIsRefused() async {
        do {
            _ = try await run(.point(x: -1, y: 0))
            XCTFail("a point off the pattern must be refused")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("covers no detector pixel"), "\(error)")
        }
    }

    /// A detector on the pattern still gives its image.
    func testACircleOnThePatternStillComputes() async throws {
        let image = try await run(.circle(centerX: 8, centerY: 8, radius: 4))
        XCTAssertTrue(image.pixels.contains { $0 != 0 })
    }
}
