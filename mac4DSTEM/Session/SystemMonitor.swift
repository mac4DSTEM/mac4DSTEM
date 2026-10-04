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

    /// The memory this process is responsible for — its physical footprint
    /// (`task_vm_info.phys_footprint`, what Activity Monitor's Memory column
    /// shows) — in MiB (bytes / 2^20; the status strip's call site converts to
    /// the decimal MB `OperationMetricsFormat.glance` takes). NOT
    /// `resident_size`: that counts the memory-mapped cube's clean file pages,
    /// which the kernel may drop at any time and which belong to the page
    /// cache, so a streamed 28 GB cube read "27 GB" for a process whose
    /// footprint was 10-22 MB (`docs/archive/v4/parity-28gb-2026-09-30.md`).
    /// The name is the frozen call site's (`WorkspaceView.systemGlance`); it
    /// is renamed when that shell is next open. 0 when the kernel call fails.
    // The same 8 lines as `DetectorTraining.footprintMB`, copied rather than
    // shared on purpose: `DSTEMTraining` depends on `DSTEMCore` alone and the
    // training probe compiles it against that alone, so it cannot call this
    // `DSTEMSession` type; a shared reader would have to live in an existing
    // Core/ file both import, and the 8-line copy is the smaller change.
    package static func residentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    package static var gpuName: String { MetalEngine.shared.device.name }

    /// Recommended max GPU working set, in MB.
    package static var gpuWorkingSetMB: Double {
        Double(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 1_048_576
    }

    /// The GPU working-set limit as text, in the app's one byte style.
    package static var gpuWorkingSetText: String {
        byteString(Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize))
    }

    /// Format a byte count as MB or GB.
    package nonisolated static func byteString(_ bytes: Int) -> String {
        // One style app-wide: Finder's decimal one (`displayByteString`), so
        // the sidebar's "Resident" reads like the sheet's and the inspector's.
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Status line for a whole-cube pass, in the two quantities a user can
    /// check against their own file: patterns read, and bytes read.
    /// Bytes are the **float32 working size** — what is actually streamed —
    /// not the on-disk size, which differs whenever the file's dtype is not
    /// float32 (a uint16 cube streams at twice its file size). Reporting the
    /// file size here would be the more flattering number and the wrong one.
    // Pure formatting; kept beside `byteString`.
    package nonisolated static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    package nonisolated static func scanProgressStatus(
        _ verb: String, processed: Int, total: Int, descriptor d: DatasetDescriptor
    ) -> String {
        let bytesPerPattern = d.qy * d.qx * MemoryLayout<Float>.stride
        // Fixed grouping rather than the user's locale, because the byte string
        // beside it is itself unlocalized (`SystemMonitor.byteString` always
        // formats "3.96 GB" with a period decimal point). Locale grouping would
        // put two meanings of "." in one line (e.g. German grouping reads as a
        // second decimal point). One convention per line.
        let patterns = "\(count(processed)) / \(count(total)) patterns"
        let bytes = "\(byteString(processed * bytesPerPattern))"
            + " of \(byteString(total * bytesPerPattern))"
        return "\(verb) \(patterns) · \(bytes)"
    }
}
