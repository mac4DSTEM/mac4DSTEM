//
//  residency-sweep
//  Measures the residency knee required by docs/load-pipeline-plan.md L2.3:
//  the fraction `f` of this machine's own Metal working set that a cube may
//  occupy before holding it stops paying.
//
//  WHY THIS EXISTS AT ALL. Getting `f` wrong does not throw. Metal pages, and
//  the app becomes SLOWER than tiled while appearing to succeed — the worst
//  regression class this app produces. So `f` is measured, never reasoned:
//  `ResidencyAdmission.measuredWorkingSetFraction` stays nil until a run of
//  this tool says otherwise. `.automatic` — the mode that consulted it — was
//  dropped for v2 (owner decision 2026-08-18); this sweep, run on a second
//  machine, is what could bring it back (docs/v2-release.md §3).
//
//  THE METHOD, and why one file is enough. A ratio is cube bytes ÷ working set,
//  and the cube's byte count is a function of its scan extent — so truncating
//  the scan axis synthesizes a whole sweep of ratios out of a single real file,
//  with real data, real chunking and real I/O. `readScanTile` is given a
//  descriptor whose `ry` is smaller than the file's; every read is then a valid
//  sub-read of rows 0..<n. Two separate cubes either side of the knee (the
//  approach L2.3 sketches) measure two points; this measures the curve.
//
//  DEVIATION from L2.3's wording, which says to extend tools/performance-baseline.
//  That harness is an argument-free synthetic benchmark that prints one JSON
//  document and is wired into `run-tests.sh benchmark`; this one needs a real
//  multi-gigabyte file, an HDF5 reader and a path argument, and must never
//  gate. Same precedent as tools/bragg-spacing-probe, which is a diagnostic for
//  exactly the same reason.
//
//  RUN IT ON LOCAL STORAGE. #30 measured ≈3.3 MB/s over a NAS, which is
//  latency-dominated and ~30x below gigabit: a sweep over a network mount
//  measures the link, not residency. The tool refuses to guess about this — it
//  reports the achieved preload throughput so a suspiciously slow run is
//  visible in the output rather than silently becoming the answer.
//

import Foundation
import Metal

// Unbuffered: a sweep can run for minutes and can die inside a large
// allocation, and block-buffered stdout redirected to a file loses every line
// it had not flushed — which turns "it crashed at ratio 0.40" into "no output".
setvbuf(stdout, nil, _IONBF, 0)

struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(1)
}

func milliseconds(_ body: () async throws -> Void) async rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try await body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 0
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle]
}

func byteString(_ bytes: Int) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return gb >= 1 ? String(format: "%.2f GB", gb)
        : String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("""
         usage: residency-sweep <file.h5> [repeats]

         Measures the fraction of this machine's Metal working set at which
         holding the cube in memory stops paying. Copy the dataset to local
         storage first — a sweep over a network mount measures the link.
         """)
}
let path = arguments[1]
let repeats = arguments.count > 2 ? max(1, Int(arguments[2]) ?? 5) : 5
guard FileManager.default.fileExists(atPath: path) else {
    fail("no such file: \(path)")
}

let device = MetalEngine.shared.device
let workingSet = Int(device.recommendedMaxWorkingSetSize)

let reader = try H5Reader(path: path)
let full = try await reader.discoverPrimaryDataset()
guard full.is4D else { fail("not a 4D dataset: \(full.shapeString)") }

let bytesPerScanRow = full.rx * full.qy * full.qx * MemoryLayout<Float>.stride
guard bytesPerScanRow > 0 else { fail("degenerate scan row") }

print("# residency sweep")
print("file          \(full.fileName)  \(full.shapeString)  \(full.dtypeDescription)")
print("cube (f32)    \(byteString(full.byteCountAsFloat32))")
print("GPU           \(device.name)")
print("working set   \(byteString(workingSet))")
print("full ratio    \(String(format: "%.2f", Double(full.byteCountAsFloat32) / Double(workingSet)))")
print("repeats       \(repeats)")
print("")

// The ratios worth probing. Above ~0.9 the buffer competes with everything else
// the GPU needs; below ~0.1 residency is uninteresting because everything fits.
let ratios: [Double] = [0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90]

struct Row {
    /// The ratio actually achieved — bytes ÷ working set — NOT the one asked
    /// for. They diverge as soon as truncation is clamped by the file's own
    /// extent, and a row labelled 0.20 that is really 0.11 would be a fabricated
    /// data point in the one output this threshold gets chosen from.
    let ratio: Double
    let requestedRatio: Double
    let rows: Int
    let bytes: Int
    let preloadMilliseconds: Double
    /// The FIRST dispatch after the preload, untouched by any warm-up. Paging is
    /// a first-touch cost, so this is the only sample that can see it.
    let coldMilliseconds: Double
    let residentMilliseconds: Double
    let streamedMilliseconds: Double
    var speedup: Double { streamedMilliseconds / residentMilliseconds }
    var preloadMBPerSecond: Double {
        Double(bytes) / 1_048_576 / (preloadMilliseconds / 1000)
    }
    /// Flat while the buffer is genuinely resident; climbs when it pages.
    var coldNanosecondsPerMB: Double {
        coldMilliseconds * 1_000_000 / (Double(bytes) / 1_048_576)
    }
}

