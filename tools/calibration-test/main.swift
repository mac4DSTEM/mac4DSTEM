// Regression harness for H5Reader.pixelCalibration().
// Usage: harness <fixture.h5>  — expects the calibration written by make_fixture.c.
import Foundation

// Usage: harness <fixture.h5> [dataset-path]
let fixturePath = CommandLine.arguments[1]
let dsPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2] : "/test_root/datacube/data"

func check(_ cond: Bool, _ msg: @autoclosure () -> String) {
    if !cond { print("FAIL(\(fixturePath)): \(msg())"); exit(1) }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let reader = try H5Reader(path: fixturePath)
        let desc = try await reader.describe(path: dsPath)
        check(desc.shape == [2, 2, 4, 4], "shape \(desc.shape)")
        guard let cal = await reader.pixelCalibration() else {
            print("FAIL(\(fixturePath)): pixelCalibration() returned nil"); exit(1)
        }
        check(cal.qSize == 0.0125, "qSize \(String(describing: cal.qSize))")
        check(cal.qUnits == "A^-1", "qUnits \(String(describing: cal.qUnits))")
        check(cal.rSize == 2.5, "rSize \(String(describing: cal.rSize))")
        check(cal.rUnits == "A", "rUnits \(String(describing: cal.rUnits))")
        check(cal.qrFlip == true, "qrFlip \(String(describing: cal.qrFlip))")
        check(cal.qx0Mean == 31.5, "qx0Mean \(String(describing: cal.qx0Mean))")
        check(cal.qy0Mean == 32.25, "qy0Mean \(String(describing: cal.qy0Mean))")
        check(cal.ellipseA == 1.02, "ellipseA \(String(describing: cal.ellipseA))")
        check(cal.ellipseB == 0.98, "ellipseB \(String(describing: cal.ellipseB))")
        check(cal.ellipseTheta == 0.35, "ellipseTheta \(String(describing: cal.ellipseTheta))")
        print("PASS: \(fixturePath)")
    } catch {
        print("FAIL(\(fixturePath)): \(error)"); exit(1)
    }
    sem.signal()
}
sem.wait()
