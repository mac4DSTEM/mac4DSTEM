//
//  SystemMonitor.swift
//  Role: Lightweight process/GPU metrics for the inspector's performance panel.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Metal

package enum SystemMonitor {

    /// Resident memory of this process, in MB.
    package static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    package static var gpuName: String { MetalEngine.shared.device.name }

    /// Recommended max GPU working set, in MB.
    package static var gpuWorkingSetMB: Double {
        Double(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 1_048_576
    }

    /// Format a byte count as MB or GB.
    package nonisolated static func byteString(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    /// Status line for a whole-cube pass, in the two quantities a user can
    /// check against their own file: patterns read, and bytes read.
    /// Bytes are the **float32 working size** — what is actually streamed —
    /// not the on-disk size, which differs whenever the file's dtype is not
    /// float32 (a uint16 cube streams at twice its file size). Reporting the
    /// file size here would be the more flattering number and the wrong one.
    // Moved from AppState in C7 session 3 (the C5 budget): pure formatting beside `byteString`.
    package nonisolated static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    package nonisolated static func scanProgressStatus(
        _ verb: String, processed: Int, total: Int, descriptor d: DatasetDescriptor
    ) -> String {
        let bytesPerPattern = d.qy * d.qx * MemoryLayout<Float>.stride
        // Fixed grouping rather than the user's locale, because the byte string
        // beside it is itself unlocalized (`SystemMonitor.byteString` always
        // formats "3.96 GB" with a period decimal point). Locale grouping put
        // two meanings of "." in one line — on a German system this read
        // "1.378 / 16.218 patterns · 3.96 GB", where the first two periods
        // group and the third is a decimal point. One convention per line.
        let patterns = "\(count(processed)) / \(count(total)) patterns"
        let bytes = "\(byteString(processed * bytesPerPattern))"
            + " of \(byteString(total * bytesPerPattern))"
        return "\(verb) \(patterns) · \(bytes)"
    }
}