var rows: [Row] = []

for ratio in ratios {
    let targetBytes = Double(workingSet) * ratio
    let scanRows = min(full.ry, max(1, Int(targetBytes / Double(bytesPerScanRow))))
    // Once truncation is clamped by the file's own extent, every larger ratio
    // would measure the identical cube. Stop rather than print duplicates.
    if let previous = rows.last, previous.rows == scanRows {
        print("(ratio \(String(format: "%.2f", ratio)) needs more scan rows than the file has — stopping)")
        break
    }
    let truncated = DatasetDescriptor(
        filePath: full.filePath, datasetPath: full.datasetPath,
        shape: [scanRows, full.rx, full.qy, full.qx],
        dtypeDescription: full.dtypeDescription, chunkShape: full.chunkShape
    )
    let shape = DetectorShape.annulus(
        centerX: Float(truncated.qx) / 2, centerY: Float(truncated.qy) / 2,
        inner: Float(min(truncated.qx, truncated.qy)) / 8,
        outer: Float(min(truncated.qx, truncated.qy)) / 4
    )

    // Streaming first, so the resident run cannot be handed a warm page cache
    // that the streaming run paid for.
    let streamed = FourDArray(reader: reader, descriptor: truncated)
    // One untimed pass per mode. Without it the FIRST ratio measured absorbs
    // pipeline-state creation and page-cache warming for the whole run, which
    // showed up as a resident time that FELL from 18.2 ms to 9.6 ms as the cube
    // got bigger — a physically impossible trend that would have been read as
    // data.
    _ = try await VirtualDetector.tiledImage(
        data: streamed, descriptor: truncated, shape: shape
    )
    var streamedSamples: [Double] = []
    for _ in 0..<repeats {
        streamedSamples.append(try await milliseconds {
            _ = try await VirtualDetector.tiledImage(
                data: streamed, descriptor: truncated, shape: shape
            )
        })
    }

    let resident = FourDArray(reader: reader, descriptor: truncated)
    await resident.setResidencyRequest(.resident)
    let preload = try await milliseconds {
        let held = try await resident.makeResident()
        guard held else {
            fail("""
                 could not hold \(byteString(truncated.byteCountAsFloat32)) at ratio \
                 \(String(format: "%.2f", ratio)). An explicit .resident request is \
                 not threshold-gated, so this is an allocation failure, and the \
                 sweep cannot continue past it.
                 """)
        }
    }
    // COLD FIRST — before any warm-up touches the pages. This is the sample the
    // knee is read from; the warm median below is kept only for the speedup
    // column, which is a rough indicator and not a criterion.
    let cold = try await milliseconds {
        _ = try await VirtualDetector.tiledImage(
            data: resident, descriptor: truncated, shape: shape
        )
    }
    var residentSamples: [Double] = []
    for _ in 0..<repeats {
        residentSamples.append(try await milliseconds {
            _ = try await VirtualDetector.tiledImage(
                data: resident, descriptor: truncated, shape: shape
            )
        })
    }
    await resident.releaseResident()

    let row = Row(
        ratio: Double(truncated.byteCountAsFloat32) / Double(workingSet),
        requestedRatio: ratio,
        rows: scanRows, bytes: truncated.byteCountAsFloat32,
        preloadMilliseconds: preload,
        coldMilliseconds: cold,
        residentMilliseconds: median(residentSamples),
        streamedMilliseconds: median(streamedSamples)
    )
    rows.append(row)
    // NOTE: no `%s` here. String(format:) treats %s as a C string pointer, so
    // passing a Swift String or NSString to it segfaults — which is exactly how
    // this tool first died, after completing every measurement it was asked for.
    func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }
    let clamped = abs(row.ratio - row.requestedRatio) > 0.005
        ? " (asked \(String(format: "%.2f", row.requestedRatio)), clamped by the file)"
        : ""
    print(
        "ratio \(String(format: "%.2f", row.ratio))"
        + "  rows \(pad("\(row.rows)", 5))"
        + "  \(pad(byteString(row.bytes), 10))"
        + "  preload \(pad(String(format: "%.0f", row.preloadMilliseconds), 8)) ms"
        + " (\(pad(String(format: "%.0f", row.preloadMBPerSecond), 6)) MB/s)"
        + "  resident \(pad(String(format: "%.1f", row.residentMilliseconds), 8)) ms"
        + "  streamed \(pad(String(format: "%.1f", row.streamedMilliseconds), 8)) ms"
        + "  speedup \(String(format: "%.2f", row.speedup))x"
        + clamped
    )
}

// MARK: - The knee

print("")
guard !rows.isEmpty else { fail("no ratios were measured") }

