import XCTest
@testable import mac4DSTEM

final class DiskDetectionContractTests: XCTestCase {
    func testDetectorAdaptedConfigurationValidatesAcrossDetectorShapes() {
        for (qy, qx) in [(128, 128), (125, 125), (96, 160), (32, 64)] {
            let parameters = DiskDetectionParams.detectorAdapted(qy: qy, qx: qx)
            let context = DiskDetectionContext(qy: qy, qx: qx, probeRadius: 3)
            let errors = parameters.validationIssues(in: context).filter {
                $0.severity == .error
            }
            XCTAssertTrue(errors.isEmpty, "\(qy)×\(qx): \(errors)")
            XCTAssertLessThanOrEqual(parameters.edgeBoundary, context.maximumEdgeBoundary)
        }
    }

    func testInvalidConfigurationNamesEveryBrokenScientificField() {
        var parameters = DiskDetectionParams()
        parameters.corrPower = 2
        parameters.sigmaDP = -.infinity
        parameters.sigmaCC = -.nan
        parameters.subpixel = .multicorr
        parameters.upsampleFactor = 2
        parameters.minRelativeIntensity = 1.5
        parameters.relativeToPeak = 10
        parameters.maxNumPeaks = 4
        parameters.edgeBoundary = 64
        let fields = Set(parameters.validationIssues(
            in: DiskDetectionContext(qy: 128, qx: 128, probeRadius: 2)
        ).filter { $0.severity == .error }.map(\.field))
        XCTAssertTrue(fields.contains(.correlationPower))
        XCTAssertTrue(fields.contains(.patternSigma))
        XCTAssertTrue(fields.contains(.correlationSigma))
        XCTAssertTrue(fields.contains(.upsampleFactor))
        XCTAssertTrue(fields.contains(.minimumRelativeIntensity))
        XCTAssertTrue(fields.contains(.relativeReferencePeak))
        XCTAssertTrue(fields.contains(.edgeBoundary))
    }

    func testParameterCatalogAndScanSummaryAreDeterministic() {
        XCTAssertEqual(
            Set(DiskDetectionParameterID.allCases.map(\.rawValue)).count,
            DiskDetectionParameterID.allCases.count
        )
        XCTAssertTrue(DiskDetectionParameterID.allCases.allSatisfy {
            !$0.title.isEmpty && !$0.explanation.isEmpty
        })

        let vectors = BraggVectors(
            scanWidth: 3, scanHeight: 2,
            peaks: [
                [],
                [BraggPeak(x: 1, y: 1, intensity: 1)],
                [BraggPeak(x: 1, y: 1, intensity: 1)],
                [BraggPeak(x: 1, y: 1, intensity: 1), BraggPeak(x: 2, y: 2, intensity: 0.5)],
                [],
                Array(repeating: BraggPeak(x: 3, y: 3, intensity: 0.25), count: 4),
            ]
        )
        let summary = DiskDetectionScanSummary(vectors: vectors, maximumPeaks: 4)
        XCTAssertEqual(summary.positionCount, 6)
        XCTAssertEqual(summary.totalPeakCount, 8)
        XCTAssertEqual(summary.minimumPeakCount, 0)
        XCTAssertEqual(summary.medianPeakCount, 1)
        XCTAssertEqual(summary.maximumPeakCount, 4)
        XCTAssertEqual(summary.atMaximumPositionCount, 1)
        XCTAssertFalse(summary.warnings.isEmpty)
    }
}
