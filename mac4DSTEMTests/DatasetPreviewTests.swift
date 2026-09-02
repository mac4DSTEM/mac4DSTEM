import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Pins stage L5's preview and **invariant I4**: a sampled preview is not a
/// result. It is visibly marked as sampled, states its stride, and cannot be
/// mistaken for or promoted to a product.
///
/// The defect these are written against is not a crash. It is a preview that
/// looks enough like a virtual image to be believed — the L5 prompt names it
/// directly: *"a strided preview and a real virtual image will differ, and a
/// user comparing them will file a bug."* Every assertion here is about the
/// preview admitting what it is.
@MainActor
final class DatasetPreviewTests: XCTestCase {

    private func demo() async throws -> (FourDArray, DatasetDescriptor) {
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        return (FourDArray(reader: source, descriptor: descriptor), descriptor)
    }

    // MARK: The stride is derived from a byte budget, not a fixed grid

    /// A fixed sample count costs 1 MB on a 64² detector and 256 MB on a 512²
    /// one — the second is a load, not a preview. Budgeting bytes keeps the wait
    /// roughly constant, which is the property the user experiences.
    func testStrideKeepsThePreviewInsideItsByteBudget() {
        for (qy, qx) in [(64, 64), (128, 128), (256, 256), (512, 512)] {
            let descriptor = DatasetDescriptor(
                filePath: "/tmp/x.h5", datasetPath: "/data",
                shape: [200, 200, qy, qx], dtypeDescription: "float32", chunkShape: nil
            )
            let budget = 16 << 20
            let steps = DatasetPreviewBuilder.stride(for: descriptor, byteBudget: budget)
            let sampled = ((descriptor.ry + steps.y - 1) / steps.y)
                * ((descriptor.rx + steps.x - 1) / steps.x)
            let bytes = sampled * qy * qx * MemoryLayout<Float>.stride
            XCTAssertLessThanOrEqual(
                bytes, budget * 2,
                "\(qy)x\(qx): sampling \(sampled) positions reads \(bytes) bytes "
                + "against a \(budget) budget — the stride is not controlling cost"
            )
        }
    }

    /// A distorted preview of real space is worse than a coarse one: the user is
    /// looking for features, and their shape is the information.
    func testStrideIsEqualOnBothAxesSoTheAspectRatioSurvives() {
        let wide = DatasetDescriptor(
            filePath: "/tmp/x.h5", datasetPath: "/data",
            shape: [40, 400, 128, 128], dtypeDescription: "float32", chunkShape: nil
        )
        let steps = DatasetPreviewBuilder.stride(for: wide, byteBudget: 1 << 20)
        XCTAssertEqual(steps.y, steps.x)
    }

    /// The same file must give the same sample on every open, or two previews of
    /// one dataset are not comparable.
    func testStrideIsDeterministic() async throws {
        let (_, descriptor) = try await demo()
        let first = DatasetPreviewBuilder.stride(for: descriptor, byteBudget: 4096)
        let second = DatasetPreviewBuilder.stride(for: descriptor, byteBudget: 4096)
        XCTAssertEqual(first.y, second.y)
        XCTAssertEqual(first.x, second.x)
    }

    /// A cube that fits the budget is not sampled at all, and must say so.
    func testAnUnsampledPreviewDoesNotClaimToBeSampled() async throws {
        let (data, descriptor) = try await demo()
        let preview = try await DatasetPreviewBuilder.make(
            data: data, descriptor: descriptor, byteBudget: .max
        )
        XCTAssertFalse(preview.isSampled)
        XCTAssertEqual(preview.sampledPositions, preview.totalPositions)
        XCTAssertEqual(preview.summary, "Preview · every position")
    }

    // MARK: I4 — it says what it is

    func testASampledPreviewStatesItsStrideAndItsFraction() async throws {
        let (data, descriptor) = try await demo()
        let patternBytes = descriptor.qy * descriptor.qx * MemoryLayout<Float>.stride
        // Budget for four patterns, so the demo's 12x12 scan is heavily sampled.
        let preview = try await DatasetPreviewBuilder.make(
            data: data, descriptor: descriptor, byteBudget: patternBytes * 4
        )

        XCTAssertTrue(preview.isSampled)
        XCTAssertGreaterThan(preview.strideY, 1)
        XCTAssertLessThan(preview.sampledPositions, preview.totalPositions)
        XCTAssertTrue(preview.summary.contains("Sampled"), preview.summary)
        XCTAssertTrue(
            preview.summary.contains("\(preview.strideY)")
            || preview.summary.contains("2nd") || preview.summary.contains("3rd"),
            "The stride must be stated, not implied: \(preview.summary)"
        )
        XCTAssertTrue(preview.summary.contains("of"), preview.summary)
    }

    /// The preview grid is the SAMPLE's shape, not the scan's. This is what
    /// makes a pixel-for-pixel comparison against a real virtual image
    /// impossible rather than merely discouraged.
    func testThePreviewGridIsTheSampleNotTheFullScan() async throws {
        let (data, descriptor) = try await demo()
        let patternBytes = descriptor.qy * descriptor.qx * MemoryLayout<Float>.stride
        let preview = try await DatasetPreviewBuilder.make(
            data: data, descriptor: descriptor, byteBudget: patternBytes * 4
        )
        XCTAssertLessThan(preview.realSpace.width, descriptor.rx)
        XCTAssertLessThan(preview.realSpace.height, descriptor.ry)
        XCTAssertEqual(
            preview.realSpace.pixels.count,
            preview.realSpace.width * preview.realSpace.height
        )
        XCTAssertEqual(preview.sampledPositions, preview.realSpace.pixels.count)
    }

    /// Mean and max come from the sample, and the detector shape is the real
    /// one — a preview reduces the SCAN axis, never the detector.
    func testDiffractionPreviewsKeepTheRealDetectorShape() async throws {
        let (data, descriptor) = try await demo()
        let preview = try await DatasetPreviewBuilder.make(
            data: data, descriptor: descriptor, byteBudget: 4096
        )
        XCTAssertEqual(preview.meanDP.qy, descriptor.qy)
        XCTAssertEqual(preview.meanDP.qx, descriptor.qx)
        XCTAssertEqual(preview.maxDP.qy, descriptor.qy)
        XCTAssertEqual(preview.maxDP.qx, descriptor.qx)
        for (mean, max) in zip(preview.meanDP.pixels, preview.maxDP.pixels) {
            XCTAssertLessThanOrEqual(mean, max + 1e-4,
                                     "a mean over the sample cannot exceed its max")
        }
    }

    /// Building a preview must not publish anything into the result pipeline.
    /// I4 says a preview cannot be promoted to a product; the enforcement is
    /// that `DatasetPreview` is its own type which no product path accepts, and
    /// this is the regression test for someone wiring it in later.
    func testBuildingAPreviewPublishesNoResult() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let before = state.resultImage?.pixels

        let (data, descriptor) = try await demo()
        _ = try await DatasetPreviewBuilder.make(
            data: data, descriptor: descriptor, byteBudget: 4096
        )

        XCTAssertEqual(state.resultImage?.pixels, before,
                       "a preview changed the published result")
    }

    func testACancelledPreviewPublishesNothing() async throws {
        let (data, descriptor) = try await demo()
        let token = AnalysisCancellationToken()
        token.cancel()
        do {
            _ = try await DatasetPreviewBuilder.make(
                data: data, descriptor: descriptor, byteBudget: 4096,
                cancellation: token
            )
            XCTFail("a cancelled preview returned a result")
        } catch is CancellationError {
            // expected
        }
    }
}
