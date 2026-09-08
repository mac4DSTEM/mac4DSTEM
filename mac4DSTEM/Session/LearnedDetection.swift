//
//  LearnedDetection.swift
//  Role: C7 session 2's seam (docs/v3-plan.md §3a, docs/development-process.md
//        §7) — the one owner of the learned-vs-classical detector option, the
//        learned pick threshold, the probe image the learned path needs, the
//        loaded `LearnedDiskDetector`, and the two runs a disagreement map
//        compares. Held by AppState with no forwarding properties; views
//        read `learnedDetection.…`. Core ML (session 1), not the Core AI
//        runtime an earlier branch used — no availability gate.
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

    /// Which detector runs a full-scan pass. Classical stays the default.
    package var detectorClass: DetectorClass = .classical

    /// The learned pick threshold on the heatmap (py4DSTEM-adjacent knob,
    /// not a physical unit).
    package var threshold: Float = LearnedDiskDetector.defaultThreshold

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
    /// from the disk-detection run's own cancellable-operation state:
    /// loading the asset happens BEFORE that operation begins.
    package private(set) var preparing = false

    /// Set once the asset has loaded successfully — the identity provenance
    /// wants (`learned_model_sha256`) and the Disk detection section's
    /// "Model" row.
    package private(set) var assetSHA256: String?

    /// Why the learned option cannot run here: no bundled asset, a load
    /// failure. Cleared on a successful `prepare`.
    package private(set) var unavailableReason: String?

    /// The loaded detector, held once and reused — loading it is slow
    /// (~1.3 s, C7 session 1 measurement) and must never happen inside a
    /// run's own cancellable operation.
    @ObservationIgnored private var detector: LearnedDiskDetector?

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

    /// Draws a unit disk at `centre` on a `qy` × `qx` field: 1 inside the
    /// radius, 0 outside. The full-size probe IMAGE the learned path needs
    /// when the kernel generator has no measured pattern to draw one from
    /// (the synthetic generator) — moved here so `AppState` gets one line.
    package static func syntheticProbe(
        qy: Int, qx: Int, centre: (x: Float, y: Float), radius: Float
    ) -> DiffractionPattern {
        var pixels = [Float](repeating: 0, count: qy * qx)
        for y in 0..<qy {
            let dy = Float(y) - centre.y
            for x in 0..<qx {
                let dx = Float(x) - centre.x
                pixels[y * qx + x] = (dx * dx + dy * dy <= radius * radius) ? 1 : 0
            }
        }
        return DiffractionPattern(qy: qy, qx: qx, pixels: pixels)
    }

    /// Load the learned asset once and cache it; later calls return the
    /// cached instance. Slow the first time — never called inside the
    /// disk-detection run's own cancellable operation, which is why
    /// `prepareForRun` runs it BEFORE `AppState.runDiskDetection` calls
    /// `beginCancellableOperation`.
    package func prepare(assetURL: URL) async throws -> LearnedDiskDetector {
        if let cached = detector { return cached }
        preparing = true
        defer { preparing = false }
        do {
            let loaded = try await LearnedDiskDetector.load(assetURL: assetURL)
            detector = loaded
            assetSHA256 = loaded.assetSHA256
            unavailableReason = nil
            return loaded
        } catch {
            unavailableReason = error.localizedDescription
            throw error
        }
    }

    /// `Result`'s `Failure` must conform to `Error`, which a bare `String`
    /// does not — this is `prepareForRun`'s outcome, shaped the same way
    /// (`.success(LearnedDiskDetector)` / `.failure(String reason)`) so call
    /// sites read identically to a `Result` without wrapping the reason.
    package enum PrepareOutcome {
        case success(LearnedDiskDetector)
        case failure(String)
    }

    /// The guards `runDiskDetection` needs before it may run the learned
    /// class: a probe reference (from a generated kernel), a bundled asset,
    /// and a successful load. Returns the failure reason on any miss, rather
    /// than substituting classical.
    package func prepareForRun() async -> PrepareOutcome {
        guard probeReference != nil else {
            return .failure("Generate a probe kernel first — the learned detector needs the probe image")
        }
        guard let assetURL = LearnedDiskDetector.bundledAssetURL() else {
            return .failure("The learned detector's model is not in this build")
        }
        do {
            return .success(try await prepare(assetURL: assetURL))
        } catch {
            return .failure("The learned detector could not be prepared: \(error.localizedDescription)")
        }
    }

    /// The learned candidates for the currently displayed pattern, or nil
    /// when the caller should fall back to the classical rings: detector
    /// class is not `.learned`, no probe reference yet, or the asset is not
    /// preparable here.
    package func livePeaks(pattern: DiffractionPattern, params: DiskDetectionParams) async -> [BraggPeak]? {
        guard detectorClass == .learned, let ref = probeReference,
              let assetURL = LearnedDiskDetector.bundledAssetURL(),
              let learned = try? await prepare(assetURL: assetURL) else { return nil }
        let currentThreshold = threshold
        return await Task.detached(priority: .userInitiated) {
            await learned.detect(
                pattern: pattern, probe: ref.pattern,
                probeCentre: (x: ref.centreX, y: ref.centreY), probeRadius: ref.radius,
                kernelSource: ref.source, params: params, threshold: currentThreshold
            )
        }.value
    }

    /// The provenance `runDiskDetection` merges into its recorded replay
    /// step: `detector_class` always, plus the learned identity when this
    /// run used it.
    package func replayParameters(for detectorClass: DetectorClass) -> [String: String] {
        var params = ["detector_class": detectorClass.provenanceID]
        if detectorClass == .learned {
            params["learned_threshold"] = String(threshold)
            params["learned_model_sha256"] = assetSHA256 ?? ""
        }
        return params
    }

    /// Apply a recorded disk-detection step's detector class (and, for
    /// `.learned`, its threshold), then confirm this build's model matches
    /// the one it ran against. Returns the refusal reason, or nil to
    /// proceed — the probe reference is not required here: it is created
    /// when `runDiskDetection` auto-generates the kernel, which happens
    /// after this check.
    package func replayRefusal(for recorded: ReplayStepPlan.DiskDetectorReplay) async -> String? {
        detectorClass = recorded.detectorClass
        guard recorded.detectorClass == .learned else { return nil }
        if let recordedThreshold = recorded.learnedThreshold { threshold = recordedThreshold }
        guard let assetURL = LearnedDiskDetector.bundledAssetURL() else {
            return "the neural-net model is not in this build — choose Classical under Detector in Disk detection, then run detection by hand"
        }
        do {
            _ = try await prepare(assetURL: assetURL)
        } catch {
            return unavailableReason ?? error.localizedDescription
        }
        guard assetSHA256 == recorded.learnedModelSHA256 else {
            let have = String((assetSHA256 ?? "").prefix(8))
            let want = String((recorded.learnedModelSHA256 ?? "").prefix(8))
            return "it detected disks with the neural net at model \(want)…, and this build ships \(have)… — run detection by hand"
        }
        return nil
    }
}
