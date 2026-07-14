import XCTest
@testable import mac4DSTEM

final class ProductWorkflowTests: XCTestCase {
    func testEveryAnalysisHasOneProductWorkspace() {
        let routed = WorkspaceArea.allCases.flatMap(\.analysisModes)
        XCTAssertEqual(Set(routed.map(\.id)).count, AnalysisMode.allCases.count)
        XCTAssertEqual(routed.count, AnalysisMode.allCases.count)

        for mode in AnalysisMode.allCases {
            XCTAssertTrue(mode.workspaceArea.analysisModes.contains(mode))
        }
    }

    func testPrimaryNavigationUsesUserOutcomes() {
        XCTAssertEqual(
            WorkspaceArea.allCases.map(\.title),
            ["Prepare", "Image", "Map", "Reconstruct", "Results"]
        )
        XCTAssertEqual(WorkspaceArea.image.defaultAnalysisMode, .virtualDetector)
        XCTAssertEqual(WorkspaceArea.map.defaultAnalysisMode, .disks)
        XCTAssertEqual(WorkspaceArea.reconstruct.defaultAnalysisMode, .ptychography)
        XCTAssertNil(WorkspaceArea.prepare.defaultAnalysisMode)
        XCTAssertNil(WorkspaceArea.results.defaultAnalysisMode)
    }

    func testPrerequisitesAreActionableAndTaskSpecific() {
        let empty = ProductWorkflowReadiness()
        XCTAssertTrue(ProductWorkflow.prerequisites(
            for: .virtualDetector, readiness: empty
        ).isEmpty)
        XCTAssertTrue(ProductWorkflow.prerequisites(for: .dpc, readiness: empty).isEmpty)
        XCTAssertTrue(ProductWorkflow.guidance(for: .dpc, readiness: empty)
            .first?.contains("qualitative units") == true)
        XCTAssertEqual(ProductWorkflow.prerequisites(
            for: .strain, readiness: empty
        ), ["Detect Bragg disks first"])
        XCTAssertEqual(ProductWorkflow.prerequisites(
            for: .acom,
            readiness: ProductWorkflowReadiness(hasBraggVectors: true)
        ), [])

        let reconstructionMissing = ProductWorkflow.prerequisites(
            for: .ptychography,
            readiness: ProductWorkflowReadiness(
                hasOriginProbe: true, hasRotation: true,
                hasQScale: true, hasRScale: true
            )
        )
        XCTAssertEqual(reconstructionMissing, ["Set the accelerating voltage"])
    }

    func testRecommendedFlowMovesTowardAReusableResult() {
        XCTAssertEqual(
            ProductWorkflow.recommendedNextArea(calibrationReady: false, hasResult: false),
            .prepare
        )
        XCTAssertEqual(
            ProductWorkflow.recommendedNextArea(calibrationReady: true, hasResult: false),
            .image
        )
        XCTAssertEqual(
            ProductWorkflow.recommendedNextArea(calibrationReady: true, hasResult: true),
            .results
        )
    }

    func testNavigationDoesNotRelabelTheVisibleScientificResult() {
        let state = AppState()
        state.resultImage = FloatImage(width: 1, height: 1, pixels: [1])
        XCTAssertEqual(state.currentResultDisplayName, "Virtual detector · Annulus")

        state.changeMode(.dpc)
        XCTAssertEqual(state.currentResultDisplayName, "Virtual detector · Annulus")
        XCTAssertEqual(state.currentResultKind, "virtual_annulus")

        state.resultImage = FloatImage(width: 1, height: 1, pixels: [2])
        XCTAssertEqual(state.currentResultDisplayName, "DPC magnitude")
    }

    func testACOMRegionUsesScanReferenceWithoutReplacingBraggResult() {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/example.h5", datasetPath: "/data",
            shape: [153, 106, 256, 256], dtypeDescription: "float32",
            chunkShape: nil
        )
        state.calibration.rPixelSize = 2
        state.calibration.rPixelUnits = "nm"
        state.calibration.qPixelSize = 0.01
        state.calibration.qPixelUnits = "Å⁻¹"
        state.analysisMode = .disks
        state.workspaceArea = .map
        state.resultImage = FloatImage(
            width: 256, height: 256,
            pixels: [Float](repeating: 1, count: 256 * 256)
        )
        state.scanNavigationImage = FloatImage(
            width: 106, height: 153,
            pixels: [Float](repeating: 2, count: 106 * 153)
        )

        state.changeMode(.acom)
        state.acomScope = .selectedRegion

        XCTAssertTrue(state.showsACOMRegionReference)
        XCTAssertEqual(state.displayedResultImage?.width, 106)
        XCTAssertEqual(state.displayedResultImage?.height, 153)
        XCTAssertEqual(state.displayedResultKind, "acom_region_reference")
        XCTAssertEqual(state.displayedResultPixelMetadata.units, "nm")

        XCTAssertEqual(state.resultImage?.width, 256)
        XCTAssertEqual(state.resultImage?.height, 256)
        XCTAssertEqual(state.currentResultKind, "bragg_vector_map")
        XCTAssertEqual(state.currentResultPersistenceMetadata.units, "Å⁻¹")
    }
}
