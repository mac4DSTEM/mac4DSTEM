//
//  ReplayPlanTests.swift
//  v2 S6 — the pure half of the replay executor: parsing recorded steps back
//  into typed plans, the detector-frame tag, and the order rules. The keys and
//  vocabularies asserted here are the ones the S5 recording sites write; a
//  drift between recorder and parser is exactly what these pin.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class ReplayPlanTests: XCTestCase {

    // MARK: - Virtual detector

    private var virtualDetectorStep: SessionReplayRecord.Step {
        .init(kind: "virtual_detector",
              parameters: ["shape": "Annulus",
                           "center_x": "31.5", "center_y": "30.0",
                           "inner": "3.0", "outer": "9.0"],
              recorded: Date(timeIntervalSince1970: 0))
    }

    func testVirtualDetectorParsesTheRecordedApertureAndShape() throws {
        let plan = try ReplayPlanner.parse(virtualDetectorStep).get()
        XCTAssertEqual(plan, .virtualDetector(
            shape: .annulus,
            aperture: Aperture(centerX: 31.5, centerY: 30.0, inner: 3.0, outer: 9.0)
        ))
        XCTAssertTrue(plan.usesDetectorFrameParameters,
                      "An aperture is detector pixels — the frame gate must see it")
    }

    func testVirtualDetectorRefusesAMissingKeyByName() {
        var step = virtualDetectorStep
        step.parameters.removeValue(forKey: "center_x")
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("A missing coordinate must refuse, not default")
        }
        XCTAssertTrue(refusal.reason.contains("center_x"),
                      "The refusal must name the unreadable key: \(refusal.reason)")
    }

    func testVirtualDetectorRefusesAnOuterSmallerThanInner() {
        var step = virtualDetectorStep
        step.parameters["outer"] = "1.0"
        guard case .failure = ReplayPlanner.parse(step) else {
            return XCTFail("outer < inner is not a runnable aperture")
        }
    }

    func testVirtualDetectorRefusesANonFiniteValue() {
        var step = virtualDetectorStep
        step.parameters["inner"] = "nan"
        guard case .failure = ReplayPlanner.parse(step) else {
            return XCTFail("A NaN radius must refuse, not propagate")
        }
    }

    // MARK: - DPC

    func testDPCParsesBothOriginVocabularyValues() throws {
        func step(_ reference: String) -> SessionReplayRecord.Step {
            .init(kind: "dpc", parameters: ["origin_reference": reference],
                  recorded: Date(timeIntervalSince1970: 0))
        }
        XCTAssertEqual(try ReplayPlanner.parse(step("calibrated origins")).get(),
                       .dpc(wantsFittedOrigin: true))
        XCTAssertEqual(try ReplayPlanner.parse(step("global center")).get(),
                       .dpc(wantsFittedOrigin: false))
        guard case .failure = ReplayPlanner.parse(step("something else")) else {
            return XCTFail("An unknown origin reference must refuse")
        }
        XCTAssertFalse(ReplayStepPlan.dpc(wantsFittedOrigin: true).usesDetectorFrameParameters,
                       "DPC records a mode, not detector numbers")
    }

    // MARK: - Disk detection

    private var diskStep: SessionReplayRecord.Step {
        .init(kind: "disk_detection",
              parameters: ["corr_power": "1.0", "sigma_dp": "0.0", "sigma_cc": "2.5",
                           "subpixel": "multicorr", "upsample_factor": "16",
                           "min_absolute_intensity": "0.0",
                           "min_relative_intensity": "0.005",
                           "relative_to_peak": "0", "min_peak_spacing": "10.0",
                           "edge_boundary": "4", "max_peaks": "70",
                           "kernel_source": "synthetic"],
              recorded: Date(timeIntervalSince1970: 0))
    }

    func testDiskDetectionParsesEveryRecordedParameter() throws {
        guard case .diskDetection(let params) = try ReplayPlanner.parse(diskStep).get() else {
            return XCTFail("Wrong plan kind")
        }
        XCTAssertEqual(params.corrPower, 1.0)
        XCTAssertEqual(params.sigmaCC, 2.5)
        XCTAssertEqual(params.subpixel, .multicorr)
        XCTAssertEqual(params.upsampleFactor, 16)
        XCTAssertEqual(params.minRelativeIntensity, 0.005)
        XCTAssertEqual(params.minPeakSpacing, 10.0)
        XCTAssertEqual(params.edgeBoundary, 4)
        XCTAssertEqual(params.maxNumPeaks, 70)
    }

    func testDiskDetectionRefusesAnUnknownSubpixelMode() {
        var step = diskStep
        step.parameters["subpixel"] = "cubic"
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("An unknown subpixel mode must refuse, never default to another")
        }
        XCTAssertTrue(refusal.reason.contains("subpixel"))
    }

    func testDiskDetectionWithAMeasuredKernelRefusesRatherThanSubstitutingSynthetic() {
        // The thresholds were tuned against the measured kernel's correlation
        // response; regenerating a synthetic one would move every peak with
        // no summary line saying so (Gate A finding C3).
        var step = diskStep
        step.parameters["kernel_source"] = "measured_roi"
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("A measured-kernel rehearsal cannot be replayed with a synthetic kernel")
        }
        XCTAssertTrue(refusal.reason.contains("kernel"), "Reason was: \(refusal.reason)")
    }

    func testDiskDetectionWithoutAKernelSourceRefusesByName() {
        var step = diskStep
        step.parameters.removeValue(forKey: "kernel_source")
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("An absent kernel class is an unknown detection parameter, not a default")
        }
        XCTAssertTrue(refusal.reason.contains("kernel_source"))
    }

    // MARK: - Strain

    func testStrainConsensusReplaysTheModeNotTheResolvedVectors() throws {
        let step = SessionReplayRecord.Step(
            kind: "strain",
            parameters: ["reference_mode": "whole-scan", "basis_mode": "consensus",
                         "resolved_g1_x": "10", "resolved_g1_y": "0",
                         "resolved_g2_x": "0", "resolved_g2_y": "10"],
            recorded: Date(timeIntervalSince1970: 0))
        let plan = try ReplayPlanner.parse(step).get()
        XCTAssertEqual(plan, .strain(.init(manualBasis: nil)),
                       "Consensus re-derives on the full data; the resolved values are informational")
        XCTAssertFalse(plan.usesDetectorFrameParameters,
                       "An automatic-basis strain replays no recorded detector numbers")
    }

    func testStrainManualBasisCarriesTheRecordedVectorsAndIsDetectorFrame() throws {
        let step = SessionReplayRecord.Step(
            kind: "strain",
            parameters: ["reference_mode": "whole-scan", "basis_mode": "manual",
                         "resolved_g1_x": "10.5", "resolved_g1_y": "0.5",
                         "resolved_g2_x": "-0.5", "resolved_g2_y": "10.0"],
            recorded: Date(timeIntervalSince1970: 0))
        let plan = try ReplayPlanner.parse(step).get()
        XCTAssertEqual(plan, .strain(.init(manualBasis:
            .init(g1x: 10.5, g1y: 0.5, g2x: -0.5, g2y: 10.0))))
        XCTAssertTrue(plan.usesDetectorFrameParameters,
                      "Manual g-vectors are detector pixels — the frame gate must see them")
    }

    func testStrainSelectedRegionRefusesBecauseTheRecipeCarriesNoRegion() {
        let step = SessionReplayRecord.Step(
            kind: "strain",
            parameters: ["reference_mode": "selected-region", "basis_mode": "consensus"],
            recorded: Date(timeIntervalSince1970: 0))
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("Replaying a region the recipe does not carry would fabricate one")
        }
        XCTAssertTrue(refusal.reason.contains("region"))
    }

    // MARK: - ACOM

    private var acomStep: SessionReplayRecord.Step {
        .init(kind: "acom",
              parameters: ["material": "library:au_fcc",
                           "scale_inv_angstrom_per_pixel": "0.0125",
                           "matching_backend": "CPU",
                           "scope": "fullScan", "quality": "balanced"],
              recorded: Date(timeIntervalSince1970: 0))
    }

    func testACOMParsesMaterialScaleScopeAndQuality() throws {
        let plan = try ReplayPlanner.parse(acomStep).get()
        XCTAssertEqual(plan, .acom(.init(materialID: "library:au_fcc",
                                         scaleInvAngstromPerPixel: 0.0125,
                                         scope: .fullScan,
                                         quality: .balanced)))
        XCTAssertTrue(plan.usesDetectorFrameParameters,
                      "Å⁻¹ per PIXEL changes meaning with the detector frame")
    }

    func testACOMSelectedRegionRefuses() {
        var step = acomStep
        step.parameters["scope"] = "selectedRegion"
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("The recipe carries no region to replay against")
        }
        XCTAssertTrue(refusal.reason.contains("region"))
    }

    func testACOMRefusesAnUnparseableScale() {
        var step = acomStep
        step.parameters["scale_inv_angstrom_per_pixel"] = "-1"
        guard case .failure = ReplayPlanner.parse(step) else {
            return XCTFail("A non-positive scale is not a runnable match")
        }
    }

    // MARK: - Unknown kinds and order rules

    func testAnUnknownKindRefusesByName() {
        let step = SessionReplayRecord.Step(kind: "future_analysis", parameters: [:],
                                            recorded: Date(timeIntervalSince1970: 0))
        guard case .failure(let refusal) = ReplayPlanner.parse(step) else {
            return XCTFail("A kind this build does not know must refuse, not be dropped")
        }
        XCTAssertTrue(refusal.reason.contains("future_analysis"))
    }

    func testStrainWithoutAnEarlierDiskDetectionStepIsRefusedUpFront() {
        var record = SessionReplayRecord()
        record.record(kind: "strain",
                      parameters: ["reference_mode": "whole-scan", "basis_mode": "consensus"],
                      at: Date(timeIntervalSince1970: 0))
        let planned = ReplayPlanner.plan(record, frame: .detectorIdentity)
        XCTAssertEqual(planned.count, 1)
        guard case .failure(let refusal) = planned[0].result else {
            return XCTFail("A strain step with no Bragg vectors to consume cannot replay coherently")
        }
        XCTAssertTrue(refusal.reason.contains("disk-detection"))
    }

    func testStrainAfterADiskDetectionStepParses() {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: diskStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        record.record(kind: "strain",
                      parameters: ["reference_mode": "whole-scan", "basis_mode": "consensus"],
                      at: Date(timeIntervalSince1970: 1))
        let planned = ReplayPlanner.plan(record, frame: .detectorIdentity)
        XCTAssertEqual(planned.count, 2)
        guard case .success = planned[1].result else {
            return XCTFail("Order satisfied — the strain step must parse")
        }
    }

    func testThePlannerAppliesTheFrameGateSoCaptionAndExecutorAgree() {
        // The frame gate lives in the PLAN (not the executor) so its verdict
        // is pure and computable before the expensive reopen, and the
        // pre-click caption reads the same refusal the run would produce
        // (Gate A findings E1/B5).
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        record.record(kind: "dpc",
                      parameters: ["origin_reference": "global center"],
                      at: Date(timeIntervalSince1970: 1))
        let planned = ReplayPlanner.plan(
            record, frame: .detectorReduced(bin: 2, cropped: false))
        guard case .failure(let refusal) = planned[0].result else {
            return XCTFail("Binned-frame aperture pixels must refuse at plan time")
        }
        XCTAssertTrue(refusal.reason.contains("binned"))
        guard case .success = planned[1].result else {
            return XCTFail("DPC carries no detector numbers — the frame gate must not touch it")
        }
    }

    func testAnUnknownFrameRefusesDetectorFrameSteps() {
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        let planned = ReplayPlanner.plan(record, frame: .unknown)
        guard case .failure(let refusal) = planned[0].result else {
            return XCTFail("An unestablished frame must refuse, not be read as identity — that would be the guess the frame rule bans")
        }
        XCTAssertTrue(refusal.reason.contains("unknown"), "Reason was: \(refusal.reason)")
    }

    // MARK: - The detector-frame tag

    func testScanCropOnlySpecificationIsDetectorIdentity() {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        XCTAssertEqual(ReplayParameterFrame.of(spec), .detectorIdentity,
                       "A scan crop never touches the detector frame — the flagship rehearse case")
        XCTAssertNil(ReplayParameterFrame.detectorIdentity.refusalReason)
    }

    func testAbsentSpecificationIsDetectorIdentity() {
        XCTAssertEqual(ReplayParameterFrame.of(nil), .detectorIdentity,
                       "No recorded specification is the full-extent session the restore path already assumes")
    }

    func testDetectorBinAndCropAreReducedAndRefuse() {
        var binned = LoadSpecification()
        binned.detectorBin = 2
        XCTAssertEqual(ReplayParameterFrame.of(binned),
                       .detectorReduced(bin: 2, cropped: false))
        XCTAssertNotNil(ReplayParameterFrame.of(binned).refusalReason)

        var cropped = LoadSpecification()
        cropped.detectorCrop = AxisCrop(yOffset: 8, xOffset: 8, height: 48, width: 48)
        XCTAssertEqual(ReplayParameterFrame.of(cropped),
                       .detectorReduced(bin: 1, cropped: true))
    }

    func testMergingDifferentFramesIsMixedAndMixedRefuses() {
        let identity = ReplayParameterFrame.detectorIdentity
        let reduced = ReplayParameterFrame.detectorReduced(bin: 2, cropped: false)
        XCTAssertEqual(identity.merging(identity), .detectorIdentity)
        XCTAssertEqual(identity.merging(reduced), .mixed)
        XCTAssertEqual(ReplayParameterFrame.mixed.merging(.mixed), .mixed,
                       "Mixed never un-mixes")
        XCTAssertNotNil(ReplayParameterFrame.mixed.refusalReason)
    }
}
