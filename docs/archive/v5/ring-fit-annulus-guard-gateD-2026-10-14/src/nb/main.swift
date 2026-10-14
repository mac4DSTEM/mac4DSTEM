// fixture search: usage nb size R eps thetaDeg noise seed f A  — Plant renderer of EllipseNoisyRingTests plus a neighbour ring at f*R, amplitude A
import Foundation
let a_ = CommandLine.arguments
let size = Int(a_[1])!, radius = Double(a_[2])!, eps = Double(a_[3])!, thetaDegrees = Double(a_[4])!, noise = Double(a_[5])!, seed = Int(a_[6])!, nf = Double(a_[7])!, nA = Double(a_[8])!
let b = 2 * radius / (2 + eps), a = b * (1 + eps)
let centerQX = Double(size) / 2 + 0.37 + 2.5 * sin(1.3 * Double(seed) + 0.2)
let centerQY = Double(size) / 2 - 0.41 + 2.5 * cos(1.9 * Double(seed) + 0.7)
let theta = thetaDegrees * .pi / 180
let sin2 = sin(theta) * sin(theta), cos2 = cos(theta) * cos(theta)
let A = sin2 / (b * b) + cos2 / (a * a), C = cos2 / (b * b) + sin2 / (a * a)
let B = 2 * (b * b - a * a) * sin(theta) * cos(theta) / (a * a * b * b)
let mean = (a + b) / 2
var state = UInt64(seed) &+ 1
func uniform() -> Double { state &+= 0x9E37_79B9_7F4A_7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return (Double((z ^ (z >> 31)) >> 11) + 0.5) / 9_007_199_254_740_992.0 }
var pixels = [Float](repeating: 0, count: size * size); var spare = 0.0
for qx in 0..<size { for qy in 0..<size {
    let dx = Double(qx) - centerQX, dy = Double(qy) - centerQY
    let rho = max(0, A * dx * dx + B * dx * dy + C * dy * dy).squareRoot()
    let d = (rho - 1) * mean, d2 = (rho - nf) * mean
    var value = exp(-(d * d) / 18) + nA * exp(-(d2 * d2) / 18)
    if noise > 0 { if (qx * size + qy) % 2 == 0 { let u1 = uniform(), u2 = uniform(); let r = (-2 * log(u1)).squareRoot(); value += noise * r * cos(2 * .pi * u2); spare = noise * r * sin(2 * .pi * u2) } else { value += spare } }
    pixels[qx * size + qy] = Float(value)
} }
let lo = b - 20, hi = a + 20
do {
    let f = try EllipseCalibration.fitBestAvailable(pattern: DiffractionPattern(qy: size, qx: size, pixels: pixels), centerQX: centerQX + 1.3, centerQY: centerQY - 0.9, innerRadius: lo, outerRadius: hi)
    print("size=\(size) R=\(radius) e=\(eps) t=\(thetaDegrees) n=\(noise) k=\(seed) f=\(nf) A=\(nA) model=\(f.model == .conic ? "conic" : "profile") meanR=\(String(format: "%.3f", (f.a + f.b) / 2)) dR=\(String(format: "%.4f", (f.a + f.b) / 2 / radius - 1)) dba=\(String(format: "%.5f", f.b / f.a - b / a)) annulus=[\(String(format: "%.1f", lo)),\(String(format: "%.1f", hi))] reason=\(f.profileFallbackReason ?? "-")")
} catch { print("size=\(size) R=\(radius) e=\(eps) t=\(thetaDegrees) n=\(noise) k=\(seed) f=\(nf) A=\(nA) THREW \(error)") }
