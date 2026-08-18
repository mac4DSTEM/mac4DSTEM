//
//  tools/load-spec-test — stage L3 (docs/load-pipeline-plan.md).
//
//  THE ONE CLAIM: a cropped read equals the corresponding slice of a full read,
//  EXACTLY, on every reader. Not approximately — `==` on Float, because a crop
//  selects stored values and must not transform them. A tolerance here would
//  hide precisely the defect this stage can produce: the right number of pixels
//  read from the wrong place.
//
//  The expected values are computed in this harness by plain arithmetic on the
//  full-extent read, never by asking the reader a second question. A harness
//  that derived its expectation from the same offset code it is testing would
//  agree with any consistent mistake.
//
//  Five conformers, because five is the number the plan's 2026-08-18 correction
//  found — MIB and EMPAD both live in VendorRawReaders.swift, and
//  DemoFourDDataSource is a reader too. Four of the five ignored the descriptor
//  they were handed before this stage.
//
//  Each reader is exercised on all three read entry points (readScanTile,
//  readScanRow, readPattern), because they are separate code paths with
//  separate offset arithmetic, and the streaming path only uses one of them.
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

/// The expected crop, by index arithmetic that shares no code with the readers.
///
/// **`fullCube` is the reader's own full-extent read, so on its own this proves
/// self-consistency, not correctness.** A transformation applied equally to the
/// full and the cropped read — a transposed detector index, say — commutes with
/// cropping and passes: adversarial review demonstrated exactly that on
/// 2026-08-18 by transposing EMPAD's decode loop, and every assertion here
/// stayed green, because both sides transposed together. It only shows up on a
/// non-square detector.
///
/// That is why `exercise` takes a `sourceValue` closure wherever the fixture is
/// one this harness wrote: the cube is then checked against the value the
/// fixture *put on disk*, which no bug in a reader can move. See `analytic`.
func expectedSlice(
    fullCube: [Float], source: DatasetDescriptor,
    specification: LoadSpecification, viewRows: Range<Int>
) -> [Float] {
    // Offsets read straight off the crop rather than through
    // `LoadSpecification.scanOffset`/`detectorOffset`, so this shares no
    // accessor with the readers either.
    let scanY = specification.scanCrop?.yOffset ?? 0
    let scanX = specification.scanCrop?.xOffset ?? 0
    let detectorY = specification.detectorCrop?.yOffset ?? 0
    let detectorX = specification.detectorCrop?.xOffset ?? 0
    let viewRx = specification.scanCrop?.width ?? source.rx
    let viewQy = specification.detectorCrop?.height ?? source.qy
    let viewQx = specification.detectorCrop?.width ?? source.qx
    var out: [Float] = []
    out.reserveCapacity(viewRows.count * viewRx * viewQy * viewQx)
    for y in viewRows {
        for x in 0..<viewRx {
            for qy in 0..<viewQy {
                for qx in 0..<viewQx {
                    let index = (((scanY + y) * source.rx + scanX + x) * source.qy
                                 + detectorY + qy) * source.qx + detectorX + qx
                    out.append(fullCube[index])
                }
            }
        }
    }
    return out
}

/// Specifications exercised on every reader. Chosen so that a mistake in any
/// one term is visible: offsets are non-zero on both axes and different from
/// each other, extents are not divisors of the source, and one case crops a
/// single scan row and a single detector column.
func specifications(for source: DatasetDescriptor) -> [(String, LoadSpecification)] {
    let ry = source.ry, rx = source.rx, qy = source.qy, qx = source.qx
    var cases: [(String, LoadSpecification)] = [("full extent", .fullExtent)]

    if ry >= 2, rx >= 2 {
        cases.append(("scan crop only", LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: ry - 1, width: rx - 1)
        )))
    }
    // A rank-3 HDF5 dataset is reshaped to [1, N, Qy, Qx], so ry == 1 and every
    // case above is skipped — which left the rank-3 scan crop with NO coverage
    // at all, and a deliberate bug in it (using the scan-y offset where the
    // scan-x offset belongs, indistinguishable when y is always 0) passed the
    // whole harness. That is the one mapping `H5Reader.hyperslab` singles out as
    // easy to get wrong. Adversarial review, 2026-08-18.
    if ry == 1, rx >= 4 {
        cases.append(("single scan row, x crop", LoadSpecification(
            scanCrop: AxisCrop(yOffset: 0, xOffset: 2, height: 1, width: rx - 3)
        )))
        if qy >= 3, qx >= 3 {
            cases.append(("single scan row, x crop and detector crop", LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 1, height: 1, width: rx - 2),
                detectorCrop: AxisCrop(yOffset: 1, xOffset: 2, height: qy - 2, width: qx - 2)
            )))
        }
    }
    if qy >= 3, qx >= 3 {
        cases.append(("detector crop only", LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 1, xOffset: 2, height: qy - 2, width: qx - 2)
        )))
    }
    if ry >= 2, rx >= 3, qy >= 4, qx >= 4 {
        cases.append(("both crops, different offsets", LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 2, height: ry - 1, width: rx - 2),
            detectorCrop: AxisCrop(yOffset: 2, xOffset: 1, height: qy - 3, width: qx - 2)
        )))
        cases.append(("single row, single column", LoadSpecification(
            scanCrop: AxisCrop(yOffset: ry - 1, xOffset: rx - 1, height: 1, width: 1),
            detectorCrop: AxisCrop(yOffset: qy - 1, xOffset: qx - 1, height: 1, width: 1)
        )))
    }
    return cases
}

