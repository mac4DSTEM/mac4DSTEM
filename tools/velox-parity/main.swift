import Darwin
import Foundation

// tools/velox-parity — VeloxEMDReader against rosettasciio, count for count (WP1 prediction P1).
//
//   main parity <velox-parity data dir> <truth dir from truth.py>
//   main owner  <owner .emd> <owner truth dir from truth.py owner>        (diagnostic; P2, P3, P4)
//
// Every public Velox file that rsciio reads as a spectrum image is decoded here and compared with
// rsciio's `sum_frames=True` array: every count of the dense cube, the energy axis (as float32),
// the scan image summed over frames. A file rsciio cannot read as an SI must be refused here too.

var failures = 0

func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    if ok { print("  ok    \(message())") } else { failures += 1; print("  FAIL  \(message())") }
}

func loadU32(_ url: URL) throws -> [UInt32] {
    let data = try Data(contentsOf: url, options: .alwaysMapped)
    return data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
}

/// The ONE file whose rsciio shape is knowingly wrong (formats.md §2.2): rsciio takes the grid from
/// the last image group read, a 128 x 128 image, for a 16 x 20 spectrum image. Compared flat.
let knownRsciioShapeDefect: Set<String> = ["velox_EELS_EDS/example_velox_EELS_EDS.emd"]

func peakRSSMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576   // macOS reports bytes
}

