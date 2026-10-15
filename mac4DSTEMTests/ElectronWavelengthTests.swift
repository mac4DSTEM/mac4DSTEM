import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The DPC electron wavelength is DiffractoKit's `ElectronWavelength.angstroms(volts:)` (CODATA 2018), through
/// `DPC.electronWavelengthAngstrom(voltageKV:)`; `ParallaxPreprocessor.electronWavelengthAngstrom(energyEV:)` stays py4DSTEM's
/// rounded-constant form, because the Parallax code is a parity port (registration
/// `docs/registrations/diffractokit-wavelength-registration-2026-10-15.md`, W′1; item W closed on W4; kit item 12 of
/// `DiffractoKit/docs/consumers-0.0.3.md`). Tier 1: every literal below is the documented value, not read back from the Swift.
///
/// The documented BEFORE, for the record. DPC's form 12.2639 / sqrt(V (1 + 0.97845e-6 V)) gave 0.02507865865 A at 200 kV
/// (2.72e-5 relative below the kit; 80 kV -2.84e-5, 120 kV -2.80e-5, 300 kV -2.64e-5); Parallax's rounded-constant form gave
/// 0.02507933736 A at 200 kV (1.23e-7 below). The kit's 200 kV value is 0.025079340450548003 A.
/// Mutations they catch: the old DPC formula back in (the offsets read 0, the values miss by 6.8e-7 A); the kit's lambda in
/// the Parallax port (misses py4DSTEM's by 3.1e-9 A);
/// `voltageKV * 1_000` dropped or `* 100` (a 1000x or 10x wrong wavelength); the nil guard removed (NaN for a bad voltage).
@MainActor
final class ElectronWavelengthTests: XCTestCase {

    /// kV -> (kit lambda, the old DPC form's lambda, the old Parallax form's lambda), A. Each independently evaluated:
    /// the kit's lambda = hc / sqrt(eV (2 m0c^2 + eV)) from CODATA 2018 (h, c, e exact, m0 = 9.1093837015e-31 kg);
    /// the old forms from their own constants (DPC: 12.2639, 0.97845e-6; Parallax: 9.109383e-31, 1.602177e-19, 6.62607e-34).
    private let table: [(kV: Double, kit: Double, oldDPC: Double, oldParallax: Double)] = [
        (80,  0.04175716077283421,  0.04175597584404136,  0.04175715620292005),
        (120, 0.033492152726723734, 0.03349121655836176,  0.03349214889517896),
        (200, 0.025079340450548003, 0.02507865865059979,  0.025079337357037376),
        (300, 0.019687489006848795, 0.019686970075614534, 0.019687486388201916),
    ]

    /// The documented relative offsets of the old DPC form below the kit (consumer note item 12), three figures.
    private let documentedDPCOffsets: [Double: Double] = [80: -2.84e-5, 120: -2.80e-5, 200: -2.72e-5, 300: -2.64e-5]

    /// W′1, DPC entry point: the kit's lambda at four voltages, to 1e-15 A (4e-14 relative; the kit's own value at 200 kV).
    func testDPCWavelengthIsTheKitValueAtFourVoltages() throws {
        for row in table {
            let lambda = try XCTUnwrap(DPC.electronWavelengthAngstrom(voltageKV: row.kV))
            XCTAssertEqual(lambda, row.kit, accuracy: 1e-15, "\(row.kV) kV")
        }
    }

    /// W′1, Parallax entry point: py4DSTEM's own rounded-constant lambda (its parity harness pins it at 1e-12), not the kit's.
    func testParallaxWavelengthStaysPy4DSTEMsRoundedForm() {
        for row in table {
            let lambda = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: row.kV * 1_000)
            XCTAssertEqual(lambda, row.oldParallax, accuracy: 1e-15, "\(row.kV) kV")
        }
    }

    /// W′1, the offsets: the documented old DPC values sit 2.6e-5..2.8e-5 below the new function (the note's per-voltage
    /// figures to their three digits); the old Parallax values 1.1e-7..1.3e-7 below, -1.23e-7 at 200 kV.
    func testNewWavelengthSitsAboveTheOldFormsByTheDocumentedOffsets() throws {
        for row in table {
            let new = try XCTUnwrap(DPC.electronWavelengthAngstrom(voltageKV: row.kV))
            let dpcOffset = (row.oldDPC - new) / new
            XCTAssertEqual(dpcOffset, try XCTUnwrap(documentedDPCOffsets[row.kV]), accuracy: 6e-8, "DPC \(row.kV) kV")
            let parallaxOffset = (row.oldParallax - new) / new
            XCTAssertLessThan(parallaxOffset, -1.0e-7, "Parallax \(row.kV) kV")
            XCTAssertGreaterThan(parallaxOffset, -1.4e-7, "Parallax \(row.kV) kV")
            if row.kV == 200 { XCTAssertEqual(parallaxOffset, -1.23e-7, accuracy: 1e-9, "Parallax 200 kV: the note's -1.23e-7") }
        }
    }

    /// The DPC entry point keeps its nil for a voltage that is not positive and finite (the kit returns NaN there).
    func testDPCWavelengthIsNilForNonPositiveOrNonFiniteVoltage() {
        for bad in [0.0, -1.0, -200.0, .nan, .infinity, -.infinity] {
            XCTAssertNil(DPC.electronWavelengthAngstrom(voltageKV: bad), "\(bad) kV")
        }
    }

    /// W′2, one linear quantity: the calibration readout's mrad per pixel is 1000 lambda dq, so at 200 kV and 0.01 A^-1 per
    /// pixel it is 0.25079340450548003 (the old form read 0.2507865865), to Float's resolution.
    func testMilliradiansPerDetectorPixelFollowsTheKitWavelength() throws {
        let mrad = try XCTUnwrap(DPC.milliradiansPerDetectorPixel(voltageKV: 200, invAngstromPerPixel: 0.01))
        XCTAssertEqual(Double(mrad), 0.25079340450548003, accuracy: 2e-8)
        XCTAssertNil(DPC.milliradiansPerDetectorPixel(voltageKV: 0, invAngstromPerPixel: 0.01))
    }
}
