import XCTest
@testable import mac4DSTEM

final class DemoWorkflowTests: XCTestCase {
    func testDemoFixturePublishesAUsableOrientationPreview() async throws {
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let radius: Float = 4.5
        let kernel = try XCTUnwrap(ProbeKernel.synthetic(
            radius: radius, qy: descriptor.qy, qx: descriptor.qx
        ))
        var parameters = DiskDetectionParams()
        let qMin = Float(min(descriptor.qx, descriptor.qy))
        parameters.minPeakSpacing = max(4, (qMin / 8).rounded())
        parameters.edgeBoundary = max(2, Int(qMin / 24))
        let detected = await DiskDetection.detectAll(
            data: data, descriptor: descriptor, kernel: kernel, params: parameters
        )
        let vectors = try XCTUnwrap(detected)
        XCTAssertGreaterThan(
            vectors.totalPeakCount, descriptor.rx * descriptor.ry * 3,
            "Demo detected only \(vectors.totalPeakCount) peaks"
        )

        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: .gold, kMax: 1.2, zoneAxisCount: 96
        ))
        let map = try XCTUnwrap(OrientationMatching.matchAll(
            bragg: vectors, plan: plan,
            originX: 32, originY: 32, invAngstromPerPixel: 0.02,
            backend: .cpu, selection: .preview(maxDimension: 12)
        ))
        let valid = map.results.filter { $0.templateIndex >= 0 }
        XCTAssertGreaterThan(valid.count, map.results.count * 9 / 10)
        let maximumScore = valid.map(\.score).max() ?? 0
        let firstRadii = vectors.peaks.first?.map {
            hypot($0.x - 32, $0.y - 32)
        } ?? []
        XCTAssertGreaterThan(
            maximumScore, 0.001,
            "score \(maximumScore); total peaks \(vectors.totalPeakCount); first radii \(firstRadii)"
        )
    }
}