func runParity(dataDir: String, truthDir: String) throws {
    let manifestData = try Data(contentsOf: URL(fileURLWithPath: truthDir + "/manifest.json"))
    guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
          let files = manifest["files"] as? [[String: Any]] else { print("FAIL: unreadable manifest"); exit(1) }
    print("velox-parity: truth is rosettasciio \(manifest["rsciio"] as? String ?? "?")")
    for entry in (manifest["npyChecks"] as? [[String: Any]]) ?? [] {
        check(entry["equal"] as? Bool == true, "comparator check: rsciio equals its shipped \(entry["npy"] as? String ?? "?")")
    }

    var compared = 0
    for entry in files {
        let name = entry["file"] as! String
        let path = dataDir + "/" + name
        let hasStream = entry["stream"] as! Bool
        let cases = entry["cases"] as! [[String: Any]]
        print("== \(name)")
        let detected = VeloxEMDReader.isVeloxEMD(path: path)
        let reader = VeloxEMDReader(path: path)

        // A file rsciio reads no spectrum image from must be refused here, never half-read.
        if !hasStream || cases.contains(where: { $0["error"] != nil }) {
            do {
                _ = try reader.readSpectrumImage()
                check(false, "refused as not a spectrum image (it was read)")
            } catch {
                check(true, "refused as not a spectrum image: \(error.localizedDescription)")
            }
            continue
        }
        check(detected, "isVeloxEMD")

        for c in cases {
            let label = c["label"] as! String
            let shape = (c["shape"] as! [Int])
            let first = c["first"] as! Int
            let last = c["last"] as? Int
            let selection: VeloxFrameSelection = last.map { .range(first..<$0) } ?? .recordedDefault
            let result: VeloxSpectrumImage
            do { result = try reader.readSpectrumImage(frames: selection) } catch {
                check(false, "[\(label)] decode threw: \(error.localizedDescription)"); continue
            }
            let store = result.eventStore
            let g = store.geometry
            let truth = try loadU32(URL(fileURLWithPath: truthDir + "/\(c["tag"] as! String).si.u32"))
            let swift = store.denseCounts()
            let sameShape = [g.ny, g.nx, g.channels] == shape
            if sameShape {
                var wrong = 0
                for i in 0..<truth.count where truth[i] != swift[i] { wrong += 1 }
                check(wrong == 0, "[\(label)] \(g.ny)x\(g.nx)x\(g.channels) counts equal (\(truth.count) cells, \(store.totalCounts) counts, \(wrong) differ)")
            } else if knownRsciioShapeDefect.contains(name) {
                // Flat pixel order: rsciio's first ny*nx pixels are this reader's pixels; the rest must be empty.
                let channels = g.channels
                let cells = g.ny * g.nx * channels
                var wrong = 0
                for i in 0..<cells where truth[i] != swift[i] { wrong += 1 }
                var stray = 0
                for i in cells..<truth.count where truth[i] != 0 { stray += 1 }
                check(wrong == 0 && stray == 0,
                      "[\(label)] DEVIATION (expected, grid): rsciio \(shape[0])x\(shape[1]) vs \(g.ny)x\(g.nx) here; flat order equal in \(cells) cells (\(wrong) differ), \(stray) stray rsciio counts outside")
            } else {
                check(false, "[\(label)] shape \(g.ny)x\(g.nx)x\(g.channels) here, rsciio \(shape)")
            }
            check(store.outOfRangeValues == 0, "[\(label)] no out-of-range channel values")

            // Energy axis: rsciio's, as Double (the same division, so exact).
            let energy = c["energy"] as! [String: Any]
            if let axis = result.metadata.energyAxis {
                let eo = energy["offsetKeV"] as! Double, es = energy["scaleKeV"] as! Double
                check(axis.offsetKeV == eo && axis.scaleKeV == es,
                      "[\(label)] energy axis offset \(axis.offsetKeV) keV, scale \(axis.scaleKeV) keV (rsciio \(eo), \(es))")
            } else {
                check(false, "[\(label)] energy axis missing")
            }

            // Frame coverage against the stream's own marker count (the default case covers every frame).
            // rsciio's frame count is ceil(markers / pixels) and it stores a trailing pixel with no closing marker,
            // so a stream one marker short of a frame (EELS_EDS: 319 of 320) holds a COMPLETE frame; any other
            // remainder is a partial frame, reported as such.
            if label == "default" {
                let (_, markers) = try reader.streamLengthAndMarkers()
                let pixels = g.ny * g.nx
                let rem = markers % pixels
                let oneShort = rem == pixels - 1
                let expectComplete = markers / pixels + (oneShort ? 1 : 0)
                let expectPartial = oneShort ? 0 : rem
                check(store.completeFrames == expectComplete && store.partialFramePixels == expectPartial,
                      "[\(label)] frames: \(store.completeFrames) complete + \(store.partialFramePixels) partial pixels (\(markers) pixel ends over \(pixels) pixels: expect \(expectComplete) + \(expectPartial))")
                check(store.completeFrames + (store.partialFramePixels > 0 ? 1 : 0) == (markers + pixels - 1) / pixels,
                      "[\(label)] frame count equals rsciio's ceil(markers / pixels) = \((markers + pixels - 1) / pixels)")
            }

            // Scan image: rsciio sums nothing by frame range, so only the default case compares it.
            if label == "default" {
                if let image = result.scanImage {
                    let truthImages = c["images"] as! [[String: Any]]
                    var matched: String?
                    for t in truthImages {
                        let ts = t["shape"] as! [Int]
                        guard ts == [image.ny, image.nx] else { continue }
                        let values = try loadU32(URL(fileURLWithPath: truthDir + "/" + (t["file"] as! String)))
                        if values == image.sum { matched = t["title"] as? String; break }
                    }
                    check(matched != nil, "[\(label)] scan image '\(image.detectorName)' (\(image.framesSummed) frames) equals rsciio's '\(matched ?? "none")'")
                    if image.detectorName.uppercased().contains("HAADF") {
                        check(matched == "HAADF", "[\(label)] the HAADF detector's image is the one rsciio titles HAADF")
                    }
                } else {
                    check(false, "[\(label)] no scan image on the spectrum grid")
                }
            }
            compared += 1
        }

        // The per-frame ScanTransformation, which Velox writes as FLAT dotted keys: every frame (metadata column)
        // of every SI file must yield one. fei_emd_si.emd frame 4 is also pinned (the reviewer's independent read: A13 -6.35e-5).
        let transformations = try reader.readFrameTransformations()
        check(!transformations.isEmpty && transformations.allSatisfy { $0 != nil }, "ScanTransformation read for all \(transformations.count) frames")
        if name.hasSuffix("fei_emd_si.emd"), transformations.count == 5, let t = transformations[4] {
            check(abs(t.a13 - (-6.35e-5)) < 1e-6, "fei_emd_si frame 4 ScanTransformation A13 = \(t.a13) (expect about -6.35e-5)")
        } else if name.hasSuffix("fei_emd_si.emd") {
            check(false, "fei_emd_si.emd frame 4 ScanTransformation missing")
        }
    }
    print("velox-parity: \(compared) cases compared, \(failures) failures")
}

