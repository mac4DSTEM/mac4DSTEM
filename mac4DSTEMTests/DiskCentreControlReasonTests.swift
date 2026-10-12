//
//  DiskCentreControlReasonTests.swift
//  Review audit 3.3 (2026-10-12): `DiskCentreControlReason` (UI/MapSettings.swift) is the one source of
//  the reason a disabled disk-centre control is off. Its `.help` tooltip and its VoiceOver value/label
//  both read it, so these tests pin the reason per gate and the order the Save button checks them in.
//

import XCTest
@testable import mac4DSTEM

final class DiskCentreControlReasonTests: XCTestCase {

    // MARK: Labelling toggle

    func testLabellingIsEnabledWithDatasetOnCurrentPattern() {
        XCTAssertNil(DiskCentreControlReason.labelling(hasDataset: true, onCurrentPattern: true))
    }

    func testLabellingWithoutDatasetGivesDatasetReason() {
        let reason = DiskCentreControlReason.labelling(hasDataset: false, onCurrentPattern: true)
        XCTAssertEqual(reason, "Open a dataset to label its disk centres.")
    }

    func testLabellingOffCurrentPatternGivesPatternReason() {
        let reason = DiskCentreControlReason.labelling(hasDataset: true, onCurrentPattern: false)
        XCTAssertEqual(
            reason,
            "Only available on the Current pattern display, where there is one scan position to label."
        )
    }

    func testLabellingDatasetReasonWinsOverPatternReason() {
        let reason = DiskCentreControlReason.labelling(hasDataset: false, onCurrentPattern: false)
        XCTAssertEqual(reason, "Open a dataset to label its disk centres.")
    }

    // MARK: Save to Sidecar

    func testSaveIsEnabledWhenNothingBlocksIt() {
        XCTAssertNil(DiskCentreControlReason.saveToSidecar(
            isEmpty: false, isBusy: false, holdsUnrestoredLabels: false, sidecarRefusal: nil
        ))
    }

    func testSaveWithNoLabelsGivesEmptyReason() {
        XCTAssertEqual(
            DiskCentreControlReason.saveToSidecar(
                isEmpty: true, isBusy: false, holdsUnrestoredLabels: false, sidecarRefusal: nil
            ),
            "There are no labelled centres to save yet."
        )
    }

    func testSaveWhileBusyGivesBusyReason() {
        XCTAssertEqual(
            DiskCentreControlReason.saveToSidecar(
                isEmpty: false, isBusy: true, holdsUnrestoredLabels: false, sidecarRefusal: nil
            ),
            "Unavailable while another task is running."
        )
    }

    func testSaveRefusedByGatePassesRefusalThrough() {
        XCTAssertEqual(
            DiskCentreControlReason.saveToSidecar(
                isEmpty: false, isBusy: false, holdsUnrestoredLabels: false, sidecarRefusal: "GATE REFUSAL"
            ),
            "GATE REFUSAL"
        )
    }

    func testSaveHoldingUnrestoredLabelsGivesHoldReason() {
        let reason = DiskCentreControlReason.saveToSidecar(
            isEmpty: false, isBusy: false, holdsUnrestoredLabels: true, sidecarRefusal: nil
        )
        XCTAssertEqual(
            reason,
            "The sidecar holds disk-centre labels this view did not restore; saving would replace them. Export Labels… saves these to a file."
        )
    }

    /// Order: holds-unrestored beats the gate refusal, which beats busy, which beats empty.
    func testSaveReasonOrderHoldsThenRefusalThenBusyThenEmpty() {
        let all = DiskCentreControlReason.saveToSidecar(
            isEmpty: true, isBusy: true, holdsUnrestoredLabels: true, sidecarRefusal: "GATE REFUSAL"
        )
        XCTAssertTrue(all?.hasPrefix("The sidecar holds") == true)

        let noHold = DiskCentreControlReason.saveToSidecar(
            isEmpty: true, isBusy: true, holdsUnrestoredLabels: false, sidecarRefusal: "GATE REFUSAL"
        )
        XCTAssertEqual(noHold, "GATE REFUSAL")

        let noRefusal = DiskCentreControlReason.saveToSidecar(
            isEmpty: true, isBusy: true, holdsUnrestoredLabels: false, sidecarRefusal: nil
        )
        XCTAssertEqual(noRefusal, "Unavailable while another task is running.")
    }

    func testEnabledSaveHelpIsTheDefaultSentence() {
        XCTAssertTrue(DiskCentreControlReason.saveToSidecarEnabledHelp.hasPrefix("Labels ride with"))
    }
}
