//
//  friedel-timing.swift — Gate D instrument for the Friedel ETA that only
//  grows (docs/open-items.md, S3; drive 2, 2026-09-29: 329 → 106 positions/s
//  over 12 000 positions on Thronsen A, ≈ 20 s stalls, Cancel ≈ 20 s late).
//
//  Pass A times the app's own tile reads alone (`FourDArray.scanTile`, the
//  exact call `friedelMeasuredOrigins` awaits) with the footprint after each.
//  Pass B runs `OriginCalibration.tiledRun(originMethod: .friedel)` on a fresh
//  reader and logs, at each 1 % of the origin phase: elapsed, positions done,
//  the cumulative and the trailing rate, and `phys_footprint`. It measures; it
//  asserts nothing.
//
//  Usage (via run.sh): friedel-timing <file.h5> [--tile-rows N]
//

import Darwin
import Foundation

private func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

private final class Timeline: @unchecked Sendable {
    private let lock = NSLock()
    private let start = Date()
    private let positions: Int
    private var lastPercent = -1
    private var samples: [(t: Double, done: Double)] = []

    init(positions: Int) { self.positions = positions }

    /// `tiledRun` maps the origin phase to 0.35…0.90 of its progress.
    func record(_ fraction: Double) {
        guard fraction >= 0.35, fraction <= 0.9 else { return }
        let phase = (fraction - 0.35) / 0.55
        let percent = Int(phase * 100)
        lock.lock(); defer { lock.unlock() }
        guard percent > lastPercent else { return }
        lastPercent = percent
        let t = Date().timeIntervalSince(start)
        let done = phase * Double(positions)
        samples.append((t, done))
        let first = samples.first!
        let trailing = samples.count > 5 ? samples[samples.count - 6] : first
        let cumulative = t > first.t ? (done - first.done) / (t - first.t) : .nan
        let recent = t > trailing.t ? (done - trailing.done) / (t - trailing.t) : .nan
        print(String(format: "  %3d %%  t %7.1f s  done %6.0f  cumulative %6.1f/s  trailing %6.1f/s  footprint %6.0f MB",
                     percent, t, done, cumulative, recent, footprintMB()))
    }
}

@main
struct FriedelTiming {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("usage: friedel-timing <file.h5> [--tile-rows N]"); exit(64) }
        let path = args[1]
        let tileRows = args.firstIndex(of: "--tile-rows").flatMap { Int(args[$0 + 1]) }

        let readerA = try H5Reader(path: path)
        let d = try await readerA.discoverPrimaryDataset()
        let dataA = FourDArray(reader: readerA, descriptor: d)
        let rows = await dataA.scanTileRows(maximumRows: tileRows)
        print("cube: \(URL(fileURLWithPath: path).lastPathComponent)  scan \(d.ry)×\(d.rx)  detector \(d.qy)×\(d.qx)  tile \(rows) rows (\(rows * d.rx) patterns)  footprint \(Int(footprintMB())) MB")

        print("Pass A — the app's tile reads alone:")
        var readTotal = 0.0
        for y in stride(from: 0, to: d.ry, by: rows) {
            let range = y..<min(d.ry, y + rows)
            let t0 = Date()
            let tile = try await dataA.scanTile(yRange: range)
            let dt = Date().timeIntervalSince(t0)
            readTotal += dt
            print(String(format: "  rows %3d–%3d  %6.2f s  %7.0f patterns/s  %d floats  footprint %6.0f MB",
                         range.lowerBound, range.upperBound - 1, dt, Double(range.count * d.rx) / dt,
                         tile.pixels.count, footprintMB()))
        }
        print(String(format: "  all reads: %.1f s = %.0f patterns/s", readTotal, Double(d.ry * d.rx) / readTotal))

        print("Pass B — tiledRun(.friedel) on a fresh reader:")
        let readerB = try H5Reader(path: path)
        let dataB = FourDArray(reader: readerB, descriptor: d)
        let timeline = Timeline(positions: d.ry * d.rx)
        let t0 = Date()
        let result = try await OriginCalibration.tiledRun(
            data: dataB, descriptor: d, fitFunction: .plane, originMethod: .friedel,
            maximumTileRows: tileRows, progress: { timeline.record($0) })
        print(String(format: "  total %.1f s, probe radius %.2f px, footprint %.0f MB",
                     Date().timeIntervalSince(t0), result?.probeRadius ?? .nan, footprintMB()))
    }
}
