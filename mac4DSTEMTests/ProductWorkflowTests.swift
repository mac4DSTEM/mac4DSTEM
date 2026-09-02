import AppKit
import DSTEMCore
import XCTest
@testable import mac4DSTEM

final class ProductWorkflowTests: XCTestCase {
    func testPublicationFigureBurnsScaleCaptionAndColorbar() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let baseContext = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 12,
            bitsPerComponent: 8, bytesPerRow: 16 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        baseContext.setFillColor(NSColor.systemRed.cgColor)
        baseContext.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        let base = try XCTUnwrap(baseContext.makeImage())

        let withScale = AppState.burnScaleBar(
            on: base, unitsPerDataPixel: 0.5, unitLabel: "nm"
        )
        XCTAssertEqual(withScale.width, 512)
        XCTAssertEqual(withScale.height, 384)

        let figure = AppState.publicationFigure(
            image: withScale, title: "Strain ε_xx",
            caption: "scan space · quantitative · 0.5 nm/px · basis_mode=consensus",
            valueRange: (low: -0.025, high: 0.025), valueUnits: "strain",
            colormap: .rdbu
        )
        XCTAssertEqual(figure.width, 624)
        XCTAssertEqual(figure.height, 478)

        var pixels = [UInt8](repeating: 0, count: figure.width * figure.height * 4)
        let raster = try XCTUnwrap(CGContext(
            data: &pixels, width: figure.width, height: figure.height,
            bitsPerComponent: 8, bytesPerRow: figure.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        raster.draw(figure, in: CGRect(x: 0, y: 0,
                                       width: figure.width, height: figure.height))

        func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let offset = (y * figure.width + x) * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
        }
        func isInk(_ value: (UInt8, UInt8, UInt8)) -> Bool {
            value.0 > 20 || value.1 > 20 || value.2 > 20
        }
        func isNearWhite(_ value: (UInt8, UInt8, UInt8)) -> Bool {
            value.0 > 225 && value.1 > 225 && value.2 > 225
        }

        var captionInk = 0
        for y in 0..<76 {
            for x in 18..<500 where isInk(rgb(x: x, y: y)) { captionInk += 1 }
        }
        for y in (figure.height - 76)..<figure.height {
            for x in 18..<500 where isInk(rgb(x: x, y: y)) { captionInk += 1 }
        }
        XCTAssertGreaterThan(captionInk, 100, "title/provenance caption disappeared")

        var colorbarColors = Set<UInt32>()
        for y in 76..<(76 + withScale.height) {
            let value = rgb(x: 550, y: y)
            colorbarColors.insert(
                UInt32(value.0) << 16 | UInt32(value.1) << 8 | UInt32(value.2)
            )
        }
        XCTAssertGreaterThan(colorbarColors.count, 100, "colorbar lost its numeric gradient")

        var whitePixels = 0
        for y in 76..<(76 + withScale.height) {
            for x in 18..<(18 + withScale.width) where isNearWhite(rgb(x: x, y: y)) {
                whitePixels += 1
            }
        }
        XCTAssertGreaterThan(whitePixels, 200, "burned scale bar/label disappeared")
    }

    func testEveryAnalysisHasOneProductWorkspace() {
        let routed = WorkspaceArea.allCases.flatMap(\.analysisModes)
        XCTAssertEqual(Set(routed.map(\.id)).count, AnalysisMode.allCases.count)
        XCTAssertEqual(routed.count, AnalysisMode.allCases.count)

        for mode in AnalysisMode.allCases {
            XCTAssertTrue(mode.workspaceArea.analysisModes.contains(mode))
        }
    }

