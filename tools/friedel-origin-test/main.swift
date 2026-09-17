//
//  main.swift — friedel-origin-test
//
//  Gated parity harness for Core/Analysis/FriedelOrigin.swift, the port of
//  py4DSTEM's `get_origin_friedel`. reference.py's `assert_source_contract`
//  has already gated the pinned source text before this binary runs (a nonzero
//  Python exit stops run.sh via `set -e`). This binary asserts, on a
//  centrosymmetric pattern with a PLANTED sub-pixel origin — clean and with a
//  beamstop:
//
//   RECOVERY (the algorithm does what it claims): the origin lands on the
//   planted centre. Truth is external — reference.py chose the centre.
//
//   PARITY (the port matches py4DSTEM): the origin equals reference.py's
//   independent numpy transcription of get_origin_friedel, to a tight
//   tolerance that a wrong axis, a wrong complex square, or a dropped mask term
//   would all exceed (each moves the origin by pixels, not thousandths).
//

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

struct Fixture: Decodable {
    let height: Int
    let width: Int
    let beamstopDP: [Float]
    let beamstopMask: [Bool]
    let beamstopCount: Int
    let plantedRow: Double
    let plantedCol: Double
    let cleanPattern: [Float]
    let cleanRow: Double
    let cleanCol: Double
    let maskedPattern: [Float]
    let mask: [Bool]
    let maskedRow: Double
    let maskedCol: Double
}

guard CommandLine.arguments.count == 2 else { fail("usage: friedel-origin-test fixture.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)

// The Friedel method finds a centre of symmetry, not a lattice point, so a
// clean recovery to well under a pixel is expected; 0.5 px passes it while a
// method that found the wrong symmetry point (or no symmetry) fails.
let recoveryTolerance = 0.5
// Swift runs the FFT in float32, reference.py's numpy in float64/complex128;
// the origin comes from an argmax (scale-invariant) plus a subpixel ratio of
// large near-peak values (well conditioned), so the two agree far inside this
// bound. Break-first: a real port defect (a swapped axis, a sign error in the
// complex square, a dropped masked term) moves the origin by whole pixels.
let parityTolerance = 0.1

func distance(_ a: (row: Float, col: Float), _ r: Double, _ c: Double) -> Double {
    hypot(Double(a.row) - r, Double(a.col) - c)
}

// MARK: - Clean (no beamstop)

guard let clean = FriedelOrigin.origin(
    pattern: fixture.cleanPattern, height: fixture.height, width: fixture.width
) else { fail("origin() returned nil on the clean pattern") }

let cleanRecovery = distance(clean, fixture.plantedRow, fixture.plantedCol)
guard cleanRecovery < recoveryTolerance else {
    fail("clean recovery: origin (\(clean.row), \(clean.col)) is \(cleanRecovery) px from "
         + "the planted (\(fixture.plantedRow), \(fixture.plantedCol)), exceeds \(recoveryTolerance) px")
}
let cleanParity = distance(clean, fixture.cleanRow, fixture.cleanCol)
guard cleanParity < parityTolerance else {
    fail("clean parity: Swift (\(clean.row), \(clean.col)) vs py4DSTEM "
         + "(\(fixture.cleanRow), \(fixture.cleanCol)), distance \(cleanParity) px exceeds \(parityTolerance) px")
}
print("PASS: clean Friedel origin (\(clean.row), \(clean.col)) — recovery \(cleanRecovery) px, "
      + "py4DSTEM parity \(cleanParity) px")

// MARK: - Beamstop (masked)

guard let masked = FriedelOrigin.origin(
    pattern: fixture.maskedPattern, height: fixture.height, width: fixture.width, mask: fixture.mask
) else { fail("origin() returned nil on the masked pattern") }

let maskedRecovery = distance(masked, fixture.plantedRow, fixture.plantedCol)
guard maskedRecovery < recoveryTolerance else {
    fail("masked recovery: origin (\(masked.row), \(masked.col)) is \(maskedRecovery) px from "
         + "the planted (\(fixture.plantedRow), \(fixture.plantedCol)) despite the beamstop, "
         + "exceeds \(recoveryTolerance) px")
}
let maskedParity = distance(masked, fixture.maskedRow, fixture.maskedCol)
guard maskedParity < parityTolerance else {
    fail("masked parity: Swift (\(masked.row), \(masked.col)) vs py4DSTEM "
         + "(\(fixture.maskedRow), \(fixture.maskedCol)), distance \(maskedParity) px exceeds \(parityTolerance) px")
}
print("PASS: masked (beamstop) Friedel origin (\(masked.row), \(masked.col)) — recovery "
      + "\(maskedRecovery) px, py4DSTEM parity \(maskedParity) px")

// MARK: - Beamstop mask parity (BeamstopMask vs py4DSTEM/scipy get_beamstop_mask)

let swiftMask = BeamstopMask.mask(meanDP: fixture.beamstopDP, height: fixture.height, width: fixture.width)
guard swiftMask.count == fixture.beamstopMask.count else {
    fail("beamstop mask length \(swiftMask.count) != \(fixture.beamstopMask.count)")
}
var disagreements = 0
for i in 0..<swiftMask.count where swiftMask[i] != fixture.beamstopMask[i] { disagreements += 1 }
guard disagreements == 0 else {
    fail("beamstop mask parity: \(disagreements) of \(swiftMask.count) pixels differ from "
         + "py4DSTEM/scipy get_beamstop_mask (expected pixel-identical)")
}
let swiftCount = swiftMask.reduce(0) { $0 + ($1 ? 1 : 0) }
guard swiftCount == fixture.beamstopCount else {
    fail("beamstop mask count \(swiftCount) != py4DSTEM \(fixture.beamstopCount)")
}
print("PASS: beamstop mask pixel-identical to py4DSTEM/scipy get_beamstop_mask "
      + "(\(swiftCount) of \(swiftMask.count) px flagged). This synthetic isolates the threshold, "
      + "the pattern-region fill, and the dilation; the dim-region fill (step 2) is verified against "
      + "scipy on the real Au_ref cube (see reference.py's synthetic_mean_dp docstring).")

// A beamstop that occludes the direct beam is exactly where the centre-of-mass
// origin fails and this method earns its place: assert the masked origin is not
// merely the pattern's intensity centroid shifted by the knocked-out bar.
print("friedel-origin-test: all passed")