func runOwner(path: String, truthDir: String) throws {
    let truthData = try Data(contentsOf: URL(fileURLWithPath: truthDir + "/owner.json"))
    let truth = try JSONSerialization.jsonObject(with: truthData) as! [String: Any]
    let reader = VeloxEMDReader(path: path)
    print("owner file: \(displayFileName(path))")

    // P2: pixel ends per frame.
    if let perFrame = try reader.markersPerFrame() {
        let distinct = Set(perFrame)
        print("P2 markers per frame window: \(perFrame.count) frames, distinct values \(distinct.sorted().prefix(5)), first \(perFrame[0]), last \(perFrame.last!)")
        print("P2 926*215 = \(926 * 215); 1024*1024 = \(1024 * 1024)")
    }
    let (values, markers) = try reader.streamLengthAndMarkers()
    print("stream values \(values), markers \(markers), events \(values - markers)")

    // P3: decode time and store size.
    let t0 = Date()
    let result = try reader.readSpectrumImage()
    let seconds = Date().timeIntervalSince(t0)
    let store = result.eventStore
    let g = store.geometry
    let denseBytes = Double(g.ny * g.nx * g.channels) * 4
    print(String(format: "P3 decode %.2f s (open to store, incl. HAADF %d frames); peak RSS %.0f MB", seconds,
                 result.scanImage?.framesSummed ?? 0, peakRSSMB()))
    print(String(format: "P3 grid %dx%d, %d channels; event store %.1f MB = %.2f%% of the dense %.0f MB; %d distinct entries, %d counts",
                 g.ny, g.nx, g.channels, Double(store.storageBytes) / 1e6, 100 * Double(store.storageBytes) / denseBytes,
                 denseBytes / 1e6, store.distinctEntries, store.totalCounts))
    print("frames summed \(store.frameRange), complete \(store.completeFrames), partial pixels \(store.partialFramePixels), out-of-range \(store.outOfRangeValues), streams \(result.streamCount)")
    let transformations = try reader.readFrameTransformations()
    if let last = transformations.last, let t = last {
        check(abs(t.a13 - 0.0149) < 5e-4 && abs(t.a23 - 0.120) < 5e-3,
              "ScanTransformation of frame \(transformations.count - 1): A13 \(t.a13), A23 \(t.a23) (reviewer: about 0.0149, 0.120)")
    } else { check(false, "owner file: last frame has no ScanTransformation") }
    print("streams: \(result.streams.map { "\($0.id.prefix(6)) \($0.detectorName ?? "?") -> \($0.segments.map(\.name))" }); energy calibration agrees: \(result.energyCalibrationAgrees)")
    if let axis = result.metadata.energyAxis { print("energy axis offset \(axis.offsetKeV) keV, scale \(axis.scaleKeV) keV/channel") }

    // P4: totals.
    check(store.totalCounts == values - markers, "P4 total counts \(store.totalCounts) equal stream values - markers \(values - markers)")
    let rsciioTotal = truth["total"] as! Int
    check(store.totalCounts == rsciioTotal, "P4 total counts equal rsciio's total \(rsciioTotal)")

    // Count for count against rsciio: per-pixel sums, per-channel sums, and the number of non-empty cells.
    let pixelTruth = try loadU32(URL(fileURLWithPath: truthDir + "/owner.pixel.u32"))
    let channelTruth = try loadU32(URL(fileURLWithPath: truthDir + "/owner.channel.u32"))
    var pixelWrong = 0
    for p in 0..<store.pixelCount {
        var s = 0
        for k in store.rowOffsets[p]..<store.rowOffsets[p + 1] { s += Int(store.counts[k]) }
        if p >= pixelTruth.count || UInt32(truncatingIfNeeded: s) != pixelTruth[p] { pixelWrong += 1 }
    }
    check(pixelTruth.count == store.pixelCount && pixelWrong == 0, "per-pixel totals equal rsciio's (\(pixelWrong) of \(store.pixelCount) differ)")
    let channels = store.summedSpectrum()
    var channelWrong = 0
    for c in 0..<g.channels where UInt32(truncatingIfNeeded: channels[c]) != channelTruth[c] { channelWrong += 1 }
    check(channelWrong == 0, "summed spectrum equals rsciio's (\(channelWrong) of \(g.channels) channels differ)")
    check(store.distinctEntries == truth["nonzero"] as! Int, "non-empty (pixel, channel) cells \(store.distinctEntries) equal rsciio's \(truth["nonzero"] as! Int)")
    let rg = truth["shape"] as! [Int]
    check([g.ny, g.nx, g.channels] == rg, "grid \(g.ny)x\(g.nx)x\(g.channels) equals rsciio's \(rg)")
}

@main struct VeloxParityHarness {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 4 else { print("usage: main parity <data dir> <truth dir> | owner <emd> <truth dir>"); exit(2) }
        do {
            switch args[1] {
            case "parity": try runParity(dataDir: args[2], truthDir: args[3])
            case "owner": try runOwner(path: args[2], truthDir: args[3])
            default: print("unknown mode \(args[1])"); exit(2)
            }
        } catch {
            print("FAIL: \(error.localizedDescription)"); exit(1)
        }
        if failures > 0 { print("velox-parity: \(failures) FAILURES"); exit(1) }
        print("velox-parity: all passed")
    }
}
