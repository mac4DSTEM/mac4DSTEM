//
//  tools/dm4-parity-probe/main.swift
//  Plan C of docs/archive/v4/almgsi-gateD-2026-09-24.md's follow-up
//  (owner, 2026-09-24): can mac4DSTEM preprocess the owner's raw DM4 itself?
//
//  `diagnostic`: it needs the owner's 28 GB raw file on an external volume.
//
//  Modes:
//    --open-only RAW.dm4
//        Open the file through `DM4Reader`, report resident memory after the
//        open and after reading a few patterns. With `.mappedIfSafe` an
//        external volume falls back to a full read into anonymous memory
//        (open-items "DM4Reader silently reads whole files into RAM off
//        non-local volumes"); run it under run.sh's RSS watchdog.
//    --parity RAW.dm4 PREPROCESSED.h5 [--bin 4] [--stride N]
//        Every (stride-th) scan position of the raw file, binned by the app's
//        own `LoadView` (sum, like py4DSTEM `bin_Q`), against the same
//        position of the py4DSTEM-preprocessed file read by the app's
//        `H5Reader`. Reports max |Δ|, max relative Δ, and the transpose check
//        (the same comparison with the binned pattern transposed).
//
import Darwin
import Foundation

/// Resident memory, and the anonymous footprint (`phys_footprint`). A mapped
/// file's clean pages count in the first and not the second: the second is
/// what a full read into memory grows, and what can exhaust swap.
func memoryMB() -> (resident: Double, footprint: Double) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return (.nan, .nan) }
    return (Double(info.resident_size) / 1_048_576, Double(info.phys_footprint) / 1_048_576)
}

func memory() -> String {
    let m = memoryMB()
    return String(format: "RSS %.0f MB, footprint %.0f MB", m.resident, m.footprint)
}

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data("FAIL: \(m)\n".utf8)); exit(1) }