    func testPrimaryNavigationUsesUserOutcomes() {
        // S22c re-cut: the five steps follow the physics families — Imaging
        // (no prerequisites), Bragg (disks → strain/orientation), Phase
        // (voltage-only: DPC first, ptychography behind it).
        XCTAssertEqual(
            WorkspaceArea.allCases.map(\.title),
            ["Prepare", "Imaging", "Strain & ACOM", "Phase", "Results"]
        )
        XCTAssertEqual(WorkspaceArea.image.defaultAnalysisMode, .virtualDetector)
        XCTAssertEqual(WorkspaceArea.map.defaultAnalysisMode, .disks)
        XCTAssertEqual(WorkspaceArea.reconstruct.defaultAnalysisMode, .dpc)
        XCTAssertEqual(AnalysisMode.dpc.workspaceArea, .reconstruct,
                       "DPC belongs to the Phase family workspace")
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
        ), ["Choose an ACOM material model"])
        XCTAssertEqual(ProductWorkflow.prerequisites(
            for: .acom,
            readiness: ProductWorkflowReadiness(
                hasBraggVectors: true, hasACOMMaterial: true,
                hasSupportedACOMMaterial: true
            )
        ), [])
        XCTAssertEqual(ProductWorkflow.prerequisites(
            for: .acom,
            readiness: ProductWorkflowReadiness(
                hasBraggVectors: true, hasACOMMaterial: true,
                hasSupportedACOMMaterial: false
            )
        ), ["The selected ACOM material is not supported"])

        let reconstructionMissing = ProductWorkflow.prerequisites(
            for: .ptychography,
            readiness: ProductWorkflowReadiness(
                hasOriginProbe: true, hasRotation: true,
                hasQScale: true, hasRScale: true
            )
        )
        XCTAssertEqual(reconstructionMissing, ["Set the accelerating voltage"])
    }

    func testPrerequisiteChecklistItemsMatchPrerequisiteStrings() {
        let complete = ProductWorkflowReadiness(
            hasOriginProbe: true, hasRotation: true, hasQScale: true,
            hasRScale: true, hasVoltage: true, hasBraggVectors: true,
            hasACOMMaterial: true, hasSupportedACOMMaterial: true,
            hasPhysicalACOMScale: true
        )
        let syntheticStates = [
            ProductWorkflowReadiness(),
            complete,
            // sim_Au's measured Reconstruct blocker: everything but R scale.
            ProductWorkflowReadiness(
                hasOriginProbe: true, hasRotation: true, hasQScale: true,
                hasRScale: false, hasVoltage: true
            ),
            ProductWorkflowReadiness(
                hasBraggVectors: true, hasACOMMaterial: true,
                hasSupportedACOMMaterial: false
            )
        ]
        for mode in AnalysisMode.allCases {
            for readiness in syntheticStates {
                let items = ProductWorkflow.prerequisiteItems(
                    for: mode, readiness: readiness
                )
                // The checklist's unmet rows are exactly the legacy gating
                // strings, in the same order — the two surfaces cannot drift.
                XCTAssertEqual(
                    items.filter { !$0.isSatisfied }.map(\.title),
                    ProductWorkflow.prerequisites(for: mode, readiness: readiness)
                )
                // Row ids are unique so accessibility identifiers are stable.
                XCTAssertEqual(Set(items.map(\.id)).count, items.count)
            }
            XCTAssertTrue(
                ProductWorkflow.prerequisiteItems(for: mode, readiness: complete)
                    .allSatisfy(\.isSatisfied)
            )
        }

        // The sim_Au case: the checklist shows all five rows with only R scale
        // unmet, and points it at the Prepare workspace.
        let simAu = ProductWorkflow.prerequisiteItems(
            for: .ptychography,
            readiness: ProductWorkflowReadiness(
                hasOriginProbe: true, hasRotation: true, hasQScale: true,
                hasRScale: false, hasVoltage: true
            )
        )
        XCTAssertEqual(simAu.count, 5)
        XCTAssertEqual(simAu.filter { !$0.isSatisfied }.map(\.id), ["rScale"])
        XCTAssertEqual(
            simAu.first { $0.id == "rScale" }?.title, "Set the R pixel scale"
        )
        XCTAssertEqual(simAu.first { $0.id == "rScale" }?.resolution, .prepare)

        // Cross-task prerequisites navigate to the producing task; in-panel
        // ones point at the panel instead of navigating away.
        let strainItems = ProductWorkflow.prerequisiteItems(
            for: .strain, readiness: ProductWorkflowReadiness()
        )
        XCTAssertEqual(strainItems.map(\.resolution), [.task(.disks)])
        let acomItems = ProductWorkflow.prerequisiteItems(
            for: .acom, readiness: ProductWorkflowReadiness(hasBraggVectors: true)
        )
        XCTAssertEqual(acomItems.first { $0.id == "braggVectors" }?.isSatisfied, true)
        guard case .taskPanel = acomItems.first(where: { $0.id == "acomMaterial" })?.resolution
        else { return XCTFail("ACOM material should resolve in its own panel") }
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

    /// IPF·Z is promoted over the Reliability default only for a user who has
    /// not chosen a display. The flag is what separates "still on the default"
    /// from "asked for Reliability", which `didSet` alone cannot see — if it
    /// stopped being set, a completed map would overrule a deliberate choice.
    func testChoosingAnACOMDisplayIsRecordedSoItIsNotLaterOverridden() {
        let state = AppState()
        XCTAssertEqual(state.acomDisplay, .reliability)
        XCTAssertFalse(state.acomDisplayIsUserChosen)

        state.selectACOMDisplay(.score)
        XCTAssertEqual(state.acomDisplay, .score)
        XCTAssertTrue(state.acomDisplayIsUserChosen)

        // Re-selecting the default is still a choice, not a reset.
        state.selectACOMDisplay(.reliability)
        XCTAssertEqual(state.acomDisplay, .reliability)
        XCTAssertTrue(state.acomDisplayIsUserChosen)
    }

    /// The hint is a forward pointer, so what it *doesn't* say matters as much
    /// as what it does: repeating the calibration checklist or the task group
    /// labels would be noise on the exact screens that already say it.
    func testNextStepHintPointsForwardAndStaysSilentWhereTheUIAlreadyExplains() {
        var readiness = ProductWorkflowReadiness()

        // Prepare: silent while the checklist is still naming missing fields.
        XCTAssertNil(ProductWorkflow.nextStepHint(
            for: .prepare, readiness: readiness, calibrationReady: false
        ))
        XCTAssertNotNil(ProductWorkflow.nextStepHint(
            for: .prepare, readiness: readiness, calibrationReady: true
        ))

        // Map: silent before disks exist — the task group labels already say
        // which tasks require Bragg vectors.
        XCTAssertNil(ProductWorkflow.nextStepHint(
            for: .map, readiness: readiness, calibrationReady: true
        ))

        // Image points at the Bragg path only while it is still unsatisfied.
        XCTAssertNotNil(ProductWorkflow.nextStepHint(
            for: .image, readiness: readiness, calibrationReady: true
        ))

        readiness.hasBraggVectors = true
        XCTAssertNil(ProductWorkflow.nextStepHint(
            for: .image, readiness: readiness, calibrationReady: true
        ))
        XCTAssertNotNil(ProductWorkflow.nextStepHint(
            for: .map, readiness: readiness, calibrationReady: true
        ))

        // Terminal for this purpose regardless of state.
        for ready in [false, true] {
            XCTAssertNil(ProductWorkflow.nextStepHint(
                for: .results, readiness: readiness, calibrationReady: ready
            ))
            XCTAssertNil(ProductWorkflow.nextStepHint(
                for: .reconstruct, readiness: readiness, calibrationReady: ready
            ))
        }
    }

    /// Every task belongs to exactly one prerequisite family, and `.disks` must
    /// be the producer — a single "requires Bragg vectors" label spanning Map
    /// would be wrong about the one task that satisfies it.
    func testTaskPrerequisiteFamiliesSplitTheBraggDependencyCorrectly() {
        XCTAssertEqual(AnalysisMode.disks.prerequisiteFamily, .producesBraggVectors)
        XCTAssertEqual(AnalysisMode.strain.prerequisiteFamily, .requiresBraggVectors)
        XCTAssertEqual(AnalysisMode.acom.prerequisiteFamily, .requiresBraggVectors)
        for mode in [AnalysisMode.virtualDetector, .dpc, .ptychography] {
            XCTAssertEqual(mode.prerequisiteFamily, .phaseContrast, "\(mode)")
        }

        // Grouping must not drop or duplicate a task in any workspace.
        for area in WorkspaceArea.allCases {
            let grouped = area.taskFamilyGroups.flatMap(\.modes)
            XCTAssertEqual(Set(grouped), Set(area.analysisModes), "\(area)")
            XCTAssertEqual(grouped.count, area.analysisModes.count, "\(area)")
        }
    }

    /// The family caption exists to *distinguish* families, so it is drawn only
    /// where there is more than one to distinguish (design pass 2026-08-05,
    /// refining #4). Reconstruct had it sitting over a single task, and Image
    /// over a single family — noise in both.
    func testFamilyCaptionsAreDrawnOnlyWhereThereIsMoreThanOneFamily() {
        XCTAssertTrue(WorkspaceArea.map.showsTaskFamilyLabels, "Map: disks vs strain/ACOM")
        XCTAssertFalse(
            WorkspaceArea.reconstruct.showsTaskFamilyLabels,
            "Reconstruct has one task; a caption above it says nothing"
        )
        XCTAssertFalse(
            WorkspaceArea.image.showsTaskFamilyLabels,
            "Image has two tasks but one family; there is nothing to distinguish"
        )

        // Workspaces with no tasks must not claim to need captions.
        for area in [WorkspaceArea.prepare, .results] {
            XCTAssertTrue(area.taskFamilyGroups.isEmpty, "\(area)")
            XCTAssertFalse(area.showsTaskFamilyLabels, "\(area)")
        }

        // The rule must agree with the grouping it labels.
        for area in WorkspaceArea.allCases {
            XCTAssertEqual(
                area.showsTaskFamilyLabels, area.taskFamilyGroups.count > 1, "\(area)"
            )
        }
    }

    func testNavigationDoesNotRelabelTheVisibleScientificResult() {
        let state = AppState()
        state.resultImage = FloatImage(width: 1, height: 1, pixels: [1])
        XCTAssertEqual(state.currentResultDisplayName, "Virtual detector · Annulus")
        XCTAssertEqual(state.displayedProduct?.domain, .scan)

        state.changeMode(.dpc)
        XCTAssertEqual(state.currentResultDisplayName, "Virtual detector · Annulus")
        XCTAssertEqual(state.currentResultKind, "virtual_annulus")
        XCTAssertEqual(state.displayedProduct?.domain, .scan)

        state.resultImage = FloatImage(width: 1, height: 1, pixels: [2])
        XCTAssertEqual(state.currentResultDisplayName, "DPC magnitude")
        XCTAssertEqual(state.displayedProduct?.domain, .scan)

        state.changeMode(.disks)
        state.resultImage = FloatImage(width: 1, height: 1, pixels: [3])
        XCTAssertEqual(state.displayedProduct?.domain, .detector)
    }

    func testDPCScalarAnglePublishesRadianEncodingProvenance() {
        let state = AppState()
        state.navigation.analysisMode = .dpc
        state.dpcDisplay = .angle
        state.resultImage = FloatImage(width: 1, height: 1, pixels: [.pi / 2])

        XCTAssertEqual(state.currentResultKind, "dpc_angle")
        XCTAssertEqual(state.currentResultValueUnits, "rad")
        XCTAssertEqual(
            state.currentResultPersistenceMetadata.provenance[
                ScalarResultMap.dpcAngleEncodingKey
            ],
            ScalarResultMap.dpcAngleRadiansEncoding
        )
        XCTAssertEqual(
            state.exportedImageProvenanceRecord()["value_units"] as? String,
            "rad"
        )
        let sidecarMap = state.currentScalarResultMapForPersistence()
        XCTAssertEqual(sidecarMap?.pixels, [.pi / 2])
        XCTAssertEqual(sidecarMap?.valueUnits, "rad")
        XCTAssertEqual(
            sidecarMap?.provenance[ScalarResultMap.dpcAngleEncodingKey],
            ScalarResultMap.dpcAngleRadiansEncoding
        )
    }

    func testRestoredForeignDPCAngleEncodingIsNotRelabeled() {
        let state = AppState()
        state.resultImage = FloatImage(width: 1, height: 1, pixels: [90])
        state.restoredResultInfo = ("dpc_angle", "Imported DPC angle", "degrees")
        state.restoredResultPixelInfo = (
            nil, nil, nil, [ScalarResultMap.dpcAngleEncodingKey: "degrees"]
        )

        let map = state.currentScalarResultMapForPersistence()
        XCTAssertEqual(map?.pixels, [90])
        XCTAssertEqual(map?.valueUnits, "degrees")
        XCTAssertEqual(
            map?.provenance[ScalarResultMap.dpcAngleEncodingKey], "degrees"
        )
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
        state.navigation.analysisMode = .disks
        state.navigation.workspaceArea = .map
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

    func testCalibrationReadinessExplainsWhatEveryFieldUnlocks() {
        XCTAssertEqual(CalibrationReadinessKind.allCases.count, 5)
        for kind in CalibrationReadinessKind.allCases {
            XCTAssertTrue(kind.unlockSummary.hasPrefix("Unlocks")
                          || kind.unlockSummary.hasPrefix("Corrects"))
            XCTAssertTrue(kind.unlockSummary.hasSuffix("."))
        }
        XCTAssertTrue(CalibrationReadinessKind.qScale.unlockSummary.contains("reciprocal"))
        XCTAssertTrue(CalibrationReadinessKind.rScale.unlockSummary.contains("scale bars"))
    }

    func testManualPixelScaleReplacesIndexUnitsWithExplicitPhysicalUnits() {
        let state = AppState()
        state.calibration.rPixelSize = 1
        state.calibration.rPixelUnits = "pixels"
        state.calibration.qPixelSize = 1
        state.calibration.qPixelUnits = "pixels"

        XCTAssertEqual(state.manualRPixelUnits, "nm")
        XCTAssertEqual(state.manualQPixelUnits, "nm⁻¹")
        XCTAssertNil(state.manualRPixelSize)
        XCTAssertNil(state.manualQPixelSize)

        state.setManualRPixelSize(0.5)
        XCTAssertEqual(state.calibration.rPixelSize, 0.5)
        XCTAssertEqual(state.calibration.rPixelUnits, "nm")
        XCTAssertEqual(state.manualRPixelSize, 0.5)
        XCTAssertEqual(state.calibrationProvenance.rScale, .manual)

        state.setManualRPixelUnits("Å")
        XCTAssertEqual(state.calibration.rPixelUnits, "Å")
        let rItem = state.calibrationReadiness.items.first { $0.kind == .rScale }
        XCTAssertEqual(rItem?.status, .ready(.manual))

        state.setManualQPixelSize(0.25)
        XCTAssertEqual(state.calibration.qPixelUnits, "nm⁻¹")
        XCTAssertEqual(state.acomScale, 0.025, accuracy: 1e-12)
        state.setManualQPixelUnits("Å⁻¹")
        XCTAssertEqual(state.calibration.qPixelUnits, "Å⁻¹")
        XCTAssertEqual(state.acomScale, 0.25, accuracy: 1e-12)
    }

    func testACOMRequiresExplicitMaterialAndPreservesScaleMeaning() {
        let state = AppState()
        XCTAssertEqual(state.acomModelSelection, .none)
        XCTAssertEqual(state.acomScaleSemantics.provenance, .exploratory)
        XCTAssertEqual(state.acomScale, 0.01, accuracy: 1e-12)
        XCTAssertFalse(state.productWorkflowReadiness.hasACOMMaterial)

        state.acomModelSelection = .library("not_a_model")
        XCTAssertTrue(state.productWorkflowReadiness.hasACOMMaterial)
        XCTAssertFalse(state.productWorkflowReadiness.hasSupportedACOMMaterial)
        XCTAssertNotNil(state.acomModelSelectionIssue)

        state.acomModelSelection = .library("au_fcc")
        XCTAssertTrue(state.productWorkflowReadiness.hasSupportedACOMMaterial)
        XCTAssertEqual(state.resolvedACOMModel?.displayName, "Gold (FCC)")
        state.acomExploratoryScale = 0.02
        XCTAssertEqual(state.acomScale, 0.02, accuracy: 1e-12)
        XCTAssertEqual(state.acomScaleSemantics.provenance, .exploratory)

        state.setManualQPixelSize(0.25)
        XCTAssertEqual(state.acomScaleSemantics.provenance, .manual)
        XCTAssertTrue(state.productWorkflowReadiness.hasPhysicalACOMScale)
    }

    func testCrystalModelLibraryIsCompleteAndSymmetryValidated() {
        let models = CrystalModelLibrary.models
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertFalse(models.isEmpty)
        for model in models {
            XCTAssertTrue(model.isUsable, "\(model.displayName): \(model.validationIssues)")
            XCTAssertFalse(model.crystal.sites.isEmpty)
            XCTAssertFalse(model.crystal.reflections(kMax: 1.2).isEmpty)
            XCTAssertEqual(model.provenance["crystal_model_id"], model.id)
            XCTAssertEqual(model.provenance["crystal_symmetry"], model.symmetry.rawValue)
        }

        let invalid = CrystalModelLibrary.customCubic(
            structure: .fcc, latticeA: 0, atomicNumber: 79
        )
        XCTAssertFalse(invalid.isUsable)
        XCTAssertTrue(invalid.validationIssues.contains {
            $0.code == "invalid_cell_lengths"
        })
    }

    func testACOMRunSemanticsNeverPromotesFallbackScale() {
        let exploratory = ACOMRunSemantics(
            materialModelID: "au_fcc", materialDescription: "Gold (FCC)",
            scale: ACOMScaleSemantics(
                invAngstromPerPixel: 0.01, provenance: .exploratory
            )
        )
        XCTAssertEqual(exploratory.productStatus(for: "acom_reliability"), .exploratory)
        XCTAssertEqual(exploratory.productStatus(for: "acom_ipf_z"), .exploratory)
        XCTAssertEqual(exploratory.provenance["interpretation"], "exploratory")

        let physical = ACOMRunSemantics(
            materialModelID: "au_fcc", materialDescription: "Gold (FCC)",
            scale: ACOMScaleSemantics(
                invAngstromPerPixel: 0.02, provenance: .importedFile
            )
        )
        XCTAssertEqual(physical.productStatus(for: "acom_reliability"), .relative)
        XCTAssertEqual(physical.productStatus(for: "acom_score"), .relative)
        XCTAssertEqual(physical.productStatus(for: "acom_phi1"), .quantitative)
        XCTAssertEqual(physical.productStatus(for: "acom_ipf_z"), .categorical)
        XCTAssertEqual(physical.provenance["q_scale_provenance"], "imported_file")
    }

    func testRejectedStrainPixelsAreNoDataRatherThanZeroStrain() {
        let map = StrainMap(
            width: 2, height: 1,
            exx: [0.125, 0], eyy: [0, 0], exy: [0, 0], theta: [0, 0],
            mask: [true, false],
            localG1x: [1, 0], localG1y: [0, 0],
            localG2x: [0, 0], localG2y: [1, 0],
            localResidualPixels: [0.01, 0],
            refG1: (1, 0), refG2: (0, 1),
            referencePositionCount: 1, indexedFraction: 0.5,
            diagnostics: StrainFitDiagnostics(
                automaticBasis: true, referenceMaskApplied: false,
                basisObservationCount: 1, basisSupportCount: 1,
                basisSupportFraction: 1, basisResidualPixels: 0,
                basisConditionNumber: 1, indexingTolerancePixels: 1,
                localResidualMedianPixels: 0.01,
                referenceCandidateCount: 1, referenceRejectedCount: 0
            )
        )
        let image = map.component(.exx)
        XCTAssertEqual(image.pixels[0], 0.125)
        XCTAssertTrue(image.pixels[1].isNaN)
        XCTAssertEqual(image.normalized(symmetric: true)[1], FloatImage.invalidDisplayValue)
    }

    func testDisplayedProductCarriesDomainMaskUnitsQualityAndCursorValues() throws {
        let image = FloatImage(width: 2, height: 1, pixels: [1.25, .nan])
        let quality = FloatImage(width: 2, height: 1, pixels: [0.02, 0.9])
        let product = DisplayedProduct(
            kind: "strain_exx", displayName: "Strain",
            payload: .scalar(image), domain: .scan,
            qualityFields: [ProductQualityField(
                name: "fit residual", units: "detector_px", image: quality
            )],
            sampling: ProductSampling(row: 0.5, column: 0.5, units: "nm"),
            valueUnits: "strain", quantitativeStatus: .quantitative,
            provenance: ["method": "local_lattice_fit"]
        )
        XCTAssertEqual(product.domain, .scan)
        XCTAssertEqual(product.provenance["display_domain"], "scan")
        XCTAssertEqual(product.validityMask, [true, false])
        XCTAssertEqual(try XCTUnwrap(product.sample(x: 0, y: 0)).value, 1.25)
        XCTAssertEqual(product.sample(x: 0, y: 0)?.quality["fit residual"], 0.02)
        XCTAssertNil(product.sample(x: 1, y: 0)?.value)
        XCTAssertTrue(product.sample(x: 1, y: 0)?.accessibilityText.contains("no data") == true)
        XCTAssertNil(product.sample(x: 2, y: 0))
    }

    func testDifferenceRequiresNumericSemanticParityAndPreservesNoData() throws {
        func product(_ values: [Float], units: String = "strain",
                     domain: ProductDomain = .scan) -> DisplayedProduct {
            DisplayedProduct(
                kind: "strain", displayName: "strain",
                payload: .scalar(FloatImage(width: 2, height: 1, pixels: values)),
                domain: domain,
                sampling: ProductSampling(row: 1, column: 1, units: "nm"),
                valueUnits: units, quantitativeStatus: .quantitative
            )
        }
        let difference = try XCTUnwrap(ProductComparison.difference(
            product([3, .nan]), product([1, 2])
        ))
        guard case .scalar(let image) = difference.payload else {
            return XCTFail("Expected scalar difference")
        }
        XCTAssertEqual(image.pixels[0], 2, accuracy: 1e-7)
        XCTAssertTrue(image.pixels[1].isNaN)
        XCTAssertEqual(difference.validityMask, [true, false])
        XCTAssertEqual(
            ProductComparison.compatibility(product([1, 2]), product([1, 2], units: "rad")),
            .incompatible("Value units differ.")
        )
        XCTAssertNil(ProductComparison.difference(
            product([1, 2]), product([1, 2], domain: .detector)
        ))
    }

    func testStrainQualityViewsRetainMaskMeaning() {
        let map = StrainMap(
            width: 2, height: 1, exx: [0, 0], eyy: [0, 0], exy: [0, 0], theta: [0, 0],
            mask: [true, false], localG1x: [1, 0], localG1y: [0, 0],
            localG2x: [0, 0], localG2y: [1, 0], localResidualPixels: [0.125, 0],
            refG1: (1, 0), refG2: (0, 1), referencePositionCount: 1,
            indexedFraction: 0.5,
            diagnostics: StrainFitDiagnostics(
                automaticBasis: true, referenceMaskApplied: false,
                basisObservationCount: 1, basisSupportCount: 1,
                basisSupportFraction: 1, basisResidualPixels: 0,
                basisConditionNumber: 1, indexingTolerancePixels: 1,
                localResidualMedianPixels: 0.125,
                referenceCandidateCount: 1, referenceRejectedCount: 0
            )
        )
        XCTAssertEqual(map.component(.residual).pixels[0], 0.125)
        XCTAssertTrue(map.component(.residual).pixels[1].isNaN)
        XCTAssertEqual(map.component(.indexed).pixels[0], 1)
        XCTAssertTrue(map.component(.indexed).pixels[1].isNaN)
    }
}
