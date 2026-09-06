//
//  LearnedDetection.swift
//  Role: step 4's seam (docs/v3-plan.md §3a, docs/development-process.md §7) —
//        the one owner of the learned-vs-classical detector option, the
//        learned pick threshold, the probe image the learned path needs, the
//        loaded `LearnedDiskDetector`, and the two runs a disagreement map
//        compares. Held by AppState with no forwarding properties; views
//        read `learnedDetection.…`.
//
//  What deliberately does NOT live here: the disk-detection run itself
//  (`AppState.runDiskDetection`, which reads `detectorClass`/`threshold`/
//  `probeReference` and writes back through `record`), and the probe kernel
//  image generation (`AppState.generateProbeKernel` and its two siblings,
//  which populate `probeReference` alongside `AppState.probeKernel`).
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

@Observable
@MainActor
package final class LearnedDetectionSession {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// Which detector runs a full-scan pass. Classical stays the default —
    /// the learned option is macOS 27+ and needs a generated probe kernel.
    package var detectorClass: DetectorClass = .classical

    /// The learned pick threshold on the heatmap (py4DSTEM-adjacent knob, not
    /// a physical unit): `LearnedDiskDetector.defaultThreshold` is 0.9.
    package var threshold: Float = 0.9

    /// The full-size probe image the learned path crops from — set whenever
    /// ANY probe kernel is generated (synthetic, measured, or file), so the
    /// learned option is ready the moment a kernel exists, without a second
    /// "prepare the learned detector" step for the probe alone.
    package struct ProbeReference: Sendable {
        package let pattern: DiffractionPattern
        package let centreX: Float
        package let centreY: Float
        package let radius: Float
        package let source: ProbeKernelSource

        package init(
            pattern: DiffractionPattern, centreX: Float, centreY: Float,
            radius: Float, source: ProbeKernelSource
        ) {
            self.pattern = pattern
            self.centreX = centreX
            self.centreY = centreY
            self.radius = radius
            self.source = source
        }
    }
    package var probeReference: ProbeReference?

    /// The two full-scan runs a disagreement map compares. Set by `record`
    /// after a successful `runDiskDetection`; cleared on dataset activation.
    package private(set) var lastClassical: BraggVectors?
    package private(set) var lastLearned: BraggVectors?

    /// True while the learned asset is loading (`prepare` below). Distinct
    /// from the disk-detection run's own cancellable-operation state: loading
    /// the asset happens BEFORE that operation begins.
    package private(set) var preparing = false

    /// Set once the asset has loaded successfully — the identity provenance
    /// wants (`learned_model_sha256`) and the Settings tab's "Model" row.
    package private(set) var assetSHA256: String?

    /// Why the learned option cannot run here: no bundled asset, a load
    /// failure, or (checked by the caller, not stored here) the OS floor.
    /// Cleared on a successful `prepare`.
    package private(set) var unavailableReason: String?

    /// The loaded detector, held as `AnyObject` so this stored property needs
    /// no availability annotation — `LearnedDiskDetector` exists only under
    /// `#if canImport(CoreAI)` / macOS 27. Only `prepare` touches it.
    @ObservationIgnored private var detectorBox: AnyObject?

    /// Record a completed full-scan result under the class that produced it.
    package func record(_ vectors: BraggVectors, as detectorClass: DetectorClass) {
        switch detectorClass {
        case .classical: lastClassical = vectors
        case .learned: lastLearned = vectors
        }
    }

    /// Dataset activation: the two compared runs and the probe reference die
    /// with the dataset (the probe reference mirrors `AppState.probeKernel`'s
    /// own lifecycle — a stale probe from a different detector grid is not
    /// just outdated, it is the wrong shape). The option, the threshold, and
    /// the loaded detector survive: they are session-scoped, not dataset-scoped.
    package func clear() {
        lastClassical = nil
        lastLearned = nil
        probeReference = nil
    }

    /// Both runs are on the same (freshly cleared) dataset because `clear()`
    /// resets both together — a disagreement map never compares runs from
    /// two different datasets.
    package var canCompare: Bool { lastClassical != nil && lastLearned != nil }

    #if canImport(CoreAI)
    /// Load the learned asset once and cache it; later calls return the
    /// cached instance. Slow the first time (~1.3 s measured 2026-09-07 in
    /// `LearnedDiskDetector.load`) — never called inside the disk-detection
    /// run's own cancellable operation, which is why `AppState.runDiskDetection`
    /// calls this BEFORE `beginCancellableOperation`.
    @available(macOS 27, *)
    package func prepare(assetURL: URL) async throws -> LearnedDiskDetector {
        if let cached = detectorBox as? LearnedDiskDetector { return cached }
        preparing = true
        defer { preparing = false }
        do {
            let detector = try await LearnedDiskDetector.load(assetURL: assetURL)
            detectorBox = detector
            assetSHA256 = detector.assetSHA256
            unavailableReason = nil
            return detector
        } catch {
            unavailableReason = error.localizedDescription
            throw error
        }
    }
    #endif
}
