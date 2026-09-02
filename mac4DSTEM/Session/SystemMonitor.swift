//
//  SystemMonitor.swift
//  Role: Lightweight process/GPU metrics for the inspector's performance panel.
//

import Foundation
import DSTEMCore
import DSTEMSession
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
}
