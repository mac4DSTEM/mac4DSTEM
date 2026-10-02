//
//  tools/hdf5-exit-race-test/main.swift
//  Quitting while HDF5 is busy (Slot 4¾ review, 2026-10-02).
//
//  The bundled libhdf5 is built Threadsafety OFF; every app entry runs under
//  `HDF5Serial` (Core/Data/HDF5Types.swift). `exit()` — what a Quit ends in —
//  runs HDF5's own atexit handler, H5_term_library, which takes no app lock:
//  before the quit barrier, a Task still inside H5Dread on another thread
//  raced the teardown and the process died at quit. The barrier is one atexit
//  handler, registered right after the first successful H5open, that takes
//  `HDF5Serial` and never gives it back; atexit runs LIFO, so it runs before
//  HDF5's handler (registered inside that first H5open): the in-flight call
//  finishes, then HDF5 tears down with no other thread able to enter.
//
//  THREE MODES (run.sh drives them; a crash is read from the exit status):
//    make  <cube.h5>             writes a small synthetic float32 cube with the
//                                app's own exporter (DemoFourDDataSource source)
//    order <cube.h5>             deterministic: an H5atclose callback, which
//                                HDF5 calls as H5_term_library starts, reports
//                                whether HDF5Serial is held at that moment
//    race  <cube.h5> <delay-ms>  a detached Task loops H5Reader.readPattern
//                                while the main thread calls exit(0)
//

import Foundation

nonisolated(unsafe) private var keepAlive: [Any] = []

nonisolated private func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

/// Called by HDF5 at the start of H5_term_library, on the exiting thread. A
/// second thread tries `HDF5Serial`: if the quit barrier already took it, the
/// try blocks and the wait times out.
nonisolated private func reportLockAtTeardown(_ context: UnsafeMutableRawPointer?) {
    let entered = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        HDF5Serial.run {}
        entered.signal()
    }
    let held = entered.wait(timeout: .now() + .milliseconds(500)) == .timedOut
    say("order: HDF5Serial held when HDF5 tears down = \(held ? "yes" : "no")")
}

@main
enum Probe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            say("usage: probe make|order|race <cube.h5> [delay-ms]")
            exit(2)
        }
        switch args[0] {
        case "make": await make(args[1])
        case "order": order(args[1])
        case "race": await race(args[1], delayMs: args.count > 2 ? Int(args[2]) ?? 80 : 80)
        default:
            say("unknown mode \(args[0])")
            exit(2)
        }
    }

    static func make(_ path: String) async {
        do {
            let source = DemoFourDDataSource(includesCalibration: false)
            let descriptor = try await source.discoverPrimaryDataset()
            let options = CalibratedDataCubeExportOptions(scanY: 0..<descriptor.ry,
                                                          scanX: 0..<descriptor.rx, tileRows: 4)
            let summary = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                source: source, view: LoadView(fullExtentOf: descriptor),
                calibration: PixelCalibration(), options: options,
                to: URL(fileURLWithPath: path))
            say("make: wrote \(summary)")
        } catch {
            say("make: failed: \(error)")
            exit(3)
        }
        exit(0)
    }

    static func order(_ path: String) {
        let reader: H5Reader
        do { reader = try H5Reader(path: path) } catch {
            say("order: cannot open \(path): \(error)")
            exit(3)
        }
        keepAlive.append(reader)
        typealias AtClose = @convention(c) (
            @convention(c) (UnsafeMutableRawPointer?) -> Void, UnsafeMutableRawPointer?
        ) -> Int32
        guard let library = ProcessInfo.processInfo.environment["MAC4DSTEM_HDF5_PATH"],
              let handle = dlopen(library, RTLD_NOW | RTLD_NOLOAD),
              let symbol = dlsym(handle, "H5atclose") else {
            say("order: H5atclose not found in the loaded libhdf5")
            exit(3)
        }
        let atclose = unsafeBitCast(symbol, to: AtClose.self)
        guard HDF5Serial.run({ atclose(reportLockAtTeardown, nil) }) >= 0 else {
            say("order: H5atclose refused the callback")
            exit(3)
        }
        say("order: calling exit(0)")
        exit(0)
    }

    static func race(_ path: String, delayMs: Int) async {
        let reader: H5Reader
        let descriptor: DatasetDescriptor
        do {
            reader = try H5Reader(path: path)
            descriptor = try await reader.discoverPrimaryDataset()
        } catch {
            say("race: cannot open \(path): \(error)")
            exit(3)
        }
        keepAlive.append(reader)
        let view = LoadView(fullExtentOf: descriptor)
        let (ry, rx) = (descriptor.ry, descriptor.rx)
        Task.detached {
            var index = 0
            while true {
                _ = try? await reader.readPattern(view, ry: index % ry, rx: (index / ry) % rx)
                index += 1
            }
        }
        try? await Task.sleep(nanoseconds: UInt64(max(delayMs, 0)) * 1_000_000)
        exit(0)
    }
}
