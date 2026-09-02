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

    // MARK: - ACOM material resolution (Gate D 2026-09-02, crystal replay)
    //
    // The promote log read "C FCC, a = 4.08 Å" against a Z=79 default. The
    // diagnosis: the recorded id was `custom_cubic_fcc_z6` because the
    // rehearsal ran with carbon selected; replay cannot substitute Z. The
    // live residual it exposed: the id omits a₀, so a drifted lattice
    // constant replayed silently. These pin both halves.

    private func session(z: Int, a: Double, imported: Set<String> = []) -> ReplayStepPlan.ACOMReplayPlan.SessionMaterials {
        .init(importedIDs: imported, customStructure: .fcc, customLatticeA: a, customZ: z)
    }

    private func customPlan(id: String, latticeA: Double?) -> ReplayStepPlan.ACOMReplayPlan {
        .init(materialID: id, latticeA: latticeA, scaleInvAngstromPerPixel: 0.0125,
              scope: .fullScan, quality: .balanced)
    }

    func testCustomCubicRecordedIDEmbedsZButNotA() {
        let carbon = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 6)
        let gold = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 79)
        let carbonOtherA = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 3.57, atomicNumber: 6)
        XCTAssertNotEqual(carbon.id, gold.id, "Z is part of the id: replay cannot swap the element")
        XCTAssertEqual(carbon.id, carbonOtherA.id, "a₀ is NOT part of the id — the reason lattice_a is recorded")
        XCTAssertTrue(carbon.displayName.hasPrefix("C "), carbon.displayName)
    }

    func testCustomCubicReplayRefusesADifferentElement() {
        let goldID = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 79).id
        let plan = customPlan(id: goldID, latticeA: 4.08)
        guard case .unavailable(let reason) = plan.resolveMaterial(in: session(z: 6, a: 4.08)) else {
            return XCTFail("A z79 recipe must not run against a carbon session")
        }
        XCTAssertTrue(reason.contains(goldID), reason)
    }

    func testCustomCubicReplayResolvesTheRecordedElementAndLattice() {
        let carbonID = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 6).id
        let plan = customPlan(id: carbonID, latticeA: 4.08)
        XCTAssertEqual(plan.resolveMaterial(in: session(z: 6, a: 4.08)), .customCubic)
    }

    func testCustomCubicReplayRefusesADriftedLatticeConstant() {
        let carbonID = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 6).id
        let plan = customPlan(id: carbonID, latticeA: 4.08)
        guard case .unavailable(let reason) = plan.resolveMaterial(in: session(z: 6, a: 3.57)) else {
            return XCTFail("Same id, different a₀ — the silent path this gate closes")
        }
        XCTAssertTrue(reason.contains("4.08") && reason.contains("3.57"), reason)
    }

    func testCustomCubicReplayRefusesARecordWithoutLatticeConstant() {
        let carbonID = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 6).id
        let plan = customPlan(id: carbonID, latticeA: nil)
        guard case .unavailable(let reason) = plan.resolveMaterial(in: session(z: 6, a: 4.08)) else {
            return XCTFail("A pre-lattice_a custom record cannot prove its a₀")
        }
        XCTAssertTrue(reason.contains("lattice constant"), reason)
    }

    func testCustomCubicReplayRefusesANearMissLatticeConstant() {
        // 4.10 vs 4.08 is a different crystal (0.5 %); a tolerance loosened
        // to 1e-1 would let it through while the 4.08-vs-3.57 test stays green.
        let carbonID = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 6).id
        let plan = customPlan(id: carbonID, latticeA: 4.08)
        guard case .unavailable = plan.resolveMaterial(in: session(z: 6, a: 4.10)) else {
            return XCTFail("A 0.5 % lattice drift must refuse")
        }
        XCTAssertEqual(plan.resolveMaterial(in: session(z: 6, a: 4.08 * (1 + 1e-9))), .customCubic,
                       "Float round-trip noise is not a drift")
    }

    func testLibraryAndImportedIDsNeedNoLatticeConstant() {
        XCTAssertEqual(customPlan(id: "au_fcc", latticeA: nil).resolveMaterial(in: session(z: 6, a: 1)),
                       .library("au_fcc"))
        // Imported ids are `imported_<file stem>` (CIFImport); membership only.
        XCTAssertEqual(customPlan(id: "imported_ws2", latticeA: nil).resolveMaterial(in: session(z: 6, a: 1, imported: ["imported_ws2"])),
                       .imported("imported_ws2"))
    }

    func testACOMParsesAndRefusesLatticeA() throws {
        var step = acomStep
        step.parameters["lattice_a"] = "4.08"
        guard case .acom(let plan) = try ReplayPlanner.parse(step).get() else { return XCTFail() }
        XCTAssertEqual(plan.latticeA, 4.08)
        for bad in ["nan", "-1", "0", "abc"] {
            step.parameters["lattice_a"] = bad
            guard case .failure = ReplayPlanner.parse(step) else {
                return XCTFail("A present but unusable lattice_a (\(bad)) is a refusal, not nil")
            }
        }
    }

    func testRecordSiteWritesLatticeAOnlyForCustomModelsAndItRoundTrips() throws {
        let custom = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 6)
        let written = ReplayStepPlan.ACOMReplayPlan.recordedParameters(
            model: custom, scale: 0.0125, backend: "CPU", scope: .fullScan, quality: .balanced)
        XCTAssertEqual(written["lattice_a"], "4.08")
        XCTAssertEqual(written["material"], custom.id)
        let step = SessionReplayRecord.Step(kind: "acom", parameters: written, recorded: Date(timeIntervalSince1970: 0))
        guard case .acom(let plan) = try ReplayPlanner.parse(step).get() else { return XCTFail() }
        XCTAssertEqual(plan.resolveMaterial(in: session(z: 6, a: 4.08)), .customCubic,
                       "What the record site writes, the applier resolves")

        let library = try XCTUnwrap(CrystalModelLibrary.model(id: "au_fcc"))
        let libraryWritten = ReplayStepPlan.ACOMReplayPlan.recordedParameters(
            model: library, scale: 0.0125, backend: "CPU", scope: .fullScan, quality: .balanced)
        XCTAssertNil(libraryWritten["lattice_a"], "Library models are resolved by id alone")
    }

    func testLatticeAIsFrameInvariantThroughABinnedExport() throws {
        // Missing from the role registry, the key would refuse the whole
        // recipe out of a reduced-file export (refuter finding, 2026-09-02).
        let step = SessionReplayRecord.Step(
            kind: "acom",
            parameters: ["material": "custom_cubic_fcc_z6", "lattice_a": "4.08",
                         "scale_inv_angstrom_per_pixel": "0.02", "matching_backend": "CPU",
                         "scope": "fullScan", "quality": "balanced"],
            recorded: Date(timeIntervalSince1970: 0))
        let mapped = try ReplayRecordFrameMap.map(step, through: .viewToExport(bin: 2)).get()
        XCTAssertEqual(mapped.parameters["lattice_a"], "4.08")
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

    func testThePlannerReReferencesABinnedFrameSoCaptionAndExecutorAgree() {
        // The frame mapping lives in the PLAN (not the executor) so its
        // verdict is pure and computable before the expensive reopen, and the
        // pre-click caption reads the same mapped values the run would use
        // (Gate A findings E1/B5; mapping since v2 S10). Hand answers, b = 2:
        // a position un-bins about the pixel grid ((x+0.5)·2−0.5), a radius
        // doubles.
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        record.record(kind: "dpc",
                      parameters: ["origin_reference": "global center"],
                      at: Date(timeIntervalSince1970: 1))
        let planned = ReplayPlanner.plan(
            record, frame: .detectorReduced(bin: 2, crop: nil))
        guard case .success(let plan) = planned[0].result else {
            return XCTFail("A binned-frame aperture must re-reference, not refuse: \(planned[0].result)")
        }
        XCTAssertEqual(plan, .virtualDetector(
            shape: .annulus,
            aperture: Aperture(centerX: 63.5, centerY: 60.5, inner: 6.0, outer: 18.0)
        ), "center_x 31.5 → (31.5+0.5)·2−0.5 = 63.5; radii double — the exact inverse of the load-time re-reference")
        guard case .success = planned[1].result else {
            return XCTFail("DPC carries no detector numbers — the mapping must not touch it")
        }
    }

    func testACroppedAndBinnedFrameReReferencesPositionsWithTheOffset() {
        // Offsets come back AFTER un-binning — `apply` shifts then bins, so
        // the inverse un-bins then shifts. b = 2, crop offset (x 8, y 4):
        // center_x 31.5 → 63.5 + 8 = 71.5; center_y 30.0 → 60.5 + 4 = 64.5;
        // radii see the bin, never the offset.
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        let crop = AxisCrop(yOffset: 4, xOffset: 8, height: 64, width: 64)
        let planned = ReplayPlanner.plan(
            record, frame: .detectorReduced(bin: 2, crop: crop))
        guard case .success(let plan) = planned[0].result else {
            return XCTFail("A mappable cropped+binned step must plan: \(planned[0].result)")
        }
        XCTAssertEqual(plan, .virtualDetector(
            shape: .annulus,
            aperture: Aperture(centerX: 71.5, centerY: 64.5, inner: 6.0, outer: 18.0)
        ))
    }

    func testMixedFramesStillRefuseDetectorFrameSteps() {
        // `.mixed` has no single transform, so the S6 refusal stands
        // unchanged — the caption and the executor read the same verdict.
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        let planned = ReplayPlanner.plan(record, frame: .mixed)
        guard case .failure(let refusal) = planned[0].result else {
            return XCTFail("Two frames in one record cannot map — refusing is the only honest answer")
        }
        XCTAssertTrue(refusal.reason.contains("two different detector frames"))
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

    func testDetectorBinAndCropAreReducedAndCarryTheirTransform() {
        var binned = LoadSpecification()
        binned.detectorBin = 2
        XCTAssertEqual(ReplayParameterFrame.of(binned),
                       .detectorReduced(bin: 2, crop: nil))
        XCTAssertNil(ReplayParameterFrame.of(binned).refusalReason,
                     "Since S10 a reduced frame maps instead of refusing wholesale")
        XCTAssertEqual(ReplayParameterFrame.of(binned).sourceTransform,
                       .viewToSource(bin: 2, xOffset: 0, yOffset: 0))

        var cropped = LoadSpecification()
        let crop = AxisCrop(yOffset: 8, xOffset: 16, height: 48, width: 48)
        cropped.detectorCrop = crop
        XCTAssertEqual(ReplayParameterFrame.of(cropped),
                       .detectorReduced(bin: 1, crop: crop))
        XCTAssertEqual(ReplayParameterFrame.of(cropped).sourceTransform,
                       .viewToSource(bin: 1, xOffset: 16, yOffset: 8))
    }

    func testMergingDifferentFramesIsMixedAndMixedRefuses() {
        let identity = ReplayParameterFrame.detectorIdentity
        let reduced = ReplayParameterFrame.detectorReduced(bin: 2, crop: nil)
        XCTAssertEqual(identity.merging(identity), .detectorIdentity)
        XCTAssertEqual(identity.merging(reduced), .mixed)
        XCTAssertEqual(ReplayParameterFrame.mixed.merging(.mixed), .mixed,
                       "Mixed never un-mixes")
        XCTAssertNotNil(ReplayParameterFrame.mixed.refusalReason)
    }

    func testTwoSameBinCropsAtDifferentOffsetsAreDifferentFrames() {
        // The trap the payload widening exists to close (v2 S10): under S6's
        // `cropped: Bool` these two frames compared EQUAL, so merging kept one
        // frame — harmless while every reduced frame refused, fabrication the
        // moment mapping landed, because every position would map with the
        // wrong offset.
        let cropA = ReplayParameterFrame.detectorReduced(
            bin: 2, crop: AxisCrop(yOffset: 0, xOffset: 0, height: 48, width: 48))
        let cropB = ReplayParameterFrame.detectorReduced(
            bin: 2, crop: AxisCrop(yOffset: 8, xOffset: 8, height: 48, width: 48))
        XCTAssertNotEqual(cropA, cropB)
        XCTAssertEqual(cropA.merging(cropB), .mixed,
                       "Same bin, different offsets — one transform cannot serve both")
    }

    // MARK: - Frame re-referencing (v2 S10)

    func testRoundTripThroughBinnedCoordinateIsExact() {
        for bin in [1, 2, 4, 8] {
            for value: Float in [-0.5, 0, 17.25, 31.5, 255.5] {
                let there = CalibrationReReference.binnedCoordinate(value, bin: bin)
                XCTAssertEqual(CalibrationReReference.sourceCoordinate(there, bin: bin),
                               value, accuracy: 1e-4,
                               "sourceCoordinate must be the exact inverse at bin \(bin)")
            }
        }
    }

    func testDiskDetectionLengthsAndIntsMapAndInvariantsHold() throws {
        let mapped = try ReplayRecordFrameMap.map(
            diskStep, through: .viewToSource(bin: 2, xOffset: 8, yOffset: 4)
        ).get()
        XCTAssertEqual(mapped.parameters["sigma_cc"], String(Float(5.0)),
                       "A smoothing sigma is a length: ×bin, never the offset")
        XCTAssertEqual(mapped.parameters["min_peak_spacing"], String(Float(20.0)))
        XCTAssertEqual(mapped.parameters["edge_boundary"], "8",
                       "An integer length ×bin stays exact")
        XCTAssertEqual(mapped.parameters["corr_power"], "1.0",
                       "An exponent is dimensionless — untouched, byte-identical")
        XCTAssertEqual(mapped.parameters["min_relative_intensity"], "0.005",
                       "A relative threshold is frame-free")
        XCTAssertEqual(mapped.parameters["min_absolute_intensity"], "0.0",
                       "Zero is invariant — only a NONZERO absolute threshold has no exact image")
    }

    func testANonzeroAbsoluteIntensityThresholdRefusesByName() {
        var step = diskStep
        step.parameters["min_absolute_intensity"] = "12.5"
        guard case .failure(let refusal) = ReplayRecordFrameMap.map(
            step, through: .viewToSource(bin: 2, xOffset: 0, yOffset: 0)
        ) else {
            return XCTFail("The correlation is not intensity-normalized (cc = m·|m|^(p−1)); an absolute threshold tuned on one frame has no exact value in another")
        }
        XCTAssertTrue(refusal.reason.contains("min_absolute_intensity"),
                      "Reason was: \(refusal.reason)")
    }

    func testAnUnclassifiedKeyRefusesRatherThanPassingThrough() {
        var step = diskStep
        step.parameters["future_knob"] = "7"
        guard case .failure(let refusal) = ReplayRecordFrameMap.map(
            step, through: .viewToSource(bin: 2, xOffset: 0, yOffset: 0)
        ) else {
            return XCTFail("An unclassified number carried across frames is a fabrication waiting for a reader")
        }
        XCTAssertTrue(refusal.reason.contains("future_knob"))
    }

    func testStrainGVectorsMapAsDisplacementsWithoutTheOffset() throws {
        let step = SessionReplayRecord.Step(
            kind: "strain",
            parameters: ["reference_mode": "whole-scan", "basis_mode": "manual",
                         "resolved_g1_x": "-7.25", "resolved_g1_y": "12.5",
                         "resolved_g2_x": "10.0", "resolved_g2_y": "3.5"],
            recorded: Date(timeIntervalSince1970: 0))
        let mapped = try ReplayRecordFrameMap.map(
            step, through: .viewToSource(bin: 2, xOffset: 8, yOffset: 4)
        ).get()
        XCTAssertEqual(mapped.parameters["resolved_g1_x"], String(Float(-14.5)),
                       "A g-vector is a DIFFERENCE of positions: the offset cancels, the bin does not")
        XCTAssertEqual(mapped.parameters["resolved_g1_y"], String(Float(25.0)))
        XCTAssertEqual(mapped.parameters["resolved_g2_x"], String(Float(20.0)))
    }

    func testACOMScaleMapsAsAPerPixelSamplingInterval() throws {
        let step = SessionReplayRecord.Step(
            kind: "acom",
            parameters: ["material": "silicon", "scale_inv_angstrom_per_pixel": "0.02",
                         "matching_backend": "accelerate",
                         "scope": "fullScan", "quality": "balanced"],
            recorded: Date(timeIntervalSince1970: 0))
        let mapped = try ReplayRecordFrameMap.map(
            step, through: .viewToSource(bin: 2, xOffset: 0, yOffset: 0)
        ).get()
        XCTAssertEqual(mapped.parameters["scale_inv_angstrom_per_pixel"],
                       String(0.02 / 2),
                       "A source pixel spans HALF the reciprocal space of a ×2-binned one")
    }

    func testMapForExportBinsForwardAndDropsWholeRecipeOnAnInexactInt() {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: diskStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        // edge_boundary 4 ÷ 2 = 2 — exact, the recipe carries.
        guard case .success(let mapped) = ReplayRecordFrameMap.mapForExport(
            record, exportBin: 2
        ) else {
            return XCTFail("An exactly divisible recipe must carry")
        }
        XCTAssertEqual(mapped.steps[0].parameters["edge_boundary"], "2")
        XCTAssertEqual(mapped.steps[0].parameters["sigma_cc"], String(Float(1.25)),
                       "Forward = ÷bin for lengths")

        var inexact = record
        inexact.steps[0].parameters["edge_boundary"] = "3"
        guard case .failure(let refusal) = ReplayRecordFrameMap.mapForExport(
            inexact, exportBin: 2
        ) else {
            return XCTFail("3 px has no exact value at ÷2 — the whole recipe drops (coherent pipeline or nothing)")
        }
        XCTAssertTrue(refusal.reason.contains("edge_boundary"), "Reason was: \(refusal.reason)")
    }

    func testMapForExportBinsPositionsWithTheHalfPixel() throws {
        // The Gate B mutation that survived the first suite (S10 finding 3):
        // `.viewToExport` positions were exercised by NO test — a naive x/b
        // (biased (b−1)/2b px) passed everything, because the export-map
        // tests used only lengths and the fixture's recipe is pre-mapped.
        // Asymmetric center so an x/y swap cannot hide either.
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        guard case .success(let mapped) = ReplayRecordFrameMap.mapForExport(
            record, exportBin: 2
        ) else {
            return XCTFail("A virtual-detector step maps under an export bin")
        }
        XCTAssertEqual(mapped.steps[0].parameters["center_x"], String(Float(15.5)),
                       "(31.5+0.5)/2−0.5 — the naive 31.5/2 = 15.75 is the classic biased answer")
        XCTAssertEqual(mapped.steps[0].parameters["center_y"], String(Float(14.75)))
        XCTAssertEqual(mapped.steps[0].parameters["inner"], String(Float(1.5)))
        XCTAssertEqual(mapped.steps[0].parameters["outer"], String(Float(4.5)))
    }

    // MARK: - The export recipe decision (v2 S10, Gate B finding 1)

    func testExportableRecipeRefusesARecordWhoseFrameIsNotTheCurrentViews() {
        // The promoted-session shape: the recipe keeps its rehearsal frame
        // while the view is full extent. Mapping it through the current
        // view's bin would stamp positions in a frame the file is not in.
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        let (carried, omission) = AppState.exportableRecipe(
            record: record,
            recordedFrame: .detectorReduced(bin: 2, crop: nil),
            currentSpecification: LoadSpecification(),
            exportBin: 1)
        XCTAssertNil(carried, "A cross-frame recipe must not be stamped")
        XCTAssertTrue(omission?.contains("different detector frame") == true,
                      "Reason was: \(omission ?? "nil")")
    }

    func testExportableRecipeWithAnUnknownFrameRefuses() {
        var record = SessionReplayRecord()
        record.record(kind: "dpc", parameters: ["origin_reference": "global center"],
                      at: Date(timeIntervalSince1970: 0))
        let (carried, omission) = AppState.exportableRecipe(
            record: record, recordedFrame: nil,
            currentSpecification: LoadSpecification(), exportBin: 1)
        XCTAssertNil(carried,
                     "A nil frame is unknown, and unknown never maps — the guess the frame rule bans")
        XCTAssertNotNil(omission)
    }

    func testExportableRecipeCarriesAndMapsWhenFramesMatch() throws {
        // The ordinary rehearse-then-export flow: recorded on THIS reduced
        // view, exported with a further bin — the recipe carries, mapped.
        var spec = LoadSpecification()
        spec.detectorBin = 2
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: virtualDetectorStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        let (carried, omission) = AppState.exportableRecipe(
            record: record,
            recordedFrame: .detectorReduced(bin: 2, crop: nil),
            currentSpecification: spec,
            exportBin: 2)
        XCTAssertNil(omission)
        XCTAssertEqual(carried?.steps[0].parameters["center_x"], String(Float(15.5)))
    }

    func testExportableRecipeWithNoRecordCarriesNothingSilently() {
        let (carried, omission) = AppState.exportableRecipe(
            record: nil, recordedFrame: nil,
            currentSpecification: LoadSpecification(), exportBin: 2)
        XCTAssertNil(carried)
        XCTAssertNil(omission, "No recipe is absence, not a refusal — nothing to explain")
    }

    func testMapForExportAtBinOneIsTheIdentity() {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: diskStep.parameters,
                      at: Date(timeIntervalSince1970: 0))
        guard case .success(let mapped) = ReplayRecordFrameMap.mapForExport(
            record, exportBin: 1
        ) else {
            return XCTFail("Bin 1 must carry the recipe")
        }
        XCTAssertEqual(mapped, record,
                       "No export bin, no rewrite — byte-identical steps, the colleague-handoff case")
    }
}
