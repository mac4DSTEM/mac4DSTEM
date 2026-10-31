//
//  SystemMonitor.swift
//  Role: this app's half of the system metrics: the GPU's name and working set (the inspector's performance panel) and the scan-pass
//        status line. The process footprint (`residentMemoryMB`), `byteString` and `count` are ShellLayout's `SystemMonitor`
//        (suite task 8, MacEMUI).
//

import ShellLayout
import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Metal
import ShellMetal

extension SystemMonitor {

    package static var gpuName: String { MetalEngine.shared.device.name }

    /// The GPU working-set limit as text, in the app's one byte style.
    package static var gpuWorkingSetText: String {
        byteString(Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize))
    }

    // Pure formatting; kept beside `byteString`.
    package nonisolated static func scanProgressStatus(
        _ verb: String, processed: Int, total: Int, descriptor d: DatasetDescriptor, bytesPerPattern streamed: Int? = nil
    ) -> String {
        // `streamed`: what one position actually reads (`LoadView.readBytesPerPattern`, pre-bin); the descriptor's
        // pattern size only when the caller has no view.
        let bytesPerPattern = streamed ?? d.qy * d.qx * MemoryLayout<Float>.stride
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