@main
enum DM4ParityProbe {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(_ f: String) -> String? {
            guard let i = args.firstIndex(of: f), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        // --make-fixture PATH: a 64 x 64 scan of 128 x 128 int16 patterns
        // (128 MB), written with the robustness harness's DM4 writer, for
        // proving the open path on a small file on a non-local volume.
        if let out = value("--make-fixture") {
            let (s, q) = (64, 128)
            var pixels = ByteWriter()
            for i in 0..<(s * s * q * q) { pixels.i16le(Int16(truncatingIfNeeded: i % 30011)) }
            let n = UInt64(s * s * q * q)
            let body = dm4Header() + groupHeader(nTags: 1)
                + imageDataObject(qx: Int32(q), qy: Int32(q), rx: Int32(s), ry: Int32(s),
                                  dataLength: n, dataPayload: pixels.bytes)
            try writeFixture(body, to: URL(fileURLWithPath: out))
            print("wrote \(out): \(body.count / 1_048_576) MB")
            return
        }
        // --foundation-check FILE: the mechanism alone, without DM4Reader.
        // Opens FILE with each reading option, touches every 16 KB page,
        // and reports the anonymous footprint: a full read grows it by the
        // file size, a mapping does not.
        if let file = value("--foundation-check") {
            for (name, option) in [("mappedIfSafe", Data.ReadingOptions.mappedIfSafe),
                                   ("alwaysMapped", Data.ReadingOptions.alwaysMapped)] {
                let before = memoryMB().footprint
                var checksum: UInt64 = 0
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: file), options: option)
                    let opened = memoryMB().footprint
                    data.withUnsafeBytes { raw in
                        var i = 0
                        while i < raw.count { checksum &+= UInt64(raw[i]); i += 16_384 }
                    }
                    let touched = memoryMB().footprint
                    print(String(format: "%@: %d MB file; footprint +%.0f MB after open, +%.0f MB after touching every page (checksum %llu)",
                                 name, data.count / 1_048_576, opened - before, touched - before, checksum))
                }
            }
            return
        }
        if let raw = value("--open-only") {
            print("before open: \(memory())")
            let t0 = Date()
            let reader = try await DM4Reader(path: raw)
            let d = try await reader.discoverPrimaryDataset()
            print(String(format: "opened in %.1f s: ry %d rx %d qy %d qx %d; ",
                         Date().timeIntervalSince(t0), d.ry, d.rx, d.qy, d.qx) + memory())
            // What the function answers, not what `init` used: a literal option
            // in `init` leaves this line unchanged (Gate B 2026-09-28). The
            // footprint lines are the proof; inventory greps `init`.
            print("readingOptions(forPath:) answers: \(DM4Reader.readingOptions(forPath: raw) == .alwaysMapped ? "alwaysMapped" : "mappedIfSafe")")
            let view = LoadView(fullExtentOf: d)
            for (y, x) in [(0, 0), (d.ry / 2, d.rx / 2), (d.ry - 1, d.rx - 1)] {
                let p = try await reader.readPattern(view, ry: y, rx: x)
                print(String(format: "pattern (%d, %d): %d px, sum %.4g; ", y, x, p.count,
                             p.reduce(0, +)) + memory())
            }
            return
        }
        guard let raw = value("--parity"), let idx = args.firstIndex(of: "--parity"), idx + 2 < args.count
        else { fail("usage: --open-only RAW.dm4 | --parity RAW.dm4 PRE.h5 [--bin 4] [--stride N]") }
        let pre = args[idx + 2]
        let bin = Int(value("--bin") ?? "4") ?? 4
        let stride = max(1, Int(value("--stride") ?? "1") ?? 1)
        let dm = try await DM4Reader(path: raw)
        let dRaw = try await dm.discoverPrimaryDataset()
        let view = try LoadView(source: dRaw, specification: LoadSpecification(detectorBin: bin))
        let h5 = try H5Reader(path: pre)
        let dPre = try await h5.discoverPrimaryDataset()
        let preView = LoadView(fullExtentOf: dPre)
        print("raw \(dRaw.ry)×\(dRaw.rx)×\(dRaw.qy)×\(dRaw.qx) binned ×\(bin) → \(view.descriptor.qy)×\(view.descriptor.qx); "
              + "preprocessed \(dPre.ry)×\(dPre.rx)×\(dPre.qy)×\(dPre.qx)")
        guard view.descriptor.ry == dPre.ry, view.descriptor.rx == dPre.rx,
              view.descriptor.qy == dPre.qy, view.descriptor.qx == dPre.qx else { fail("shapes differ") }
        let q = dPre.qx
        var maxAbs: Float = 0, maxRel: Float = 0, maxAbsT: Float = 0, compared = 0, exact = 0
        var worst = (0, 0)
        let t0 = Date()
        for y in Swift.stride(from: 0, to: dPre.ry, by: stride) {
            let rowA = try await dm.readScanRow(view, ry: y)
            for x in Swift.stride(from: 0, to: dPre.rx, by: stride) {
                let a = Array(rowA[(x * q * q)..<((x + 1) * q * q)])
                let b = try await h5.readPattern(preView, ry: y, rx: x)
                var patternExact = true
                for i in 0..<(q * q) {
                    let diff = abs(a[i] - b[i])
                    if diff != 0 { patternExact = false }
                    if diff > maxAbs { maxAbs = diff; worst = (y, x) }
                    let scale = max(abs(b[i]), 1)
                    maxRel = max(maxRel, diff / scale)
                    let t = (i % q) * q + i / q              // transposed index
                    maxAbsT = max(maxAbsT, abs(a[t] - b[i]))
                }
                if patternExact { exact += 1 }
                compared += 1
            }
            if y % 30 == 0 {
                print(String(format: "  row %d: %d patterns, max |Δ| %.4g, max rel %.3g; %.0f s; ",
                             y, compared, maxAbs, maxRel, Date().timeIntervalSince(t0)) + memory())
            }
        }
        print(String(format: "PARITY: %d patterns compared, %d bit-identical; max |Δ| %.6g at (%d, %d), max relative %.3g; "
                     + "transposed max |Δ| %.6g; %.0f s",
                     compared, exact, maxAbs, worst.0, worst.1, maxRel, maxAbsT, Date().timeIntervalSince(t0)))
    }
}
