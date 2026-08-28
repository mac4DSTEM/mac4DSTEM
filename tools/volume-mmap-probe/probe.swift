import Foundation

/// phys_footprint — the number jetsam kills on. `resident_size` misses
/// compressed pages and IOKit/Metal allocations, which is why the app's own
/// Performance panel structurally cannot predict the kill it suffered
/// (docs/open-items.md, the 8 GB death entry).
func physFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
}

func gb(_ b: UInt64) -> String { String(format: "%.2f GB", Double(b) / 1_073_741_824) }

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
let size = (try! FileManager.default.attributesOfItem(atPath: path)[.size] as! NSNumber).uint64Value

/// The predicate Foundation actually applies is on the MOUNT flags:
/// it maps only when `MNT_LOCAL && !MNT_REMOVABLE`.
///
/// Read them from `statfs`, NOT from `URL.volumeIsRemovableKey`. The two answer
/// different questions — the URL key tracks removable *media*, the mount flag
/// tracks external attachment — and they DISAGREE on an external SSD, which is
/// exactly what sent S9b's first reading down the wrong road (2026-08-28).
func mountFlags(_ path: String) -> (fs: String, local: Bool, removable: Bool) {
    var st = statfs()
    guard statfs(path, &st) == 0 else { return ("?", false, false) }
    let fs = withUnsafePointer(to: st.f_fstypename) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
    }
    return (fs, st.f_flags & UInt32(MNT_LOCAL) != 0, st.f_flags & UInt32(MNT_REMOVABLE) != 0)
}
let flags = mountFlags(path)
let before = physFootprintBytes()
let data = try! Data(contentsOf: url, options: .mappedIfSafe)

// Touch one byte per 4 KB page across the whole file. A real mmap faults pages
// in and the kernel can evict them; a silent full read has already paid for all
// of it. Either way this defeats any laziness in the measurement.
var checksum: UInt64 = 0
data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    var i = 0
    while i < raw.count { checksum &+= UInt64(raw[i]); i += 4096 }
}
let after = physFootprintBytes()
let delta = after > before ? after - before : 0
let ratio = Double(delta) / Double(size)

print("file        \(url.lastPathComponent)")
print("size        \(gb(size))")
print("mount       fs=\(flags.fs) MNT_LOCAL=\(flags.local ? 1 : 0) MNT_REMOVABLE=\(flags.removable ? 1 : 0)")
print("predicted   " + ((flags.local && !flags.removable) ? "MAPPED (local, not removable)" : "DECLINED (not local, or removable)"))
print("footprint   before \(gb(before))  after \(gb(after))  delta \(gb(delta))")
print(String(format: "ratio       %.3f of file size", ratio))
print("verdict     " + (ratio < 0.10 ? "MAPPED (delta < 10% of file)"
                      : ratio > 0.80 ? "DECLINED — full read (delta > 80% of file)"
                      : "UNPLANNED — between thresholds, report as-is"))
print("checksum    \(checksum)   (forces the touch loop to not be optimised away)")
