//
//  tools/hdf5-race-probe/main.swift
//  Reproduction harness for docs/open-items.md, "HDF5 is entered from two
//  unserialised paths, and a second window is not the worst of it"
//  (sharpened 2026-09-15).
//
//  WHAT THIS MEASURES. The bundled libhdf5 is built Threadsafety OFF.
//  `H5Reader` (Core/Data/H5Reader.swift) is a `package actor` that only
//  serialises calls made through ONE instance; `BraggVectorEMDWriter`
//  (Core/Data/BraggVectorEMDWriter.swift) is a `nonisolated enum` whose every
//  static method opens the library itself via a separate `dlopen`
//  (`HDF5WriteLibrary.load()`, :2764) and is guarded by nothing at all. Both
//  resolve to the same process image and the same non-thread-safe library. A
//  2026-08-19 lldb session reproduced `EXC_BAD_ACCESS` in `H5SL_search` within
//  a few dozen iterations of driving both paths at once, but nothing runnable
//  from that session was checked in — so the refactor the docs name twice
//  ("the real fix is one actor owning the library handle",
//  App/mac4DSTEMApp.swift:64 and
//  mac4DSTEMTests/DatasetLoadCancellationTests.swift:141; recorded again in
//  docs/decisions.md 2026-09-15) has had nothing to fail against. This
//  harness is that reproduction.
//
//  It is a NEW directory because nothing in tools/ already drives both HDF5
//  entry points at once: the reader tests exercise `H5Reader` against fakes,
//  and no existing runner touches `BraggVectorEMDWriter`'s real dlopen'd
//  library concurrently with a real `H5Reader`.
//
//  THIS IS DIAGNOSTIC, NOT GATED, AND MAY CRASH BY DESIGN. It measures
//  whether concurrent use of the two paths crashes the process; it asserts
//  nothing and there is no pass/fail. A crash is the observation, reported by
//  run.sh from the process exit status/signal, not from anything printed
//  here (a crash may print nothing).
//
//  TWO MODES:
//   - concurrent (default): the reader loop and the writer-path loop run at
//     the same time, in two Tasks.
//   - `--serial`: the same two loops run one after another. This is the
//     control — if serial completes cleanly and concurrent crashes, the race
//     is reproduced; if both crash, something else is wrong and the
//     concurrency story is not the (sole) explanation.
//
//  USAGE: probe [--serial] <cube.h5> <sidecar.mac4dstem.h5> [iterations=200]
//

import Foundation

@main
enum Probe {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let serial = args.contains("--serial")
        args.removeAll { $0 == "--serial" }

        guard args.count >= 2 else {
            print("usage: probe [--serial] <cube.h5> <sidecar.mac4dstem.h5> [iterations=200]")
            exit(2)
        }
        let cubePath = args[0]
        let sidecarURL = URL(fileURLWithPath: args[1])
        let iterations = args.count > 2 ? (Int(args[2]) ?? 200) : 200
        guard iterations > 0 else {
            print("iterations must be positive"); exit(2)
        }

        guard let reader = try? H5Reader(path: cubePath) else {
            print("could not open \(cubePath) as an H5Reader"); exit(1)
        }
        guard let primary = try? await reader.discoverPrimaryDataset() else {
            print("could not discover a primary dataset in \(cubePath)"); exit(1)
        }
        let view = LoadView(fullExtentOf: primary)
        print("cube: ry=\(primary.ry) rx=\(primary.rx) qy=\(primary.qy) qx=\(primary.qx)")
        print("sidecar: \(sidecarURL.path)")
        print("iterations: \(iterations), mode: \(serial ? "serial" : "concurrent")")

        // The READER path: `H5Reader.readPattern`, an actor-isolated call
        // that serialises against other calls on THIS instance only. Walks
        // the scan so it is not reading the same cached position every time.
        func readerLoop() async -> Int {
            var completed = 0
            for i in 0..<iterations {
                let ry = i % max(1, primary.ry)
                let rx = (i / max(1, primary.ry)) % max(1, primary.rx)
                guard (try? await reader.readPattern(view, ry: ry, rx: rx)) != nil else { continue }
                completed += 1
                if completed % 20 == 0 { print(".", terminator: ""); fflush(stdout) }
            }
            return completed
        }

        // The WRITER path: `BraggVectorEMDWriter.loadInventory`, a
        // `nonisolated static` call that opens the sidecar through
        // `HDF5WriteLibrary.load()` — its own `dlopen`, no actor, no guard.
        // Chosen over `loadResultMap`/`loadRGBAResultMap` because it needs
        // nothing about the sidecar's contents beyond the file existing and
        // carrying the session root group: it reads the inventory only, so
        // it exercises the writer's HDF5 entry point on the smallest
        // dependency.
        // Two writer entry points, alternating: `loadInventory` (through the
        // locked `loadSession`) and `loadRGBAResultMap(id:)` / `loadResultMap(id:)`,
        // which open the file THEMSELVES — Gate B (2026-09-15 late night)
        // found them unlocked and crashing while the inventory path already
        // completed, so a probe that drove only the inventory said nothing
        // about them. The id is whatever result the sidecar lists first;
        // a kind mismatch returns nil and still opened the file.
        nonisolated func writerLoop() -> Int {
            var completed = 0
            let firstResultID = (try? BraggVectorEMDWriter.loadInventory(from: sidecarURL))?.results.first?.id
            for iteration in 0..<iterations {
                let ok: Bool
                switch iteration % 3 {
                case 0: ok = (try? BraggVectorEMDWriter.loadInventory(from: sidecarURL)) != nil
                case 1: ok = firstResultID.map { (try? BraggVectorEMDWriter.loadRGBAResultMap(id: $0, from: sidecarURL)) != nil } ?? false
                default: ok = firstResultID.map { (try? BraggVectorEMDWriter.loadResultMap(id: $0, from: sidecarURL)) != nil } ?? false
                }
                guard ok || iteration % 3 != 0 else { continue }
                completed += 1
                if completed % 20 == 0 { print(",", terminator: ""); fflush(stdout) }
            }
            return completed
        }

        let readerCompleted: Int
        let writerCompleted: Int
        if serial {
            readerCompleted = await readerLoop()
            writerCompleted = writerLoop()
        } else {
            async let r = readerLoop()
            let writerTask = Task.detached { writerLoop() }
            readerCompleted = await r
            writerCompleted = await writerTask.value
        }

        print("")
        print("completed \(readerCompleted) reader reads and \(writerCompleted) "
              + "writer-path calls without a crash")
        exit(0)
    }
}