/// Every assertion this harness makes about one reader.
func exercise(
    _ label: String, source: DatasetDescriptor, fullCube: [Float],
    sourceValue: ((Int) -> Float)?,
    expectedPushdown: LoadPushdown,
    read: (LoadView, Range<Int>) async throws -> FourDScanTile,
    readRow: (LoadView, Int) async throws -> [Float],
    readPattern: (LoadView, Int, Int) async throws -> [Float],
    pushdown: LoadPushdown
) async {
    check(pushdown == expectedPushdown,
          "\(label): declares pushdown \(pushdown), expected \(expectedPushdown)")

    // INDEPENDENT GROUND TRUTH. Every fixture this harness writes is filled with
    // a known function of its own flat SOURCE index, so this pins the reader's
    // full-extent read against the bytes on disk — not against itself. Without
    // it, any transformation that commutes with cropping (a transposed detector
    // index on a square detector is the demonstrated one) passes every
    // comparison below, because both sides carry it.
    if let sourceValue {
        var mismatch: String?
        for index in 0..<fullCube.count where fullCube[index] != sourceValue(index) {
            mismatch = "index \(index): read \(fullCube[index]), fixture wrote \(sourceValue(index))"
            break
        }
        check(mismatch == nil,
              "\(label): the full-extent read does not match what the fixture wrote — \(mismatch ?? "")")
    }

    for (name, specification) in specifications(for: source) {
        let view: LoadView
        do { view = try LoadView(source: source, specification: specification) }
        catch { check(false, "\(label)/\(name): building the view threw \(error)"); continue }

        let viewRy = view.descriptor.ry
        let viewRx = view.descriptor.rx
        let expectedShape = [
            specification.scanCrop?.height ?? source.ry,
            specification.scanCrop?.width ?? source.rx,
            specification.detectorCrop?.height ?? source.qy,
            specification.detectorCrop?.width ?? source.qx,
        ]
        check(view.descriptor.shape == expectedShape,
              "\(label)/\(name): view shape \(view.descriptor.shape) != \(expectedShape)")

        // 1. The whole view in one tile.
        do {
            let tile = try await read(view, 0..<viewRy)
            let expected = expectedSlice(fullCube: fullCube, source: source,
                                         specification: specification, viewRows: 0..<viewRy)
            check(tile.pixels == expected,
                  "\(label)/\(name): whole-view tile differs from the slice of the full read")
            check(tile.scanWidth == viewRx && tile.detectorHeight == expectedShape[2]
                  && tile.detectorWidth == expectedShape[3],
                  "\(label)/\(name): tile reports \(tile.scanWidth)x\(tile.detectorHeight)x\(tile.detectorWidth)")
        } catch {
            check(false, "\(label)/\(name): whole-view tile threw \(error)")
        }

        // 2. Every sub-tile, because the streaming path never asks for the whole
        //    cube at once and a per-tile offset error would survive step 1.
        for lower in 0..<viewRy {
            for upper in (lower + 1)...viewRy {
                do {
                    let tile = try await read(view, lower..<upper)
                    let expected = expectedSlice(fullCube: fullCube, source: source,
                                                 specification: specification,
                                                 viewRows: lower..<upper)
                    check(tile.pixels == expected,
                          "\(label)/\(name): tile \(lower)..<\(upper) differs from the slice")
                    check(tile.yRange == lower..<upper,
                          "\(label)/\(name): tile \(lower)..<\(upper) reports \(tile.yRange)")
                } catch {
                    check(false, "\(label)/\(name): tile \(lower)..<\(upper) threw \(error)")
                }
            }
        }

        // 3. readScanRow and readPattern — separate offset arithmetic.
        for y in 0..<viewRy {
            do {
                let row = try await readRow(view, y)
                let expected = expectedSlice(fullCube: fullCube, source: source,
                                             specification: specification, viewRows: y..<(y + 1))
                check(row == expected, "\(label)/\(name): scan row \(y) differs from the slice")
            } catch {
                check(false, "\(label)/\(name): scan row \(y) threw \(error)")
            }
            for x in 0..<viewRx {
                do {
                    let pattern = try await readPattern(view, y, x)
                    let whole = expectedSlice(fullCube: fullCube, source: source,
                                              specification: specification, viewRows: y..<(y + 1))
                    let patternCount = expectedShape[2] * expectedShape[3]
                    let expected = Array(whole[(x * patternCount)..<((x + 1) * patternCount)])
                    check(pattern == expected,
                          "\(label)/\(name): pattern (\(y), \(x)) differs from the slice")
                } catch {
                    check(false, "\(label)/\(name): pattern (\(y), \(x)) threw \(error)")
                }
            }
        }
    }

    // 4. Refusals. A specification a reader cannot honour must stop the read;
    //    the one thing it must never do is return the full extent.
    let outOfBounds = LoadSpecification(
        scanCrop: AxisCrop(yOffset: source.ry, xOffset: 0, height: 1, width: source.rx)
    )
    check((try? LoadView(source: source, specification: outOfBounds)) == nil,
          "\(label): an out-of-bounds scan crop was accepted")
    let detectorOutOfBounds = LoadSpecification(
        detectorCrop: AxisCrop(yOffset: 0, xOffset: source.qx - 1, height: source.qy, width: 2)
    )
    check((try? LoadView(source: source, specification: detectorOutOfBounds)) == nil,
          "\(label): an out-of-bounds detector crop was accepted")
    // Bin factors: L4 implemented 2, 4 and 8, so those are accepted here and the
    // VALUES are checked against py4DSTEM in tools/preprocess-crop-bin-test.
    // What this harness still owns is the refusal of everything else — py4DSTEM
    // takes any integer, this app does not, and a factor that slipped through
    // would silently reshape the detector.
    for factor in [2, 4, 8] {
        var binned = LoadSpecification.fullExtent
        binned.detectorBin = factor
        let view = try? LoadView(source: source, specification: binned)
        // A factor larger than the detector legitimately leaves nothing, and
        // that refusal is correct — the fixtures here run from a 6 x 5 detector
        // up to 256 x 256, so both outcomes are exercised across the readers.
        if source.qy >= factor && source.qx >= factor {
            check(view != nil,
                  "\(label): bin factor \(factor) was refused on a \(source.qy) x \(source.qx) detector")
        } else {
            check(view == nil,
                  "\(label): bin factor \(factor) was accepted on a \(source.qy) x \(source.qx) detector, which leaves no pixels")
        }
    }
    for factor in [0, -1, 3, 5, 6, 7, 9, 16] {
        var binned = LoadSpecification.fullExtent
        binned.detectorBin = factor
        check((try? LoadView(source: source, specification: binned)) == nil,
              "\(label): bin factor \(factor) was accepted; only 2, 4 and 8 are offered")
    }

    // 5. A view of a *different* source must be refused, not silently read.
    //    This is the mismatched-pair failure the LoadView type exists to make
    //    unrepresentable at call sites; readers check it too, because a reader
    //    can be handed a view built from another file's descriptor.
    let foreign = DatasetDescriptor(
        filePath: source.filePath, datasetPath: source.datasetPath,
        shape: [source.ry + 1, source.rx, source.qy, source.qx],
        dtypeDescription: source.dtypeDescription, chunkShape: source.chunkShape
    )
    do {
        _ = try await read(LoadView(fullExtentOf: foreign), 0..<1)
        check(false, "\(label): a view of a differently-shaped source was read anyway")
    } catch {
        // Any throw satisfies "refused, not silently read".
    }
}

