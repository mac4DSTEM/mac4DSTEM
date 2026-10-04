import Foundation
import Darwin

// Lane D probe (NOT in the app): a DM4Reader on a RAM disk, a forced unmount, and the candidate liveness checks.
// usage: probe write <path>          writes a 32 MB synthetic int16 DM4 (Ry=Rx=32, Qy=Qx=128)
//        probe run <path>            opens it, then obeys commands on stdin: check <label> | read first | read last | quit

func say(_ s: String) { print(s); fflush(stdout) }
func errText() -> String { "errno=\(errno) (\(String(cString: strerror(errno))))" }
func fsid(_ f: fsid_t) -> String { "\(f.val.0),\(f.val.1)" }
func typeName(_ sf: inout statfs) -> String {
    withUnsafeBytes(of: &sf.f_fstypename) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
}

func checks(_ label: String, path: String, fd: Int32) {
    var sf = statfs()
    if statfs(path, &sf) == 0 { say("[\(label)] statfs(path)  OK  fsid=\(fsid(sf.f_fsid)) type=\(typeName(&sf))") }
    else { say("[\(label)] statfs(path)  FAIL \(errText())") }
    var st = stat()
    if stat(path, &st) == 0 { say("[\(label)] stat(path)    OK  dev=\(st.st_dev) ino=\(st.st_ino)") }
    else { say("[\(label)] stat(path)    FAIL \(errText())") }
    var fsf = statfs()
    if fstatfs(fd, &fsf) == 0 { say("[\(label)] fstatfs(fd)  OK  fsid=\(fsid(fsf.f_fsid)) type=\(typeName(&fsf)) on=\(withUnsafeBytes(of: &fsf.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) })") }
    else { say("[\(label)] fstatfs(fd)  FAIL \(errText())") }
    var fst = stat()
    if fstat(fd, &fst) == 0 { say("[\(label)] fstat(fd)    OK  dev=\(fst.st_dev) ino=\(fst.st_ino) nlink=\(fst.st_nlink)") }
    else { say("[\(label)] fstat(fd)    FAIL \(errText())") }
    var buf = [UInt8](repeating: 0, count: 4096)
    let r0 = pread(fd, &buf, 1, 0)
    say("[\(label)] pread(fd,1B@0)        \(r0 == 1 ? "OK" : "FAIL \(errText())")")
    let r1 = pread(fd, &buf, 1, 30_000_000)
    say("[\(label)] pread(fd,1B@30MB)     \(r1 == 1 ? "OK" : "FAIL \(errText())")")
    var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    if fcntl(fd, F_GETPATH, &pathBuf) == 0 { say("[\(label)] F_GETPATH(fd)  OK  \(String(cString: pathBuf))") }
    else { say("[\(label)] F_GETPATH(fd)  FAIL \(errText())") }
}

func writeCube(to path: String) throws {
    let qy = 128, qx = 128, ry = 32, rx = 32
    var pixels = ByteWriter()
    for i in 0..<(qy * qx * ry * rx) { pixels.i16le(Int16(truncatingIfNeeded: i)) }
    let body = dm4Header() + groupHeader(nTags: 1)
        + imageDataObject(qx: Int32(qx), qy: Int32(qy), rx: Int32(rx), ry: Int32(ry),
                          dataLength: UInt64(qy * qx * ry * rx), dataPayload: pixels.bytes)
    try Data(body).write(to: URL(fileURLWithPath: path))
}

@main struct Probe {
    static func main() async {
        let a = CommandLine.arguments
        guard a.count >= 3 else { say("usage"); exit(2) }
        let path = a[2]
        if a[1] == "write" {
            do { try writeCube(to: path); say("wrote \(path)") } catch { say("write failed \(error)"); exit(1) }
            return
        }
        if a[1] == "hash" {
            // FNV-1a 64 over the float bit patterns of every pixel the reader serves: all rows as one tile, a row, a pattern.
            func fnv(_ values: [Float], _ h: inout UInt64) { for v in values { var b = v.bitPattern; for _ in 0..<4 { h = (h ^ UInt64(b & 0xFF)) &* 0x100000001b3; b >>= 8 } } }
            do {
                let reader = try await DM4Reader(path: path)
                let ds = try await reader.discoverPrimaryDataset(); let view = LoadView(fullExtentOf: ds)
                var h: UInt64 = 0xcbf29ce484222325
                let tile = try await reader.readScanTile(view, yRange: 0..<ds.shape[0]); fnv(tile.pixels, &h)
                fnv(try await reader.readScanRow(view, ry: 3), &h)
                fnv(try await reader.readPattern(view, ry: 5, rx: 7), &h)
                say("hash \(String(h, radix: 16)) tilePixels=\(tile.pixels.count)")
            } catch { say("hash FAILED \(error)"); exit(1) }
            return
        }
        let options = DM4Reader.readingOptions(forPath: path)
        say("readingOptions == alwaysMapped: \(options == .alwaysMapped)")
        let reader: DM4Reader
        do { reader = try await DM4Reader(path: path) } catch { say("open FAILED: \(error)"); exit(1) }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { say("open(fd) FAILED \(errText())"); exit(1) }
        let ds = try! await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        do {
            let p = try await reader.readPattern(view, ry: 0, rx: 0)
            say("pre-yank readPattern(0,0) OK, \(p.count) px, first=\(p[0]) last=\(p[p.count - 1])")
        } catch { say("pre-yank read FAILED: \(error)") }
        checks("open", path: path, fd: fd)
        say("READY")
        while let line = readLine() {
            let parts = line.split(separator: " ").map(String.init)
            switch parts.first ?? "" {
            case "check": checks(parts.count > 1 ? parts[1] : "check", path: path, fd: fd)
            case "read":
                let last = parts.count > 1 && parts[1] == "last"
                let (y, x) = last ? (31, 31) : (0, 0)
                say("reading pattern (\(y),\(x)) ...")
                do {
                    let p = try await reader.readPattern(view, ry: y, rx: x)
                    say("readPattern(\(y),\(x)) returned \(p.count) px, first=\(p[0]) (no error)")
                } catch { say("readPattern(\(y),\(x)) THREW: \(error.localizedDescription)") }
            case "quit": say("bye"); exit(0)
            default: say("unknown command \(line)")
            }
        }
    }
}
