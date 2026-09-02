//
//  tools/two-spec-analysis-test — v2 S2 (docs/v2-release.md §8).
//
//  THE CLAIM UNDER TEST, and it is the release's first sentence: "an analysis
//  validated on a cropped, binned view re-runs unchanged on the full dataset".
//  This harness is the evidence for the word *unchanged*.
//
//  THE ARBITER IS THE FULL-EXTENT RUN, RESTRICTED TO THE OVERLAP — never a
//  cropped run compared against another cropped run. Two reduced views that
//  share a defect agree with each other perfectly; that comparison is a
//  self-consistency check wearing the costume of a parity test, and this repo
//  has shipped one before (docs/load-pipeline-plan.md, the L4 phantom control).
//  So: every expectation below is computed from the FULL-extent analysis, and
//  the reduced view is asked whether it reproduces it.
//
//  EACH CASE STATES WHICH INVARIANCE IT CLAIMS, because they are NOT the same
//  claim and lumping them together is how a weak one borrows the credibility of
//  a strong one:
//
//    SELECTION       (scan crop)      — a scan crop chooses which output pixels
//                                       exist. It cannot change one. Exact.
//    TRANSLATION     (detector crop)  — a detector crop moves the frame. A
//                                       detector-space value re-referenced by
//                                       the crop offset addresses the same
//                                       pixels. Exact, but ONLY where the
//                                       support lies inside the crop, which is
//                                       asserted, not assumed.
//    CONSERVATION    (detector bin)   — binning sums b*b pixels. Total
//                                       intensity over a bin-aligned region is
//                                       preserved. Exact (see WHY `==` below).
//    COMMUTATION     (metamorphic)    — crop-then-analyse equals
//                                       analyse-then-crop, over randomized
//                                       fixtures.
//
//  Detector-crop DISK DETECTION is the one case that is deliberately NOT exact,
//  and saying why is the point: correlation runs an FFT over the whole detector
//  grid, so cropping changes the transform size and the wrap-around. Its
//  invariance is weaker and stated as such at the case.
//
//  WHY `==` AND NOT A TOLERANCE — and it is THREE arguments, not one. The
//  original header gave only the first and implied it covered every `==` in the
//  file; Gate B (2026-08-19) pointed out that it does not.
//
//    1. THE SUM CASES (virtual imaging, binning). reference.py fills every
//       fixture with integers whose per-pattern totals stay under 2**24 — the
//       largest actually written is 178,802 — so a float32 sum of them is exact
//       in whatever order either side accumulates. Masks are exactly binary
//       (`fillRadial` writes 1), so no fractional weight breaks integrality.
//    2. CASE 2 (scan-crop disk detection) is a DETERMINISM argument, not an
//       integer one: the identical FFT over identical bytes returns identical
//       floats. Exactness here would hold for non-integer data too.
//    3. CASE 7 (calibration re-reference) is identical float expressions
//       evaluated on exactly-representable values.
//
//  A tolerance in any of the three would hide the one defect this harness exists
//  to catch: the right number of pixels reduced from the wrong place. Where
//  exactness genuinely does not hold (the FFT-under-detector-crop case), the
//  harness says so and bounds the error instead of quietly widening `==`.
//
//  WHAT THIS HARNESS DOES NOT PROVE. It drives H5Reader only — the reader whose
//  pushdown is `.full`. The four slicing readers are covered for READS by
//  tools/load-spec-test; nothing here re-checks them, and an analysis defect
//  specific to a sliced reader would not appear. It also runs on synthetic
//  cubes: it can show that a reduced view agrees with full extent, not that
//  either is physically right. That is tools/disk-correlation-parity's job.
//
//  AND ONE BLIND SPOT WORTH NAMING, found by Gate B: both sides of every
//  comparison call the same `VirtualDetector.makeMask`, so a change to the MASK
//  BOUNDARY convention (`r2 < rOut2` vs `<=`) cancels and passes here — as it
//  does in tools/virtual-detector-test. The app matches py4DSTEM today
//  (References/py4DSTEM-dev/py4DSTEM/datacube/virtualimage.py:636 uses strict
//  `<`), so this is a gap in coverage rather than a live defect, and it is the
//  irreducible limit of any self-comparison: shared code cancels. Closing it
//  needs one assertion pinning makeMask against an analytic mask. Filed in
//  docs/open-items.md.
//

import Foundation
import Metal

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

// MARK: - Harness plumbing

/// The measured translation-equivariance error of the origin measurement.
///
/// **MEASURED, NOT CHOSEN.** A run on 2026-08-19 (Apple M3, macOS 27) produced a
/// worst deviation of **0.6094227 px**, at shift (dy -2, dx -2), which the
/// kernel reported as (dy -1.39, dx -2.34).
///
/// **This is the COARSE-GRID item, not the un-iterated-CoM item, and an earlier
/// version of this comment conflated the two** because both are "about 0.6 px"
/// (Gate B, 2026-08-19). They are different quantities with different causes.
/// The discriminating experiment, run twice independently: make the coarse step
/// translation-equivariant by striding the block scan by 1 instead of by `bin`
/// (`OriginMeasure.metal:47,49`). P4's deviation collapses from 0.6094227 px to
/// **9.536743e-07 px** — float noise — which confirms the coarse grid as the
/// cause and rules out the un-iterated CoM as an independent contributor to
/// *this* number. The same experiment leaves the ABSOLUTE error (see
/// `originAbsoluteAccuracy`) unchanged at 0.337 px, which is how you can tell
/// they are two defects and not one.
///
/// 0.65 is that measurement plus a little headroom for cross-GPU float
/// differences — deliberately far below the coarse bin size of `round(r)` = 3 px,
/// which is the scale a genuine regression in the coarse step would move by. So
/// the bound is loose enough not to flake and tight enough that the defect
/// getting worse cannot hide inside it.
///
/// This number goes DOWN to zero when S13 lands a translation-equivariant coarse
/// step; it must never be raised to make a run pass. Raising it is the refusal
/// rule's "widening a gate", and the gate is the only reason this line exists.
let P4_KNOWN_BOUND: Float = 0.65

