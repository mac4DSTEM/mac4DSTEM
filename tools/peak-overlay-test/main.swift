import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func close(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
    abs(actual - expected) <= tolerance
}

let fitted = CGSize(width: 640, height: 320)
let cases: [(String, Float, Float, CGPoint)] = [
    ("first_pixel", 0, 0, CGPoint(x: 5, y: 5)),
    ("interior_integer", 12, 8, CGPoint(x: 125, y: 85)),
    ("subpixel", 12.25, 8.5, CGPoint(x: 127.5, y: 90)),
    ("last_pixel", 63, 31, CGPoint(x: 635, y: 315)),
]

for (name, x, y, expected) in cases {
    let actual = PeakOverlayGeometry.center(
        x: x, y: y, patternWidth: 64, patternHeight: 32, box: fitted
    )
    guard close(actual.x, expected.x), close(actual.y, expected.y) else {
        fail("\(name) center \(actual), expected \(expected)")
    }
    print("PASS: \(name) center \(actual)")
}

let fittedRadius = PeakOverlayGeometry.radius(
    probeRadius: 3, patternWidth: 64, patternHeight: 32, box: fitted
)
guard close(fittedRadius, 30) else { fail("fitted radius \(fittedRadius), expected 30") }
print("PASS: non_square_fitted_radius \(fittedRadius)")

let squeezedRadius = PeakOverlayGeometry.radius(
    probeRadius: 3,
    patternWidth: 64,
    patternHeight: 32,
    box: CGSize(width: 640, height: 300)
)
guard close(squeezedRadius, 28.125) else {
    fail("squeezed radius \(squeezedRadius), expected 28.125")
}
print("PASS: squeezed_box_stays_circular radius \(squeezedRadius)")
print("peak-overlay-test: all passed")
