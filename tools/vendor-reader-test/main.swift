import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

@main struct VendorReaderHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fail("usage: harness fixture-dir") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])

        let empad = try EMPADReader(path: root.appendingPathComponent("empad.xml").path)
        let ed = try await empad.discoverPrimaryDataset()
        guard ed.shape == [2, 3, 128, 128], ed.dtypeDescription.contains("little-endian") else {
            fail("EMPAD descriptor \(ed.shape) \(ed.dtypeDescription)")
        }
        let ep = try await empad.readPattern(ed, ry: 1, rx: 2)
        guard ep.count == 128 * 128, ep[0] == 500_000, ep.last == 516_383,
              !ep.contains(-6) else { fail("EMPAD image/footer separation") }
        let et = try await empad.readScanTile(ed, yRange: 0..<2)
        guard et.pixels.count == 6 * 128 * 128, et.pixels[128 * 128] == 100_000 else {
            fail("EMPAD scan ordering")
        }
        print("PASS: EMPAD XML shape, little-endian frames, footer crop, and tile order")

        do {
            _ = try EMPADReader(path: root.appendingPathComponent("ambiguous.raw").path)
            fail("ambiguous raw-only EMPAD was accepted")
        } catch let error as VendorRawError {
            guard error.localizedDescription.contains("XML companion") else {
                fail("EMPAD ambiguity error was not actionable: \(error.localizedDescription)")
            }
        }
        print("PASS: non-square raw-only EMPAD fails with companion guidance")

        let mib = try MIBReader(path: root.appendingPathComponent("merlin.mib").path)
        let md = try await mib.discoverPrimaryDataset()
        guard md.shape == [1, 2, 256, 256], md.dtypeDescription.contains("U16") else {
            fail("MIB descriptor \(md.shape) \(md.dtypeDescription)")
        }
        let mp = try await mib.readPattern(md, ry: 0, rx: 1)
        guard mp.count == 256 * 256, mp[0] == 1000, mp[1] == 1001,
              mp[65534] == Float((1000 + 65534) % 65535) else {
            fail("MIB repeated-header skip or big-endian decode")
        }
        let mt = try await mib.readScanTile(md, yRange: 0..<1)
        guard mt.pixels.count == 2 * 256 * 256, mt.pixels[256 * 256] == 1000 else {
            fail("MIB scan ordering")
        }
        print("PASS: MIB companion shape, repeated headers, big-endian U16, and tile order")
        print("vendor-reader-test: all passed")
    }
}
