//
//  ACOMSession.swift
//  v2.5 step 6a (2026-09-03): the ACOM analysis's own state — model choice,
//  matching options, custom crystal, display, confidence gate, and the facts
//  of the last run — owned in one observable place (plan §4 "ACOMController").
//  AppState forwards to it and keeps the invalidation side effects in its
//  setters until the run functions move here too.
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class ACOMSession {
    package var modelSelection: CrystalModelSelection = .none
    /// CIF files imported this run. Session-local, never persisted.
    package var importedCrystalModels: [CrystalModel] = []
    package var exploratoryScale: Double = 0.01
    package var backend: ACOMMatchingBackend = .automatic
    package var quality: ACOMQualityPreset = .balanced
    package var scope: ACOMRunScope = .preview
    package var regionRadius = 24
    package var regionSelectionActive = false

    // Custom (user-defined) cubic crystal.
    package var customZ: Int = 79
    package var customStructure: Crystal.CubicStructure = .fcc
    package var customLatticeA: Double = 4.08

    package var display: ACOMDisplayMode = .reliability
    package var displayIsUserChosen = false
    /// Nil = automatic (10th percentile of matched reliabilities).
    package var reliabilityThreshold: Float?

    // Facts of the last run, read by the footer and the estimates.
    package var lastRunScope: ACOMRunScope?
    package var lastRunQuality: ACOMQualityPreset?
    package var lastRunSemantics: ACOMRunSemantics?
    package var lastMatchedPositionCount: Int?
    package var lastPositionsPerSecond: Double?
    package var lastEndToEndDuration: TimeInterval?

    package init() {}
}