/// Read a whole reader at full extent, as one flat source cube.
func fullCube(
    of source: DatasetDescriptor,
    read: (LoadView, Range<Int>) async throws -> FourDScanTile
) async throws -> [Float] {
    try await read(LoadView(fullExtentOf: source), 0..<source.ry).pixels
}

@main struct LoadSpecHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fail("usage: harness fixture-dir") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])

        // ---- HDF5, rank 4 --------------------------------------------------
        do {
            let reader = try H5Reader(path: root.appendingPathComponent("rank4.h5").path)
            let source = try await reader.discoverPrimaryDataset()
            guard source.shape == [3, 4, 6, 5] else { fail("rank4 shape \(source.shape)") }
            let cube = try await fullCube(of: source) { try await reader.readScanTile($0, yRange: $1) }
            await exercise(
                "H5 rank-4", source: source, fullCube: cube,
                sourceValue: { Float($0) }, expectedPushdown: .full,
                read: { try await reader.readScanTile($0, yRange: $1) },
                readRow: { try await reader.readScanRow($0, ry: $1) },
                readPattern: { try await reader.readPattern($0, ry: $1, rx: $2) },
                pushdown: reader.loadPushdown(for: LoadView(fullExtentOf: source))
            )
        }

        // ---- HDF5, rank 3 (reshaped to [1, N, Qy, Qx]) ----------------------
        do {
            let reader = try H5Reader(path: root.appendingPathComponent("rank3.h5").path)
            let source = try await reader.discoverPrimaryDataset()
            guard source.shape == [1, 5, 6, 5] else { fail("rank3 shape \(source.shape)") }
            let cube = try await fullCube(of: source) { try await reader.readScanTile($0, yRange: $1) }
            await exercise(
                "H5 rank-3", source: source, fullCube: cube,
                sourceValue: { Float($0) }, expectedPushdown: .full,
                read: { try await reader.readScanTile($0, yRange: $1) },
                readRow: { try await reader.readScanRow($0, ry: $1) },
                readPattern: { try await reader.readPattern($0, ry: $1, rx: $2) },
                pushdown: reader.loadPushdown(for: LoadView(fullExtentOf: source))
            )
        }

        // ---- DM4 -----------------------------------------------------------
        do {
            let reader = try await DM4Reader(path: root.appendingPathComponent("cube.dm4").path)
            let source = try await reader.discoverPrimaryDataset()
            guard source.shape == [3, 4, 6, 5] else { fail("dm4 shape \(source.shape)") }
            let cube = try await fullCube(of: source) { try await reader.readScanTile($0, yRange: $1) }
            await exercise(
                "DM4", source: source, fullCube: cube,
                sourceValue: { Float($0) }, expectedPushdown: .scanOnly,
                read: { try await reader.readScanTile($0, yRange: $1) },
                readRow: { try await reader.readScanRow($0, ry: $1) },
                readPattern: { try await reader.readPattern($0, ry: $1, rx: $2) },
                pushdown: reader.loadPushdown(for: LoadView(fullExtentOf: source))
            )
        }

        // ---- EMPAD ---------------------------------------------------------
        do {
            let reader = try EMPADReader(path: root.appendingPathComponent("empad.xml").path)
            let source = try await reader.discoverPrimaryDataset()
            guard source.shape == [3, 4, 128, 128] else { fail("empad shape \(source.shape)") }
            let cube = try await fullCube(of: source) { try await reader.readScanTile($0, yRange: $1) }
            await exercise(
                // reference.py writes frame * 128 * 128 + (row * 128 + column), which is
                // the flat source index — and the two footer rows are negative, so a
                // read that leaked into them shows up here too.
                "EMPAD", source: source, fullCube: cube,
                sourceValue: { Float($0) }, expectedPushdown: .scanOnly,
                read: { try await reader.readScanTile($0, yRange: $1) },
                readRow: { try await reader.readScanRow($0, ry: $1) },
                readPattern: { try await reader.readPattern($0, ry: $1, rx: $2) },
                pushdown: reader.loadPushdown(for: LoadView(fullExtentOf: source))
            )
        }

        // ---- MIB -----------------------------------------------------------
        do {
            let reader = try MIBReader(path: root.appendingPathComponent("merlin.mib").path)
            let source = try await reader.discoverPrimaryDataset()
            guard source.shape == [2, 3, 256, 256] else { fail("mib shape \(source.shape)") }
            let cube = try await fullCube(of: source) { try await reader.readScanTile($0, yRange: $1) }
            await exercise(
                // U16 big-endian, written modulo 65535 by reference.py.
                "MIB", source: source, fullCube: cube,
                sourceValue: { Float($0 % 65535) }, expectedPushdown: .scanOnly,
                read: { try await reader.readScanTile($0, yRange: $1) },
                readRow: { try await reader.readScanRow($0, ry: $1) },
                readPattern: { try await reader.readPattern($0, ry: $1, rx: $2) },
                pushdown: reader.loadPushdown(for: LoadView(fullExtentOf: source))
            )
        }

        // ---- Demo ----------------------------------------------------------
        // The demo source GENERATES its patterns, so it is the one reader that
        // could answer a crop with a differently-centred cube rather than a
        // subset — a fabrication that would look entirely plausible on screen.
        do {
            let reader = DemoFourDDataSource()
            let source = try await reader.discoverPrimaryDataset()
            let cube = try await fullCube(of: source) { try await reader.readScanTile($0, yRange: $1) }
            await exercise(
                // The ONE reader with no independent ground truth: its patterns come from
                // the app's own generator, so there is no "what the fixture wrote" to
                // compare against and the checks below are self-consistency only. What
                // that does not catch is a transformation applied equally to the full
                // and the cropped read. It is covered instead by the control that
                // matters most here — generating from the view descriptor rather than
                // the source, the fabrication this source could plausibly commit — which
                // fails 626 assertions.
                "Demo", source: source, fullCube: cube,
                sourceValue: nil, expectedPushdown: .none,
                read: { try await reader.readScanTile($0, yRange: $1) },
                readRow: { try await reader.readScanRow($0, ry: $1) },
                readPattern: { try await reader.readPattern($0, ry: $1, rx: $2) },
                pushdown: reader.loadPushdown(for: LoadView(fullExtentOf: source))
            )
        }

        // ---- FourDArray carries the view -----------------------------------
        // The array is what the compute layer holds, so the crop has to survive
        // the hop from reader to array — including the resident path, where a
        // buffer filled for one crop must never be served to another.
        do {
            let reader = try H5Reader(path: root.appendingPathComponent("rank4.h5").path)
            let source = try await reader.discoverPrimaryDataset()
            let full = FourDArray(reader: reader, descriptor: source)
            let fullPixels = try await full.scanTile(yRange: 0..<source.ry).pixels

            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 3),
                detectorCrop: AxisCrop(yOffset: 2, xOffset: 1, height: 3, width: 3)
            )
            let view = try LoadView(source: source, specification: specification)
            let cropped = FourDArray(reader: reader, view: view)
            let croppedShape = cropped.descriptor.shape
            check(croppedShape == [2, 3, 3, 3],
                  "FourDArray: cropped descriptor \(croppedShape)")
            let croppedPixels = try await cropped.scanTile(yRange: 0..<2).pixels
            let expected = expectedSlice(fullCube: fullPixels, source: source,
                                         specification: specification, viewRows: 0..<2)
            check(croppedPixels == expected,
                  "FourDArray: cropped tile differs from the slice of the full read")

            // The same numbers must come back out of a resident buffer.
            //
            // `.resident` is requested explicitly: `.automatic` streams while
            // `ResidencyAdmission.measuredWorkingSetFraction` is nil, so leaving
            // the default here would silently test the streaming path twice —
            // the exact way L2's first residency harness was green and wrong.
            await cropped.setResidencyRequest(.resident)
            let admitted = try await cropped.makeResident(maximumRows: 1)
            let isResident = await cropped.isResident
            check(admitted && isResident,
                  "FourDArray: the cropped cube never went resident (admitted \(admitted), resident \(isResident))")
            let residentPixels = try await cropped.scanTile(yRange: 0..<2).pixels
            check(residentPixels == expected,
                  "FourDArray: the resident cropped cube differs from the streamed one")

            // A descriptor that is not this array's view must not be served the
            // buffer — the compute layer builds synthetic descriptors, and one
            // of those reaching the resident fast path would compute a correct
            // number about the wrong extent.
            let strangerBuffer = await cropped.resident(for: source)
            check(strangerBuffer == nil,
                  "FourDArray: the full-extent descriptor was served a cropped buffer")

            // And a *different* crop is a different array with its own (absent)
            // buffer. That is the model — changing the specification reopens —
            // so this asserts the separation rather than a guard inside one
            // array, which could not distinguish two equal-shape crops anyway.
            let otherSpecification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 2, width: 3),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 3, width: 3)
            )
            let otherView = try LoadView(source: source, specification: otherSpecification)
            let other = FourDArray(reader: reader, view: otherView)
            let otherPixels = try await other.scanTile(yRange: 0..<2).pixels
            let otherExpected = expectedSlice(fullCube: fullPixels, source: source,
                                              specification: otherSpecification,
                                              viewRows: 0..<2)
            check(otherPixels == otherExpected,
                  "FourDArray: the second crop read the first crop's pixels")
        }

        if failures.isEmpty {
            print("load-spec-test: all passed")
        } else {
            for message in failures.prefix(40) {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            }
            FileHandle.standardError.write(
                Data("load-spec-test: \(failures.count) failure(s)\n".utf8)
            )
            exit(1)
        }
    }
}