/// How far the measured beam centre may sit from the centre reference.py planted.
///
/// **MEASURED, NOT CHOSEN.** 2026-08-19, Apple M3 / macOS 27: worst deviation
/// **0.3367424 px** at scan position 0, where the kernel reported (y 15.337,
/// x 16.663) for a disk the fixture centred at (y 15, x 17). Same root cause as
/// P4 — the coarse grid in `Shaders/OriginMeasure.metal` is pinned to the
/// detector origin, so the CoM window is seeded off-centre.
///
/// 0.40 is that plus headroom, and deliberately well under 1 px: a constant-bias
/// regression of the kind this check exists for moves by a whole pixel or more.
/// Gate B's `+1.0f` experiment passed every other check in this file, and fails
/// this one by a factor of two and a half.
///
/// Goes DOWN when S13 lands an equivariant coarse step. Never up.
let ORIGIN_ABSOLUTE_BOUND: Float = 0.40

var failures: [String] = []
var checksRun = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    checksRun += 1
    if !condition { failures.append(message()) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

/// Largest absolute difference, or nil when the shapes disagree.
func maximumDifference(_ a: [Float], _ b: [Float]) -> Float? {
    guard a.count == b.count else { return nil }
    var worst: Float = 0
    for index in 0..<a.count {
        worst = max(worst, abs(a[index] - b[index]))
    }
    return worst
}

/// How two float arrays differ, for a failure message.
///
/// A named function rather than an interpolated `.map(String.init) ?? "..."`:
/// the interpolated form made the type checker give up entirely
/// ("failed to produce diagnostic for expression") on every check that used it,
/// which reads as a compiler bug and costs an hour to trace back to a string.
func differenceReport(_ a: [Float], _ b: [Float]) -> String {
    guard let worst = maximumDifference(a, b) else {
        return "shape mismatch, \(a.count) values vs \(b.count)"
    }
    return "worst |delta| \(worst)"
}

/// The sub-rectangle of a full-extent scan-indexed image that a scan crop keeps.
///
/// Written here with plain index arithmetic that shares no code with the crop
/// path under test — a harness that asked `LoadView` where the crop is would
/// agree with any consistent off-by-one in `LoadView`.
func scanSubRectangle(
    _ image: [Float], width: Int, crop: AxisCrop
) -> [Float] {
    var output: [Float] = []
    output.reserveCapacity(crop.height * crop.width)
    for y in crop.yRange {
        for x in crop.xRange {
            output.append(image[y * width + x])
        }
    }
    return output
}

// MARK: - The analyses, run through the app's own code

/// One virtual image over a view, through the production tiled path.
///
/// `maximumTileRows: 1` forces the multi-tile path on every view, including the
/// short ones. Without it a small view is a single tile and the cross-tile
/// assembly — the part that a crop offset can break — never runs.
func virtualImage(
    _ data: FourDArray, _ descriptor: DatasetDescriptor, _ shape: DetectorShape
) async throws -> FloatImage {
    try await VirtualDetector.tiledImage(
        data: data, descriptor: descriptor, shape: shape, maximumTileRows: 1
    )
}

/// Bragg peaks for one pattern, sorted into a comparable order.
///
/// Sorted by descending intensity then by position: detection returns peaks in
/// an order that depends on the maxima scan, and comparing two runs' *order*
/// would report a failure for a difference that carries no meaning.
func peaks(
    in pattern: [Float], detector: DiskDetector, params: DiskDetectionParams
) -> [BraggPeak] {
    detector.detect(pattern: pattern, params: params).sorted {
        if $0.intensity != $1.intensity { return $0.intensity > $1.intensity }
        if $0.y != $1.y { return $0.y < $1.y }
        return $0.x < $1.x
    }
}

func describe(_ peak: BraggPeak) -> String {
    String(format: "(y %.4f, x %.4f, I %.4f)", peak.y, peak.x, peak.intensity)
}

// MARK: - Main

@main struct TwoSpecAnalysisHarness {

    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            fail("usage: two-spec-analysis-test <fixture-directory>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])

        try await structuredCases(root: root)
        try await residentTileOffset(root: root)
        try await metamorphicProperties(root: root)
        try await originAbsoluteAccuracy(root: root)
        try originTranslationEquivariance()

        if failures.isEmpty {
            // The count is DATA-DEPENDENT, not a coverage invariant: a peak-count
            // mismatch takes extra branches in Case 2, so a failing run can report
            // MORE checks than a passing one (Gate B saw 221 under NC1 against 214
            // clean). Do not read this number as "N assertions are guaranteed to
            // run" — the anti-vacuity guards inside Case 6, `residentTileOffset`
            // and the bin-placement precondition are what enforce that, each for
            // its own case.
            print("two-spec-analysis-test: all passed (\(checksRun) checks)")
        } else {
            for message in failures.prefix(40) {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            }
            FileHandle.standardError.write(
                Data("two-spec-analysis-test: \(failures.count) failure(s) of \(checksRun) checks\n".utf8)
            )
            exit(1)
        }
    }

    // MARK: The structured two-spec cases

    static func structuredCases(root: URL) async throws {
        let reader = try H5Reader(path: root.appendingPathComponent("analysis.h5").path)
        let source = try await reader.discoverPrimaryDataset()
        guard source.shape == [6, 7, 32, 36] else {
            fail("analysis.h5 shape \(source.shape), expected [6, 7, 32, 36]")
        }

        // The virtual detector, defined once in SOURCE detector coordinates.
        // Every reduced view re-expresses this same physical detector in its own
        // frame; that re-expression is what "re-referenced coordinates" means
        // and it is the thing under test.
        let beamY: Float = 16, beamX: Float = 18
        let detectorRadius: Float = 8
        let sourceShape = DetectorShape.circle(
            centerX: beamX, centerY: beamY, radius: detectorRadius
        )

        // Support of that mask, in source detector pixels. Asserted rather than
        // eyeballed: the TRANSLATION invariance below is only true when the
        // whole support survives the crop, and a case that quietly violated its
        // own precondition would look like a defect in the app.
        let supportYRange = Int((beamY - detectorRadius).rounded(.down))
            ... Int((beamY + detectorRadius).rounded(.up))
        let supportXRange = Int((beamX - detectorRadius).rounded(.down))
            ... Int((beamX + detectorRadius).rounded(.up))

        let fullView = LoadView(fullExtentOf: source)
        let fullData = FourDArray(reader: reader, view: fullView)
        let fullImage = try await virtualImage(fullData, source, sourceShape)
        check(fullImage.width == 7 && fullImage.height == 6,
              "full-extent virtual image is \(fullImage.width)x\(fullImage.height), expected 7x6")

        // The full-extent detection, once, as the arbiter for the scan cases.
        guard let fullKernel = ProbeKernel.synthetic(radius: 3, qy: source.qy, qx: source.qx),
              let fullDetector = DiskDetector(kernel: fullKernel) else {
            fail("could not build the full-extent probe kernel")
        }
        var params = DiskDetectionParams()
        params.sigmaCC = 0
        params.subpixel = .poly
        // The Bragg disks are 250 counts against the beam's 900, so the
        // relative-intensity gate has to sit below that ratio or detection
        // returns the beam alone — which the sanity check below would catch,
        // but only after someone wondered why a crop case had nothing to compare.
        params.minRelativeIntensity = 0.1
        params.minPeakSpacing = 5
        params.edgeBoundary = 2
        params.maxNumPeaks = 8

        var fullPeaks: [[BraggPeak]] = []
        for ry in 0..<source.ry {
            for rx in 0..<source.rx {
                let pattern = try await fullData.pattern(ry: ry, rx: rx)
                fullPeaks.append(peaks(in: pattern.pixels, detector: fullDetector, params: params))
            }
        }
        check(fullPeaks.allSatisfy { $0.count >= 5 },
              "the fixture should present a beam plus four Bragg disks; full-extent counts were \(fullPeaks.map(\.count))")

        // ---- Case 1. Scan crop, virtual image. INVARIANCE: SELECTION -------
        // A scan crop chooses which scan positions are loaded. The virtual image
        // at a position is a reduction over that position's own pattern and
        // nothing else, so cropping cannot change a surviving value — only
        // remove others. Exact.
        let scanCrop = AxisCrop(yOffset: 2, xOffset: 1, height: 4, width: 5)
        do {
            let view = try LoadView(
                source: source, specification: LoadSpecification(scanCrop: scanCrop)
            )
            let data = FourDArray(reader: reader, view: view)
            let image = try await virtualImage(data, view.descriptor, sourceShape)
            let expected = scanSubRectangle(fullImage.pixels, width: source.rx, crop: scanCrop)
            check(image.pixels == expected,
                  "scan crop / virtual image: differs from the full-extent image's sub-rectangle "
                  + "(\(differenceReport(image.pixels, expected)))")
            check(image.width == scanCrop.width && image.height == scanCrop.height,
                  "scan crop / virtual image: \(image.width)x\(image.height), expected \(scanCrop.width)x\(scanCrop.height)")
        }

        // ---- Case 2. Scan crop, disk detection. INVARIANCE: SELECTION -----
        // Same argument, and stronger than it looks: the DETECTOR grid is
        // untouched by a scan crop, so the correlation FFT is the identical
        // transform on the identical pattern. Bit-exact, including the subpixel
        // refinement. Anything else means the crop fetched a different pattern.
        do {
            let view = try LoadView(
                source: source, specification: LoadSpecification(scanCrop: scanCrop)
            )
            let data = FourDArray(reader: reader, view: view)
            guard let kernel = ProbeKernel.synthetic(radius: 3, qy: view.descriptor.qy, qx: view.descriptor.qx),
                  let detector = DiskDetector(kernel: kernel) else {
                fail("scan crop: could not build the probe kernel")
            }
            for viewY in 0..<view.descriptor.ry {
                for viewX in 0..<view.descriptor.rx {
                    let pattern = try await data.pattern(ry: viewY, rx: viewX)
                    let found = peaks(in: pattern.pixels, detector: detector, params: params)
                    let sourceIndex = (viewY + scanCrop.yOffset) * source.rx + (viewX + scanCrop.xOffset)
                    let expected = fullPeaks[sourceIndex]
                    check(found.count == expected.count,
                          "scan crop / disk detection at view (\(viewY),\(viewX)): \(found.count) peaks, "
                          + "full extent found \(expected.count) at source (\(viewY + scanCrop.yOffset),\(viewX + scanCrop.xOffset))")
                    guard found.count == expected.count else { continue }
                    for (a, b) in zip(found, expected) where a.x != b.x || a.y != b.y || a.intensity != b.intensity {
                        check(false,
                              "scan crop / disk detection at view (\(viewY),\(viewX)): peak \(describe(a)) "
                              + "differs from the full-extent peak \(describe(b)) — a scan crop must not "
                              + "change a pattern, so this is a read offset, not a numerical difference")
                        break
                    }
                }
            }
        }

        // ---- Case 3. Detector crop, virtual image. INVARIANCE: TRANSLATION -
        // A detector crop moves the origin of the detector frame. The SAME
        // physical detector, re-expressed at (centre - offset), sums the same
        // source pixels — provided its whole support survives the crop, which is
        // asserted below rather than assumed. Exact.
        let detectorCrop = AxisCrop(yOffset: 4, xOffset: 6, height: 24, width: 26)
        do {
            check(detectorCrop.yRange.contains(supportYRange.lowerBound)
                  && detectorCrop.yRange.contains(supportYRange.upperBound)
                  && detectorCrop.xRange.contains(supportXRange.lowerBound)
                  && detectorCrop.xRange.contains(supportXRange.upperBound),
                  "detector crop case precondition: the mask support "
                  + "y\(supportYRange) x\(supportXRange) is not inside the crop "
                  + "y\(detectorCrop.yRange) x\(detectorCrop.xRange) — the TRANSLATION invariance "
                  + "does not apply and this case would be testing the wrong thing")

            let view = try LoadView(
                source: source, specification: LoadSpecification(detectorCrop: detectorCrop)
            )
            let data = FourDArray(reader: reader, view: view)
            // The re-reference: this is the arithmetic the app must agree with.
            let viewShape = DetectorShape.circle(
                centerX: beamX - Float(detectorCrop.xOffset),
                centerY: beamY - Float(detectorCrop.yOffset),
                radius: detectorRadius
            )
            let image = try await virtualImage(data, view.descriptor, viewShape)
            check(image.pixels == fullImage.pixels,
                  "detector crop / virtual image: differs from the full-extent image "
                  + "(\(differenceReport(image.pixels, fullImage.pixels))) "
                  + "— the mask support is entirely inside the crop, so the same pixels are summed")
        }

        // ---- Case 4. Detector bin, virtual image. INVARIANCE: CONSERVATION -
        // Binning sums b*b detector pixels into one. Over a BIN-ALIGNED region
        // the same source values are summed, only grouped differently, so the
        // total is preserved exactly — reference.py's integers make the float32
        // sum order-independent. A rectangle detector is used rather than a
        // circle precisely because a circle is not bin-aligned: its edge would
        // include a different pixel set after binning, and the case would be
        // testing rounding rather than conservation.
        do {
            let bin = 2
            // ASYMMETRIC IN BOTH AXES, and that is a correction rather than a
            // preference. The first version used y 4..<28 on a 32-row detector —
            // symmetric — and Gate B (2026-08-19) showed that a VERTICAL FLIP of
            // the binned output then passed all 201 checks: a mirrored diffraction
            // pattern mirrors every downstream detector-frame quantity (origin,
            // Bragg qy, strain sign, ACOM orientation). The x-region was already
            // asymmetric and did catch the x-flip. A region symmetric about the
            // axis it is meant to constrain cannot see a reflection in that axis.
            let region = (yMin: 4, yMax: 24, xMin: 6, xMax: 32)   // all divisible by 2
            let view = try LoadView(
                source: source, specification: LoadSpecification(detectorBin: bin)
            )
            let data = FourDArray(reader: reader, view: view)
            let binnedImage = try await virtualImage(data, view.descriptor, .rectangle(
                xMin: region.xMin / bin, xMax: region.xMax / bin,
                yMin: region.yMin / bin, yMax: region.yMax / bin
            ))
            let sourceImage = try await virtualImage(fullData, source, .rectangle(
                xMin: region.xMin, xMax: region.xMax, yMin: region.yMin, yMax: region.yMax
            ))
            check(binnedImage.pixels == sourceImage.pixels,
                  "detector bin / virtual image: total intensity over a bin-aligned region changed "
                  + "(\(differenceReport(binnedImage.pixels, sourceImage.pixels)))")

            // ---- PLACEMENT, which conservation on its own cannot check -------
            // A region total is invariant under ANY permutation of the binned
            // output, so the assertion above survives a flip, a transpose or a
            // rotation of the binned pattern — Gate B demonstrated exactly that.
            // This asks a strictly stronger question of individual bins: does
            // binned pixel (by, bx) hold the sum of source block
            // [by*b, (by+1)*b) x [bx*b, (bx+1)*b) — that one and no other?
            // Blocks are picked off-centre and at three corners, so no reflection
            // maps the chosen set onto itself.
            let binnedHeight = view.descriptor.qy, binnedWidth = view.descriptor.qx
            //
            // THE BLOCKS MUST CONTAIN STRUCTURE, and the first set did not.
            // Corner and edge blocks were chosen for asymmetry, but on this
            // fixture every one of them is flat background (3 counts), so each
            // check compared 12 against 12 and passed under the vertical flip it
            // was written to catch. Vacuous, and green. These blocks sit on the
            // beam (binned rows 5..10, cols 6..11) and on the four Bragg disks;
            // the guard below refuses to let that failure recur silently.
            let blocks = [
                (by: 5, bx: 7),    // beam, upper edge
                (by: 6, bx: 9),    // beam, centre
                (by: 8, bx: 14),   // Bragg disk right of the beam
                                   // (was the beam's left edge, which is
                                   // radially symmetric and so failed its own
                                   // anti-vacuity guard — the guard working)
                (by: 3, bx: 9),    // Bragg disk above the beam
                (by: 12, bx: 9),   // Bragg disk below the beam
                (by: 8, bx: 3),    // Bragg disk left of the beam
            ]
            for block in blocks {
                // ANTI-VACUITY, checked per block rather than assumed: this
                // comparison can only detect a reflection if the block's own sum
                // differs from the sum of the block a reflection would put there.
                // Without this, a future fixture change turns the placement
                // checks back into 12 == 12 and nothing says so.
                let mirroredY = try await virtualImage(fullData, source, .rectangle(
                    xMin: block.bx * bin, xMax: (block.bx + 1) * bin,
                    yMin: (binnedHeight - 1 - block.by) * bin,
                    yMax: (binnedHeight - block.by) * bin
                ))
                let mirroredX = try await virtualImage(fullData, source, .rectangle(
                    xMin: (binnedWidth - 1 - block.bx) * bin,
                    xMax: (binnedWidth - block.bx) * bin,
                    yMin: block.by * bin, yMax: (block.by + 1) * bin
                ))
                let ownSum = try await virtualImage(fullData, source, .rectangle(
                    xMin: block.bx * bin, xMax: (block.bx + 1) * bin,
                    yMin: block.by * bin, yMax: (block.by + 1) * bin
                ))
                check(ownSum.pixels != mirroredY.pixels && ownSum.pixels != mirroredX.pixels,
                      "detector bin / placement precondition: block (y \(block.by), x \(block.bx)) has the "
                      + "same sum as its mirror image, so the placement check below cannot detect a "
                      + "reflection and is asserting nothing")

                let binnedPixel = try await virtualImage(data, view.descriptor, .rectangle(
                    xMin: block.bx, xMax: block.bx + 1,
                    yMin: block.by, yMax: block.by + 1
                ))
                let sourceBlock = try await virtualImage(fullData, source, .rectangle(
                    xMin: block.bx * bin, xMax: (block.bx + 1) * bin,
                    yMin: block.by * bin, yMax: (block.by + 1) * bin
                ))
                check(binnedPixel.pixels == sourceBlock.pixels,
                      "detector bin / placement: binned pixel (y \(block.by), x \(block.bx)) is not the "
                      + "sum of source block y[\(block.by * bin)..<\((block.by + 1) * bin)] "
                      + "x[\(block.bx * bin)..<\((block.bx + 1) * bin)] "
                      + "(\(differenceReport(binnedPixel.pixels, sourceBlock.pixels))) — the total is "
                      + "conserved but a bin landed in the wrong place")
            }
        }

        // ---- Case 5. Both crops together. INVARIANCE: SELECTION+TRANSLATION -
        // Composed, because the two act on different axes and a defect that
        // swaps a scan offset for a detector offset passes both single-axis
        // cases. The scan and detector offsets are deliberately DIFFERENT
        // numbers so a transposed or reused offset cannot land on the right
        // answer by coincidence.
        do {
            let specification = LoadSpecification(scanCrop: scanCrop, detectorCrop: detectorCrop)
            let view = try LoadView(source: source, specification: specification)
            let data = FourDArray(reader: reader, view: view)
            let viewShape = DetectorShape.circle(
                centerX: beamX - Float(detectorCrop.xOffset),
                centerY: beamY - Float(detectorCrop.yOffset),
                radius: detectorRadius
            )
            let image = try await virtualImage(data, view.descriptor, viewShape)
            let expected = scanSubRectangle(fullImage.pixels, width: source.rx, crop: scanCrop)
            check(image.pixels == expected,
                  "scan+detector crop / virtual image: differs from the full-extent sub-rectangle "
                  + "(\(differenceReport(image.pixels, expected)))")
        }

        // ---- Case 6. Detector-crop disk detection. WEAKER, AND SAID SO ------
        // NOT exact, and not a defect: cross-correlation transforms the whole
        // detector grid, so a crop changes the FFT size and what wraps around.
        // The invariance that DOES hold is that a peak keeps its position in
        // SOURCE coordinates once re-referenced. The tolerance below is a
        // sub-pixel bound on the refinement, not a licence for a peak to move.
        do {
            let specification = LoadSpecification(detectorCrop: detectorCrop)
            let view = try LoadView(source: source, specification: specification)
            let data = FourDArray(reader: reader, view: view)
            guard let kernel = ProbeKernel.synthetic(radius: 3, qy: view.descriptor.qy, qx: view.descriptor.qx),
                  let detector = DiskDetector(kernel: kernel) else {
                fail("detector crop: could not build the probe kernel")
            }
            // Half a pixel. A genuine crop-offset defect displaces a peak by a
            // WHOLE pixel or more (the offsets here are 4 and 6), so this bound
            // separates "the FFT refined slightly differently" from "the crop
            // read from the wrong place" — which is the only distinction this
            // case needs to make.
            let tolerance: Float = 0.5
            var compared = 0
            for viewY in 0..<view.descriptor.ry {
                for viewX in 0..<view.descriptor.rx {
                    let pattern = try await data.pattern(ry: viewY, rx: viewX)
                    let found = peaks(in: pattern.pixels, detector: detector, params: params)
                    let expected = fullPeaks[viewY * source.rx + viewX]
                    // Compare only peaks the full-extent run found well inside
                    // the crop; one that sat near the crop edge is a different
                    // measurement, not a moved one.
                    for peak in expected {
                        let insideY = peak.y >= Float(detectorCrop.yOffset) + 3
                            && peak.y <= Float(detectorCrop.yOffset + detectorCrop.height) - 3
                        let insideX = peak.x >= Float(detectorCrop.xOffset) + 3
                            && peak.x <= Float(detectorCrop.xOffset + detectorCrop.width) - 3
                        guard insideY && insideX else { continue }
                        // Re-reference the view's peaks into source coordinates.
                        let match = found.min {
                            let da = abs($0.y + Float(detectorCrop.yOffset) - peak.y)
                                + abs($0.x + Float(detectorCrop.xOffset) - peak.x)
                            let db = abs($1.y + Float(detectorCrop.yOffset) - peak.y)
                                + abs($1.x + Float(detectorCrop.xOffset) - peak.x)
                            return da < db
                        }
                        guard let match else {
                            check(false, "detector crop / disk detection at (\(viewY),\(viewX)): no peaks at all")
                            continue
                        }
                        let dy = abs(match.y + Float(detectorCrop.yOffset) - peak.y)
                        let dx = abs(match.x + Float(detectorCrop.xOffset) - peak.x)
                        compared += 1
                        check(dy <= tolerance && dx <= tolerance,
                              "detector crop / disk detection at (\(viewY),\(viewX)): full-extent peak "
                              + "\(describe(peak)) re-references to (y \(match.y + Float(detectorCrop.yOffset)), "
                              + "x \(match.x + Float(detectorCrop.xOffset))), moved by (\(dy), \(dx)) px")
                    }
                }
            }
            check(compared > 0,
                  "detector crop / disk detection: no peak was inside the crop, so this case asserted nothing")
        }

        // ---- Case 7. The calibration re-reference, against the FIXTURE ------
        // Checked against the beam centres reference.py PUT ON DISK, not against
        // a second run of the app. This is the only case here with genuinely
        // external ground truth, and it is what stops the whole file from being
        // an elaborate self-consistency argument.
        try calibrationReReference(root: root, source: source,
                                   scanCrop: scanCrop, detectorCrop: detectorCrop)
    }

    /// Case 7, separated only for length.
    static func calibrationReReference(
        root: URL, source: DatasetDescriptor, scanCrop: AxisCrop, detectorCrop: AxisCrop
    ) throws {
        let text = try String(contentsOf: root.appendingPathComponent("origins.txt"), encoding: .utf8)
        let planted: [(y: Float, x: Float)] = text
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: " ").compactMap { Float($0) }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
        guard planted.count == source.ry * source.rx else {
            fail("origins.txt has \(planted.count) entries, expected \(source.ry * source.rx)")
        }

        let origin = OriginMaps(
            width: source.rx, height: source.ry,
            measuredX: planted.map(\.x), measuredY: planted.map(\.y),
            fittedX: planted.map(\.x), fittedY: planted.map(\.y)
        )
        var calibration = Calibration()
        calibration.origin = origin
        calibration.probeRadius = 3

        // Scan crop: the origin map is SELECTED, never transformed.
        do {
            let view = try LoadView(
                source: source, specification: LoadSpecification(scanCrop: scanCrop)
            )
            let outcome = CalibrationReReference.apply(
                view, to: calibration, provenance: CalibrationProvenance(),
                apertureCenter: .init(x: 18, y: 16)
            )
            guard let moved = outcome.calibration.origin else {
                fail("scan crop: the re-reference dropped the origin map entirely")
            }
            let expectedX = scanSubRectangle(planted.map(\.x), width: source.rx, crop: scanCrop)
            let expectedY = scanSubRectangle(planted.map(\.y), width: source.rx, crop: scanCrop)
            check(moved.fittedX == expectedX && moved.fittedY == expectedY,
                  "scan crop / calibration: the cropped origin map is not the planted sub-rectangle")
        }

        // Detector crop with a bin: the origin TRANSLATES, then RESCALES. The
        // expected value is written out here in full rather than by calling
        // `binnedCoordinate`, because that function is part of what is under
        // test — asking it to state its own expectation would agree with any
        // consistent convention error, including the `x / b` one its own
        // documentation warns about.
        do {
            let bin = 2
            let specification = LoadSpecification(detectorCrop: detectorCrop, detectorBin: bin)
            let view = try LoadView(source: source, specification: specification)
            let outcome = CalibrationReReference.apply(
                view, to: calibration, provenance: CalibrationProvenance(),
                apertureCenter: .init(x: 18, y: 16)
            )
            guard let moved = outcome.calibration.origin else {
                fail("detector crop + bin: the re-reference dropped the origin map entirely")
            }
            let expectedX = planted.map {
                ($0.x - Float(detectorCrop.xOffset) + 0.5) / Float(bin) - 0.5
            }
            let expectedY = planted.map {
                ($0.y - Float(detectorCrop.yOffset) + 0.5) / Float(bin) - 0.5
            }
            // ONE check over two whole arrays, so a failure here reports "the
            // re-reference is wrong" and its worst delta, not which positions.
            // That is enough to distinguish the convention error it exists to
            // catch — `value / bin` misplaces EVERY position by the same
            // (b-1)/2b — but it is not per-position precision, and Gate B was
            // right that "exactly one check went red" is the maximum possible
            // here rather than evidence of sharpness.
            check(moved.fittedX == expectedX && moved.fittedY == expectedY,
                  "detector crop + bin / calibration: origin re-reference differs from "
                  + "translate-then-rescale on the planted centres "
                  + "(x: \(differenceReport(moved.fittedX, expectedX)))")
        }
    }

    // MARK: The L3 residual — a resident tile at a non-zero lower bound

    /// `FourDArray.tile(yRange:from:)` reads out of a resident buffer at a byte
    /// offset.
    ///
    /// **THE ORIGINAL JUSTIFICATION FOR THIS CASE WAS WRONG, and Gate B refuted
    /// it on 2026-08-19.** It claimed the function was "only ever exercised at
    /// `lowerBound == 0`", citing tools/load-spec-test. That is true of
    /// load-spec-test — verified: it exits 0 with the offset deleted — but NOT of
    /// the suite. `tools/virtual-detector-residency` drives
    /// `tiledDPStatistics(maximumTileRows: 2)`, which reaches `lowerBound > 0`,
    /// and it goes red with the same breakage (`DP statistics [max]: differs at
    /// index 0 — resident 279.5537, tiled 1055.2793`). Both re-verified here.
    ///
    /// So L3 residual (b) was **narrower than recorded**: the offset was covered,
    /// but only at full extent. What this case actually adds is exhaustive
    /// `(lower, upper)` coverage **under a scan crop**, where the resident path
    /// and the reader's own crop offset compose — which no existing harness does.
    /// That is worth having, and it is a smaller claim than the one this comment
    /// used to make.
    ///
    /// The comparison is against the STREAMING read of the same rows, which is
    /// independent code (the reader's hyperslab) rather than the same offset
    /// arithmetic asked twice.
    static func residentTileOffset(root: URL) async throws {
        let reader = try H5Reader(path: root.appendingPathComponent("analysis.h5").path)
        let source = try await reader.discoverPrimaryDataset()

        // Under a scan crop as well as at full extent: a resident cube of a
        // cropped view has BOTH offsets in play, and only their composition is
        // wrong if the resident path re-applies the crop the reader already did.
        let specifications = [
            ("full extent", LoadSpecification()),
            ("scan crop", LoadSpecification(
                scanCrop: AxisCrop(yOffset: 2, xOffset: 1, height: 4, width: 5)
            )),
        ]

        for (label, specification) in specifications {
            let view = try LoadView(source: source, specification: specification)

            let streaming = FourDArray(reader: reader, view: view)
            let resident = FourDArray(reader: reader, view: view)
            await resident.setResidencyRequest(.resident)
            let admitted = try await resident.makeResident(maximumRows: 2)
            let isResident = await resident.isResident
            check(admitted && isResident,
                  "\(label): the cube never went resident (admitted \(admitted), resident \(isResident)) "
                  + "— every assertion below would then compare streaming against streaming")
            guard admitted, isResident else { continue }

            let rows = view.descriptor.ry
            var lowerBoundsExercised: [Int] = []
            for lower in 0..<rows {
                for upper in (lower + 1)...rows {
                    let fromDisk = try await streaming.scanTile(yRange: lower..<upper).pixels
                    let fromMemory = try await resident.scanTile(yRange: lower..<upper).pixels
                    check(fromMemory == fromDisk,
                          "\(label): resident tile \(lower)..<\(upper) differs from the streamed read "
                          + "(\(differenceReport(fromMemory, fromDisk)))")
                    if lower > 0 { lowerBoundsExercised.append(lower) }
                }
            }
            // The residual was specifically about lowerBound > 0. Assert that
            // this run actually reached it, so a future shape change cannot
            // quietly return the case to the state it was written to fix.
            check(!lowerBoundsExercised.isEmpty,
                  "\(label): no tile with lowerBound > 0 was exercised — this is the whole point of the case")
        }
    }

    // MARK: The metamorphic property suite (seeded here for the phase)

    /// Invariances stated as properties over randomized fixtures, so this class
    /// of defect is caught by machine rather than by someone reasoning about it
    /// late. Seeded in reference.py: randomized enough that no single hand-picked
    /// arrangement can satisfy them by luck, reproducible enough that a failure
    /// can be re-run.
    static func metamorphicProperties(root: URL) async throws {
        for index in 0..<5 {
            let path = root.appendingPathComponent("random-\(index).h5").path
            let reader = try H5Reader(path: path)
            let source = try await reader.discoverPrimaryDataset()
            let full = FourDArray(reader: reader, view: LoadView(fullExtentOf: source))

            // A detector that is not centred and not symmetric, so a transposed
            // or mirrored index cannot map it onto itself.
            let shape = DetectorShape.rectangle(
                xMin: 3, xMax: source.qx - 5, yMin: 2, yMax: source.qy - 4
            )
            let fullImage = try await virtualImage(full, source, shape)

            // ---- P1. COMMUTATION: crop-then-analyse == analyse-then-crop ----
            for (cropIndex, crop) in scanCrops(for: source).enumerated() {
                let view = try LoadView(
                    source: source, specification: LoadSpecification(scanCrop: crop)
                )
                let data = FourDArray(reader: reader, view: view)
                let image = try await virtualImage(data, view.descriptor, shape)
                let expected = scanSubRectangle(fullImage.pixels, width: source.rx, crop: crop)
                check(image.pixels == expected,
                      "P1 commutation, random-\(index) crop \(cropIndex) "
                      + "(y\(crop.yOffset)+\(crop.height), x\(crop.xOffset)+\(crop.width)): "
                      + "cropping and analysing do not commute "
                      + "(\(differenceReport(image.pixels, expected)))")
            }

            // ---- P2. CONSERVATION: binning preserves total intensity --------
            // Over the whole TRIMMED detector, which is the region binning
            // actually keeps — comparing against the untrimmed total would fail
            // for two of these five fixtures by construction (their detector
            // extents do not divide by 4) and would be testing reference.py's
            // shapes rather than the app.
            for bin in [2, 4] {
                let view = try LoadView(
                    source: source, specification: LoadSpecification(detectorBin: bin)
                )
                let data = FourDArray(reader: reader, view: view)
                let binnedTotal = try await virtualImage(data, view.descriptor, .rectangle(
                    xMin: 0, xMax: view.descriptor.qx, yMin: 0, yMax: view.descriptor.qy
                ))
                let keptHeight = source.qy - source.qy % bin
                let keptWidth = source.qx - source.qx % bin
                let sourceTotal = try await virtualImage(full, source, .rectangle(
                    xMin: 0, xMax: keptWidth, yMin: 0, yMax: keptHeight
                ))
                check(binnedTotal.pixels == sourceTotal.pixels,
                      "P2 conservation, random-\(index) bin \(bin): total intensity over the trimmed "
                      + "detector changed under binning "
                      + "(\(differenceReport(binnedTotal.pixels, sourceTotal.pixels)))")
            }

            // ---- P3. TRANSLATION: a re-referenced detector reads the same ---
            let detectorCrop = AxisCrop(
                yOffset: 2, xOffset: 3,
                height: source.qy - 4, width: source.qx - 5
            )
            do {
                let view = try LoadView(
                    source: source, specification: LoadSpecification(detectorCrop: detectorCrop)
                )
                let data = FourDArray(reader: reader, view: view)
                // The same physical rectangle, expressed in the cropped frame.
                let viewShape = DetectorShape.rectangle(
                    xMin: 3 - detectorCrop.xOffset, xMax: source.qx - 5 - detectorCrop.xOffset,
                    yMin: 2 - detectorCrop.yOffset, yMax: source.qy - 4 - detectorCrop.yOffset
                )
                let image = try await virtualImage(data, view.descriptor, viewShape)
                check(image.pixels == fullImage.pixels,
                      "P3 translation, random-\(index): the same detector re-referenced into the "
                      + "cropped frame sums different pixels "
                      + "(\(differenceReport(image.pixels, fullImage.pixels)))")
            }
        }
    }

    // MARK: The absolute origin check — a bias P4 cannot see

    /// **Why this exists: P4 compares two measurements to each other, so any
    /// CONSTANT error cancels.** Gate B demonstrated it on 2026-08-19 by adding
    /// `+1.0f` to the measured origin X in `Shaders/OriginMeasure.metal` — every
    /// check in this harness stayed green, while a one-pixel origin bias
    /// propagates into every Bragg vector, every strain component and every ACOM
    /// orientation the app produces.
    ///
    /// The ground truth was already on disk and already being read: reference.py
    /// writes the beam centre it planted for each scan position, and Case 7 was
    /// using it for the re-reference arithmetic only. This asks the more basic
    /// question — does the app find the beam where the fixture put it?
    ///
    /// The bound is MEASURED, and it is a characterization of the same known
    /// coarse-grid defect as P4, not a target anyone chose. It must go down, never
    /// up.
    static func originAbsoluteAccuracy(root: URL) async throws {
        let reader = try H5Reader(path: root.appendingPathComponent("analysis.h5").path)
        let source = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, view: LoadView(fullExtentOf: source))
        let pixels = try await data.scanTile(yRange: 0..<source.ry).pixels

        guard let buffer = MetalEngine.shared.device.makeBuffer(
            bytes: pixels,
            length: pixels.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { fail("absolute origin: could not allocate the cube") }

        let measured = try MetalEngine.shared.measureOrigins(
            cube: buffer,
            params: OriginParams(
                ry: UInt32(source.ry), rx: UInt32(source.rx),
                qy: UInt32(source.qy), qx: UInt32(source.qx),
                r: 3, rscale: 1.2
            )
        )

        let text = try String(contentsOf: root.appendingPathComponent("origins.txt"), encoding: .utf8)
        let planted: [(y: Float, x: Float)] = text
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: " ").compactMap { Float($0) }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
        guard planted.count == source.ry * source.rx else {
            fail("absolute origin: origins.txt has \(planted.count) entries")
        }

        var worst: Float = 0
        var worstCase = ""
        for index in 0..<planted.count {
            // measureOrigins writes x then y per position (OriginCalibration.run).
            let dx = abs(measured[2 * index] - planted[index].x)
            let dy = abs(measured[2 * index + 1] - planted[index].y)
            if max(dx, dy) > worst {
                worst = max(dx, dy)
                worstCase = "position \(index): measured (y \(measured[2 * index + 1]), "
                    + "x \(measured[2 * index])), fixture planted (y \(planted[index].y), "
                    + "x \(planted[index].x))"
            }
        }
        print("absolute origin accuracy: worst deviation \(worst) px — \(worstCase)")
        check(worst <= ORIGIN_ABSOLUTE_BOUND,
              "absolute origin: the measured beam centre is \(worst) px from where the fixture planted "
              + "it, worse than the recorded bound of \(ORIGIN_ABSOLUTE_BOUND) px (\(worstCase)). "
              + "Unlike P4 this catches a CONSTANT bias, which is the class that propagates into every "
              + "Bragg vector, strain component and ACOM orientation.")
    }

    // MARK: P4 — translation equivariance of the origin measurement

    /// **A CHARACTERIZATION OF A KNOWN DEFECT, NOT A PASSING INVARIANCE.**
    /// Read this before trusting a green run.
    ///
    /// The property that *should* hold: translate a diffraction pattern by an
    /// integer (dy, dx) and the measured origin moves by exactly (dy, dx).
    /// It does not, and the reason is visible in `Shaders/OriginMeasure.metal`:
    /// the coarse step scans bin-aligned blocks pinned to the DETECTOR origin
    /// (`for (uint by = 0; by < p.qy; by += bin)`, line 47), so translating the
    /// feature moves it *within* its block. The coarse centre therefore jumps in
    /// bin-sized steps rather than following the feature, and the CoM window it
    /// seeds — radius `r * rscale` — admits a different pixel set at the two
    /// positions. Already recorded in docs/open-items.md: "the same dataset
    /// cropped two ways can fit two origins ~1 px apart".
    ///
    /// So this asserts the MEASURED bound, not zero. A green run here means "the
    /// known deviation has not got worse", and nothing else. The assertion
    /// tightens to exact when S12 weighs the translation-equivariant coarse step
    /// and S13 lands whatever it recommends — at which point this property
    /// becomes what its name says.
    ///
    /// It is seeded here anyway, because the class of defect it covers is the
    /// one this repo keeps finding late and by hand.
    static func originTranslationEquivariance() throws {
        let qy = 32, qx = 36
        let radius: Float = 3
        let rscale: Float = 1.2      // the app's default (OriginCalibration.run)

        /// One pattern with a hard disk at (cy, cx) — reference.py's fixture,
        /// restated in Swift so the translations can be generated here rather
        /// than enumerated on disk.
        func pattern(cy: Int, cx: Int) -> [Float] {
            var values = [Float](repeating: 3, count: qy * qx)
            for y in 0..<qy {
                for x in 0..<qx {
                    let dy = Float(y - cy), dx = Float(x - cx)
                    if dy * dy + dx * dx <= radius * radius {
                        values[y * qx + x] += 900
                    }
                }
            }
            return values
        }

        // The base centre is deliberately NOT on a bin boundary: `bin` is
        // round(r) = 3, and a base on the grid would make some translations
        // land back on it and look equivariant for the wrong reason.
        let baseY = 14, baseX = 16
        var worstDeviation: Float = 0
        var worstCase = ""

        for dy in -3...3 {
            for dx in -3...3 where !(dy == 0 && dx == 0) {
                let a = pattern(cy: baseY, cx: baseX)
                let b = pattern(cy: baseY + dy, cx: baseX + dx)
                var cube = a
                cube.append(contentsOf: b)
                guard let buffer = MetalEngine.shared.device.makeBuffer(
                    bytes: cube,
                    length: cube.count * MemoryLayout<Float>.stride,
                    options: .storageModeShared
                ) else { fail("P4: could not allocate the two-pattern cube") }

                let measured = try MetalEngine.shared.measureOrigins(
                    cube: buffer,
                    params: OriginParams(ry: 1, rx: 2, qy: UInt32(qy), qx: UInt32(qx),
                                         r: radius, rscale: rscale)
                )
                // measureOrigins writes x then y per position (OriginCalibration.run).
                let movedX = measured[2] - measured[0]
                let movedY = measured[3] - measured[1]
                let deviation = max(abs(movedX - Float(dx)), abs(movedY - Float(dy)))
                if deviation > worstDeviation {
                    worstDeviation = deviation
                    worstCase = "shift (dy \(dy), dx \(dx)) measured as (dy \(movedY), dx \(movedX))"
                }
            }
        }

        print("P4 origin translation equivariance: worst deviation \(worstDeviation) px — \(worstCase)")
        check(worstDeviation <= P4_KNOWN_BOUND,
              "P4 equivariance: the origin measurement's translation error is \(worstDeviation) px, "
              + "worse than the recorded bound of \(P4_KNOWN_BOUND) px (\(worstCase)). This test pins a "
              + "KNOWN defect in Shaders/OriginMeasure.metal's coarse step; a regression here means it got "
              + "worse, not that it appeared.")
    }

    /// A handful of scan crops per fixture, including the degenerate ones. The
    /// single-row and single-column crops are here because a reduction over one
    /// row is where an offset error is most likely to still produce a plausible
    /// number.
    static func scanCrops(for source: DatasetDescriptor) -> [AxisCrop] {
        var crops: [AxisCrop] = []
        if source.ry >= 2, source.rx >= 2 {
            crops.append(AxisCrop(yOffset: 1, xOffset: 1,
                                  height: source.ry - 1, width: source.rx - 1))
        }
        if source.ry >= 3, source.rx >= 3 {
            crops.append(AxisCrop(yOffset: 1, xOffset: 2,
                                  height: source.ry - 2, width: source.rx - 2))
        }
        crops.append(AxisCrop(yOffset: source.ry - 1, xOffset: 0, height: 1, width: source.rx))
        crops.append(AxisCrop(yOffset: 0, xOffset: source.rx - 1, height: source.ry, width: 1))
        return crops
    }
}
