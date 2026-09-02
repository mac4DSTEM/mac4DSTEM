import XCTest
import DSTEMCore
import DSTEMSession
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

    /// The minimum-spacing default must scale with the *probe*, not the
    /// detector. Measured on the training set (see
    /// `DiskDetectionParams.detectorAdapted` and `tools/bragg-spacing-probe/`):
    /// a 128 px detector yields a 16 px detector-scaled gate, which sits above
    /// the true Bragg spacing on Si_SiGe (14.9 px) and Particle_1 (12.7 px)
    /// and suppresses the g-vectors that define the strain basis.
    func testMinimumSpacingScalesWithProbeRadiusNotDetectorSize() {
        // Same detector, different probes -> different spacing.
        let smallProbe = DiskDetectionParams.detectorAdapted(qy: 128, qx: 128, probeRadius: 5.03)
        let largeProbe = DiskDetectionParams.detectorAdapted(qy: 128, qx: 128, probeRadius: 10.6)
        XCTAssertEqual(smallProbe.minPeakSpacing, 5)
        XCTAssertEqual(largeProbe.minPeakSpacing, 11)

        // Same probe, different detectors -> identical spacing. This is the
        // property the old qMin/8 heuristic violated.
        let wide = DiskDetectionParams.detectorAdapted(qy: 512, qx: 512, probeRadius: 6.1)
        let narrow = DiskDetectionParams.detectorAdapted(qy: 128, qx: 128, probeRadius: 6.1)
        XCTAssertEqual(wide.minPeakSpacing, narrow.minPeakSpacing)

        // A degenerate probe must not produce a zero or negative gate.
        for bad: Float in [0, -1, .nan, .infinity] {
            let params = DiskDetectionParams.detectorAdapted(qy: 128, qx: 128, probeRadius: bad)
            XCTAssertGreaterThanOrEqual(params.minPeakSpacing, 4, "probeRadius \(bad)")
        }
    }

    /// The probe-scaled rule may only ever *loosen* the gate. Only the
    /// loosening direction was measured (every training dataset has
    /// r < qMin/8); a large convergence semi-angle puts the probe radius above
    /// the detector-scaled value, and there an unclamped rule would suppress
    /// more than the value it replaced — a 300 kV / 25 mrad probe reaches
    /// r ≈ 60 px on a 128 px detector, which sits *below* the
    /// `detectorMinimum / 2` validation warning and so would fail silently.
    func testProbeScaledSpacingNeverExceedsTheDetectorScaledValue() {
        for (qy, qx) in [(128, 128), (125, 125), (256, 256), (64, 64)] {
            let detectorScaled = DiskDetectionParams.detectorAdapted(qy: qy, qx: qx)
            for radius: Float in [1, 5, 6.1, 10.6, 20, 40, 60, 200] {
                let params = DiskDetectionParams.detectorAdapted(
                    qy: qy, qx: qx, probeRadius: radius
                )
                XCTAssertLessThanOrEqual(
                    params.minPeakSpacing, detectorScaled.minPeakSpacing,
                    "\(qy)×\(qx) r=\(radius): probe rule must not tighten the gate"
                )
                XCTAssertGreaterThanOrEqual(params.minPeakSpacing, 4)
            }
        }
    }

    /// Omitting the probe radius must reproduce the historical detector-scaled
    /// value exactly. `tools/disk-correlation-parity` is gated against a
    /// recorded 2697-peak baseline and calls this without a probe radius, so a
    /// change here would silently invalidate that baseline.
    func testDetectorScaledFallbackIsUnchangedWithoutAProbeRadius() {
        for (qy, qx) in [(128, 128), (125, 125), (96, 160), (32, 64), (512, 512)] {
            let params = DiskDetectionParams.detectorAdapted(qy: qy, qx: qx)
            let qMin = Float(min(qx, qy))
            XCTAssertEqual(params.minPeakSpacing, max(4, (qMin / 8).rounded()), "\(qy)×\(qx)")
            XCTAssertEqual(params.edgeBoundary, max(2, Int(qMin / 24)), "\(qy)×\(qx)")
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
