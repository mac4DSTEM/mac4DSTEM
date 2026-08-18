//
//  tools/preprocess-crop-bin-test — stage L4 (docs/load-pipeline-plan.md).
//
//  THE CLAIM: binning on read reproduces py4DSTEM's `bin_data_diffraction`
//  EXACTLY — the sum, the edge-remainder crop, and the Q_pixel_size rescale —
//  and the app's own deviations from it are the ones written down, no others.
//
//  The arbiter is py4DSTEM itself, running from the vendored source. The plan
//  named a different fixture: "the training set already carries bin2 and bin8
//  files of the same data". IT DOES NOT — checked 2026-08-18, there is one
//  Particle_1 file whose name carries both tokens because one describes the
//  acquisition and the other a later reduction. Comparing against the reference
//  implementation is stronger than that pair would have been: it pins the
//  remainder rule and sum-not-average against the source of truth instead of
//  transitively through a file somebody else produced.
//
//  `==` and not a tolerance: reference.py fills the cubes with small integers,
//  so every partial sum is exact in float32 and accumulation order cannot
//  matter. On arbitrary float data a bit-identity claim would be false, and a
//  tolerance would hide a real disagreement rather than expose it.
//

import Foundation

var failures: [String] = []

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { failures.append(message()) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

struct CropSpec: Decodable {
    let yOffset: Int
    let xOffset: Int
    let height: Int
    let width: Int
}

struct Case: Decodable {
    let name: String
    let shape: [Int]
    let bin: Int
    let crop: CropSpec?
    let expectedShape: [Int]
    let qPixelSize: Double
    let binnedQPixelSize: Double
}

@main struct PreprocessCropBinHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fail("usage: harness fixture-dir") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try JSONDecoder().decode(
            [Case].self, from: Data(contentsOf: root.appendingPathComponent("manifest.json"))
        )
        guard !manifest.isEmpty else { fail("empty manifest") }

        for testCase in manifest {
            let reader = try H5Reader(path: root.appendingPathComponent("\(testCase.name).h5").path)
            let source = try await reader.discoverPrimaryDataset()
            guard source.shape == testCase.shape else {
                check(false, "\(testCase.name): source shape \(source.shape) != \(testCase.shape)")
                continue
            }

            var specification = LoadSpecification()
            specification.detectorBin = testCase.bin
            if let crop = testCase.crop {
                specification.detectorCrop = AxisCrop(
                    yOffset: crop.yOffset, xOffset: crop.xOffset,
                    height: crop.height, width: crop.width
                )
            }
            let view = try LoadView(source: source, specification: specification)

            // 1. Shape. py4DSTEM's own output shape is the reference, so this
            //    also pins the remainder rule before a single value is compared.
            check(view.descriptor.shape == testCase.expectedShape,
                  "\(testCase.name): view shape \(view.descriptor.shape) != py4DSTEM's \(testCase.expectedShape)")
            guard view.descriptor.shape == testCase.expectedShape else { continue }

            // 2. Values, exactly, through the real reader.
            let expectedData = try Data(contentsOf: root.appendingPathComponent("\(testCase.name).expected"))
            let expected = expectedData.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float32.self))
            }
            let tile = try await reader.readScanTile(view, yRange: 0..<view.descriptor.ry)
            check(tile.pixels.count == expected.count,
                  "\(testCase.name): \(tile.pixels.count) values against py4DSTEM's \(expected.count)")
            if tile.pixels.count == expected.count {
                var firstMismatch: String?
                for index in 0..<expected.count where tile.pixels[index] != expected[index] {
                    firstMismatch = "index \(index): app \(tile.pixels[index]), py4DSTEM \(expected[index])"
                    break
                }
                check(firstMismatch == nil,
                      "\(testCase.name): binned values differ from py4DSTEM — \(firstMismatch ?? "")")
            }

            // 3. The other two read entry points must agree with the tile. They
            //    are separate code paths with separate offset arithmetic, and
            //    the streaming path only ever uses one of them.
            for ry in 0..<view.descriptor.ry {
                let row = try await reader.readScanRow(view, ry: ry)
                let stride = view.descriptor.rx * view.descriptor.qy * view.descriptor.qx
                let slice = Array(tile.pixels[(ry * stride)..<((ry + 1) * stride)])
                check(row == slice, "\(testCase.name): readScanRow \(ry) disagrees with the tile")
                for rx in 0..<view.descriptor.rx {
                    let pattern = try await reader.readPattern(view, ry: ry, rx: rx)
                    let patternCount = view.descriptor.qy * view.descriptor.qx
                    let expectedPattern = Array(slice[(rx * patternCount)..<((rx + 1) * patternCount)])
                    check(pattern == expectedPattern,
                          "\(testCase.name): readPattern (\(ry), \(rx)) disagrees with the tile")
                }
            }

            // 4. THE INTENSITY CONSEQUENCE, stated rather than assumed.
            //    py4DSTEM sums, so a binned pixel is the sum of bin^2 source
            //    pixels and the whole cube's total intensity is unchanged by
            //    binning (up to whatever the edge remainder dropped). Averaging
            //    instead — the plausible "fix" — would divide every value by
            //    bin^2 and this would catch it.
            if testCase.crop == nil {
                let unbinned = try await reader.readScanTile(
                    LoadView(fullExtentOf: source), yRange: 0..<source.ry
                )
                let readHeight = source.qy - (source.qy % testCase.bin)
                let readWidth = source.qx - (source.qx % testCase.bin)
                var keptTotal: Float = 0
                for position in 0..<(source.ry * source.rx) {
                    let base = position * source.qy * source.qx
                    for y in 0..<readHeight {
                        for x in 0..<readWidth {
                            keptTotal += unbinned.pixels[base + y * source.qx + x]
                        }
                    }
                }
                let binnedTotal = tile.pixels.reduce(0, +)
                check(binnedTotal == keptTotal,
                      "\(testCase.name): binning changed total intensity — \(binnedTotal) against \(keptTotal). It must SUM, not average.")
            }

            // 5. Q_pixel_size scales UP by the bin factor, matching py4DSTEM's
            //    own value from the same run.
            var calibration = Calibration()
            calibration.qPixelSize = testCase.qPixelSize
            calibration.probeRadius = 8
            calibration.ellipseA = 1.04
            calibration.ellipseB = 0.96
            calibration.ellipseTheta = 0.3
            let outcome = CalibrationReReference.apply(
                view, to: calibration, provenance: CalibrationProvenance(),
                apertureCenter: .init(x: 4, y: 4)
            )
            let scaled = outcome.calibration.qPixelSize ?? 0
            check(abs(scaled - testCase.binnedQPixelSize) < 1e-12,
                  "\(testCase.name): Q pixel size \(scaled) != py4DSTEM's \(testCase.binnedQPixelSize)")

            // 6. THE DEVIATIONS, which py4DSTEM does not perform. A length in
            //    detector pixels shrinks with the bin; an angle does not.
            check(outcome.calibration.probeRadius == 8 / Float(testCase.bin),
                  "\(testCase.name): probe radius \(outcome.calibration.probeRadius as Any) was not divided by \(testCase.bin)")
            check(abs((outcome.calibration.ellipseA ?? 0) - 1.04 / Double(testCase.bin)) < 1e-12
                  && abs((outcome.calibration.ellipseB ?? 0) - 0.96 / Double(testCase.bin)) < 1e-12,
                  "\(testCase.name): the ellipse semi-axes were not rescaled")
            check(outcome.calibration.ellipseTheta == 0.3,
                  "\(testCase.name): the ellipse angle must not change with binning")

            // Rescaling both semi-axes must leave every corrected offset
            // bit-identical, because the transform uses only their ratio. If
            // this ever fails, the rescale has changed a result rather than a
            // label, and that is a different decision than the one taken.
            let before = calibration.ellipseCorrectedOffset(dx: 3.5, dy: -2.25)
            let after = outcome.calibration.ellipseCorrectedOffset(dx: 3.5, dy: -2.25)
            check(before == after,
                  "\(testCase.name): rescaling the ellipse changed a corrected offset \(before) -> \(after)")
        }

        // 7. The offered factors. py4DSTEM accepts any integer; this app offers
        //    2, 4 and 8, and must REFUSE the rest rather than silently rounding.
        let source = DatasetDescriptor(
            filePath: "/tmp/x", datasetPath: "/data", shape: [2, 2, 16, 16],
            dtypeDescription: "float32", chunkShape: nil
        )
        for factor in [0, -2, 3, 5, 6, 7, 16] {
            var specification = LoadSpecification()
            specification.detectorBin = factor
            check((try? LoadView(source: source, specification: specification)) == nil,
                  "bin factor \(factor) was accepted; only 1, 2, 4 and 8 are offered")
        }
        for factor in [1, 2, 4, 8] {
            var specification = LoadSpecification()
            specification.detectorBin = factor
            check((try? LoadView(source: source, specification: specification)) != nil,
                  "bin factor \(factor) was refused; it is one of the offered factors")
        }

        // 8. A bin that would leave no pixels is refused, not clamped to 1.
        var empty = LoadSpecification()
        empty.detectorBin = 8
        empty.detectorCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        check((try? LoadView(source: source, specification: empty)) == nil,
              "binning a 4 x 4 crop by 8 was accepted")

        if failures.isEmpty {
            print("preprocess-crop-bin-test: all passed")
        } else {
            for message in failures.prefix(40) {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            }
            FileHandle.standardError.write(
                Data("preprocess-crop-bin-test: \(failures.count) failure(s)\n".utf8)
            )
            exit(1)
        }
    }
}
