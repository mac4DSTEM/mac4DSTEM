import Foundation
// Driver: raw float32 cube [R0,R1,H,W] from file; mean in Double exactly as the writer; mask; per-pattern replace.
let a = CommandLine.arguments
let R0 = Int(a[2])!, R1 = Int(a[3])!, H = Int(a[4])!, W = Int(a[5])!, thresh = Double(a[6])!
let data = try! Data(contentsOf: URL(fileURLWithPath: a[1]))
var cube = [Float](repeating: 0, count: R0*R1*H*W)
_ = cube.withUnsafeMutableBytes { data.copyBytes(to: $0) }
let p = H*W
var sums = [Double](repeating: 0, count: p)
for n in 0..<(R0*R1) { for i in 0..<p { sums[i] += Double(cube[n*p+i]) } }
let mean = sums.map { Float($0 / Double(R0*R1)) }
let mask = HotPixelFilter.maskIndices(mean: mean, height: H, width: W, threshold: thresh)
for n in 0..<(R0*R1) { HotPixelFilter.replace(mask: mask, in: &cube, base: n*p, height: H, width: W) }
try! cube.withUnsafeBytes { Data($0) }.write(to: URL(fileURLWithPath: a[7]))
print(mask.map(String.init).joined(separator: " "))
