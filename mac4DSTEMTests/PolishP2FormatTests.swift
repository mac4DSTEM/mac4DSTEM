//
//  PolishP2FormatTests.swift
//  Polish lane P2: display formatters only (negative zero, provenance values and labels, one byte style).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class P2NegativeZeroTests: XCTestCase {
    func testNegativeZeroPrintsPlain() {
        XCTAssertEqual(RQRotationConvention.degreesText(-0.0), "0.0°")
        XCTAssertEqual(RQRotationConvention.degreesText(-0.04), "0.0°")
        XCTAssertEqual(RQRotationConvention.degreesText(0.04), "0.0°")
        XCTAssertEqual(RQRotationConvention.degreesText(-0.06), "-0.1°")
        XCTAssertEqual(RQRotationConvention.degreesText(-10.04), "-10.0°")
        XCTAssertEqual(RQRotationConvention.degreesText(-0.004, decimals: 2), "0.00°")
    }

    func testAppZeroRotationReadsZero() {
        // py4DSTEM(fromApp: 0) is -0.0; the Prepare row and status lines must not print it.
        XCTAssertEqual(RQRotationConvention.displayText(fromApp: 0), "0.0°")
        XCTAssertEqual(RQRotationConvention.displayText(fromApp: Float.pi), "-180.0°")
    }
}

final class P2ProvenanceTextTests: XCTestCase {
    func testLongDecimalsRoundForDisplay() {
        XCTAssertEqual(ProvenanceValueText.display("10.056641535141353"), "10.057")
        XCTAssertEqual(ProvenanceValueText.display("-663.6327265054541"), "-663.63")
    }

    func testShortAndNonNumericValuesUntouched() {
        for raw in ["3.92", "0.50", "42", "gradient-descent", "32,16,8", "1.23456789e-7", "123456789.123"] {
            XCTAssertEqual(ProvenanceValueText.display(raw), raw, raw)
        }
    }

    func testUnitWordsBecomeSymbols() {
        XCTAssertEqual(ProvenanceKeyLabel.text("probe_defocus_angstrom"), "Probe defocus (Å)")
        XCTAssertEqual(ProvenanceKeyLabel.text("cell_volume_angstrom_cubed"), "Cell volume (Å³)")
        XCTAssertEqual(ProvenanceKeyLabel.text("k_max_inv_angstrom"), "K max (Å⁻¹)")
        XCTAssertEqual(ProvenanceKeyLabel.text("dpc_magnitude_mrad"), "Dpc magnitude (mrad)")
        XCTAssertEqual(ProvenanceKeyLabel.text("analysis_mode"), "Analysis mode")
    }
}

final class P2ByteStyleTests: XCTestCase {
    func testSidebarAndSheetShareOneStyle() {
        let bytes = 15_840_000_000 + 12_345_678
        XCTAssertEqual(SystemMonitor.byteString(bytes), displayByteString(bytes))
        let small = 668_500_000
        XCTAssertEqual(SystemMonitor.byteString(small), displayByteString(small))
    }

    func testDecimalNotBinary() {
        // 1,000,000,000 bytes is 1 GB in the app's style; the binary one read "954 MB".
        XCTAssertFalse(SystemMonitor.byteString(1_000_000_000).contains("954"))
    }
}