// WHAT THE KNEE IS, AND WHAT IT IS NOT.
//
// The first version of this tool ranked ratios by `streamed / resident` and
// called the largest ratio above 1.1x the knee. That criterion cannot fail.
// The streaming comparand pays disk I/O, a per-tile memcpy and a per-tile
// MTLBuffer allocation; the resident comparand is a bare GPU dispatch. The
// ratio is therefore monotone in cube size and stays far above 1.1x right up
// to the swap cliff — so the tool would have recommended an `f` from whatever
// the largest cube it was handed happened to be. That is a gate widened by
// measurement design, which is invariant I7. Adversarial review, 2026-08-17.
//
// The signal that actually locates the cliff is the RESIDENT dispatch cost per
// byte. A resident dispatch reads the whole buffer once, so while everything is
// truly resident, time scales linearly with cube size and ns/MB stays flat.
// When the buffer starts paging, ns/MB climbs — that inflection IS the knee,
// and it is visible without reference to streaming at all.
//
// It is measured from `coldMilliseconds`, the FIRST dispatch after the preload,
// not the median of repeats. Paging is a first-touch cost; a warm-up pass
// followed by a median is the one protocol guaranteed to hide it.
// THE TRIGGER IS AN ORDER OF MAGNITUDE, AND THE BASELINE IS A RUNNING MEDIAN.
//
// The previous version used `min()` as the baseline and fired at 1.5x. Both
// were wrong, and the first real run said so: the smallest cube (530 MB) sits
// in cache and is an unrepresentatively fast baseline, so every larger ratio
// read as ">=1.5x" and the tool called the knee at the second row — while the
// ACTUAL cliff, 707 ms -> 39,531 ms, sat five rows further down and was ignored.
// A criterion that fires on the first row after the fastest one is not
// measuring paging, it is measuring cache.
//
// A running median over the preceding rows is robust to that outlier, and a
// swap cliff is not subtle: it is one to two ORDERS of magnitude, not 50%.
print("resident cost per byte (the paging signal — flat while truly resident):")
let floorCost = rows.map(\.coldNanosecondsPerMB).min() ?? 1
var cliff: Row?
for (index, row) in rows.enumerated() {
    var marker = ""
    if index >= 2 {
        let prior = median(rows[0..<index].map(\.coldNanosecondsPerMB))
        if row.coldNanosecondsPerMB >= 8 * prior {
            marker = "  <-- CLIFF"
            if cliff == nil { cliff = row }
        }
    }
    print("  ratio \(String(format: "%.2f", row.ratio))"
          + "  cold \(String(format: "%9.1f", row.coldMilliseconds)) ms"
          + "  \(String(format: "%12.1f", row.coldNanosecondsPerMB)) ns/MB"
          + "  \(String(format: "%7.2f", row.coldNanosecondsPerMB / floorCost))x floor\(marker)")
}

print("")
if let knee = cliff, let previous = rows.last(where: { $0.ratio < knee.ratio }) {
    let degradation = previous.coldNanosecondsPerMB / floorCost
    print("""
          CLIFF between ratio \(String(format: "%.2f", previous.ratio)) and \
          \(String(format: "%.2f", knee.ratio)) — cold resident cost per byte \
          jumps \(String(format: "%.0f", knee.coldNanosecondsPerMB / previous.coldNanosecondsPerMB))x. \
          That is the buffer paging, not noise.

          Last ratio below the cliff: \(String(format: "%.2f", previous.ratio)).
          """)
    if degradation >= 2 {
        print("""

              BUT DO NOT PASTE THAT NUMBER IN. At ratio \
              \(String(format: "%.2f", previous.ratio)) the cold cost is already \
              \(String(format: "%.1f", degradation))x the floor, so this machine \
              was degrading well before the cliff — there is a gentle slope and \
              then a wall, not a plateau and then a wall. Pick a ratio from the \
              flat part of the table above, not from the last row before the wall.

              And note what the denominator is doing: `recommendedMaxWorkingSetSize` \
              is a GPU budget hint, not a statement about free RAM. On a machine \
              where it is a large fraction of physical memory, a buffer at a high \
              fraction of it competes with the OS and with this app's own staging \
              copies. An `f` measured here may not transfer to a Mac with a very \
              different RAM-to-working-set ratio, which is exactly what a single \
              fraction is supposed to do. Treat this run as ONE machine's data \
              point and say so wherever the constant is recorded.
              """)
    }
    print("""

          Then update tools/virtual-detector-residency and \
          mac4DSTEMTests/DatasetResidencyTests, which both currently assert that \
          the threshold is unmeasured.
          """)
} else {
    let reached = rows.last?.ratio ?? 0
    print("""
          NO KNEE FOUND — cold resident cost per byte stayed flat through ratio \
          \(String(format: "%.2f", reached)), so nothing here shows the buffer \
          paging. LEAVE measuredWorkingSetFraction NIL.

          This is not a licence to pick an f from the largest ratio that "still \
          paid". It means the cliff is above \(String(format: "%.2f", reached)) \
          and this run did not reach it — use a cube big enough to push the ratio \
          past ~0.8, on local storage. Check the preload MB/s above first: a few \
          tens of MB/s means the run measured the link, not residency (#30).
          """)
}
