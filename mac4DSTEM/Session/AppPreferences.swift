//
//  AppPreferences.swift
//  Role: the Settings window's one state owner — every user-facing app
//        preference, over an injectable `UserDefaults`. `SettingsWindow`
//        (`UI/SettingsWindow.swift`) is the writer, and the one exception is
//        `exportScale` and `figureFormat`, which the export sections also set
//        where the export is chosen; every other reader reaches it through
//        `.environment(preferences)`.
//
//  Injectable store, same shape as `MaterialsProjectSettings`'s injectable
//  `APIKeyStore` and `SessionSidecarLocator`'s injectable bookmark store: a
//  test must never touch the real `UserDefaults.standard` domain — construct
//  with `UserDefaults(suiteName:)` and remove the suite afterward.
//
//  Keys are namespaced `prefs.` so they cannot collide with
//  `WorkspaceRecoveryStore`'s keys in the same `UserDefaults.standard` domain.
//  EVERY property's default equals today's shipped behaviour with no
//  Settings window at all — installing this file changes nothing until a
//  user actually opens Settings and changes something (owner decision,
//  ROADMAP.md "Settings window, Xcode-style sidebar").
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// System/Light/Dark. The mapping to SwiftUI's `ColorScheme?` lives in
/// `App/mac4DSTEMApp.swift`, not here — `Session/` imports no SwiftUI
/// (`docs/architecture.md`).
package enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// The diffraction/result panes' log-scale toggle already exists as
/// `AppState.logScale: Bool`; this is its Settings-facing, named-case twin so
/// the picker reads "Log / Linear" rather than a bare toggle with an
/// inverted sense hidden in its label.
package enum IntensityDisplayDefault: String, CaseIterable, Identifiable, Sendable {
    case log, linear

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .log: return "Log"
        case .linear: return "Linear"
        }
    }

    package var isLog: Bool { self == .log }
}

/// How many pixels each exported PNG spends per point of its layout: 1x is the size the exports always had, 2x and 3x are the same
/// picture with that many times the pixels in each direction (a talk's figure, sharp on a projector), and the file says so (144 or
/// 216 pixels per inch) so a slide app places it at the 1x size.
package enum ExportImageScale: String, CaseIterable, Identifiable, Sendable {
    case one = "1x", two = "2x", three = "3x"

    package var id: String { rawValue }

    package var pixelScale: Int {
        switch self {
        case .one: return 1
        case .two: return 2
        case .three: return 3
        }
    }

    package var displayName: String { "\(pixelScale)\u{00D7}" }
}

/// The file a figure is written as. PNG and TIFF are pixels (at the export scale); PDF is vector: the labels, the outlines and the
/// scale bars stay lines and text at any zoom, and the maps are the only pixels in it.
package enum ExportFigureFormat: String, CaseIterable, Identifiable, Sendable {
    case png, pdf, tiff

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .png: return "PNG"
        case .pdf: return "PDF (vector)"
        case .tiff: return "TIFF"
        }
    }
}

/// What the primary "Open Dataset…" action does. `AppState` already exposes
/// both flows as separate methods (`requestOpenDataset` /
/// `requestOpenDatasetWithOptions`) reachable from their own menu items and
/// buttons; this only decides which one the SHARED "Open Dataset…" gesture
/// (⌘O, the sidebar's primary button) takes by default.
package enum OpenDatasetBehaviour: String, CaseIterable, Identifiable, Sendable {
    case direct, options

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .direct: return "Open directly"
        case .options: return "Show options"
        }
    }
}

@Observable
@MainActor
package final class AppPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var suppressPersistence = false

    package var appearance: AppAppearance {
        didSet { persist(appearance, forKey: Keys.appearance) }
    }

    /// The result pane's default colormap. Read once, at the moment a fresh
    /// window's `ResultPresentation`/`AppState.patternColormap` take their
    /// starting value (`AppState.init`) — never re-applied over an
    /// analysis's own colormap choice (a diverging strain or DPC-difference
    /// map must stay diverging regardless of this default; see
    /// `AppState+ResultPresentation.swift` and `AppState+DPC.swift`).
    package var mapColormap: ColormapKind {
        didSet { persist(mapColormap, forKey: Keys.mapColormap) }
    }

    /// The diffraction (CBED) pane's default colormap. Same one-shot seeding
    /// as `mapColormap`.
    package var diffractionColormap: ColormapKind {
        didSet { persist(diffractionColormap, forKey: Keys.diffractionColormap) }
    }

    package var intensityDisplay: IntensityDisplayDefault {
        didSet { persist(intensityDisplay, forKey: Keys.intensityDisplay) }
    }

    package var showScaleBar: Bool {
        didSet { persist(showScaleBar, forKey: Keys.showScaleBar) }
    }

    package var openBehaviour: OpenDatasetBehaviour {
        didSet { persist(openBehaviour, forKey: Keys.openBehaviour) }
    }

    /// The pixel density of exported PNGs (the result image, the diffraction pattern, the EDX maps and the figure).
    package var exportScale: ExportImageScale {
        didSet { persist(exportScale, forKey: Keys.exportScale) }
    }

    /// The file type of an exported figure. A PDF has no pixel size, so `exportScale` does not apply to it.
    package var figureFormat: ExportFigureFormat {
        didSet { persist(figureFormat, forKey: Keys.figureFormat) }
    }

    /// `false` is today's shipped behaviour: nothing calls
    /// `ProcessInfo.beginActivity` for an interactive run today.
    package var keepAwake: Bool {
        didSet { persist(keepAwake, forKey: Keys.keepAwake) }
    }

    /// Whether the learned (Core ML) disk detector is offered in the
    /// Detector picker at all (`UI/MapSettings.swift`). `true` is today's
    /// shipped behaviour — the picker always lists it when a bundled asset
    /// exists; this does not touch asset availability or the threshold the
    /// detector runs with, only whether the option is offered.
    package var offerLearnedDetector: Bool {
        didSet { persist(offerLearnedDetector, forKey: Keys.offerLearnedDetector) }
    }

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = Self.decode(Keys.appearance, from: defaults) ?? .system
        self.mapColormap = Self.decode(Keys.mapColormap, from: defaults) ?? .viridis
        self.diffractionColormap = Self.decode(Keys.diffractionColormap, from: defaults) ?? .viridis
        self.intensityDisplay = Self.decode(Keys.intensityDisplay, from: defaults) ?? .log
        self.showScaleBar = defaults.object(forKey: Keys.showScaleBar) as? Bool ?? true
        self.openBehaviour = Self.decode(Keys.openBehaviour, from: defaults) ?? .direct
        self.exportScale = Self.decode(Keys.exportScale, from: defaults) ?? .one
        self.figureFormat = Self.decode(Keys.figureFormat, from: defaults) ?? .png
        self.keepAwake = defaults.object(forKey: Keys.keepAwake) as? Bool ?? false
        self.offerLearnedDetector = defaults.object(forKey: Keys.offerLearnedDetector) as? Bool ?? true
    }

    /// Restore every key to its shipped default. `removeObject`, not a
    /// re-write of the default's raw value, so a later change to what
    /// "default" means takes effect without a second migration.
    package func resetAllToDefaults() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        suppressPersistence = true
        appearance = .system
        mapColormap = .viridis
        diffractionColormap = .viridis
        intensityDisplay = .log
        showScaleBar = true
        openBehaviour = .direct
        exportScale = .one
        figureFormat = .png
        keepAwake = false
        offerLearnedDetector = true
        suppressPersistence = false
    }

    private static func decode<T: RawRepresentable>(
        _ key: String, from defaults: UserDefaults
    ) -> T? where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }

    private func persist<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == String {
        guard !suppressPersistence else { return }
        defaults.set(value.rawValue, forKey: key)
    }

    private func persist(_ value: Bool, forKey key: String) {
        guard !suppressPersistence else { return }
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let appearance = "prefs.appearance"
        static let mapColormap = "prefs.mapColormap"
        static let diffractionColormap = "prefs.diffractionColormap"
        static let intensityDisplay = "prefs.intensityDisplay"
        static let showScaleBar = "prefs.showScaleBar"
        static let openBehaviour = "prefs.openBehaviour"
        static let exportScale = "prefs.exportScale"
        static let figureFormat = "prefs.figureFormat"
        static let keepAwake = "prefs.keepAwake"
        static let offerLearnedDetector = "prefs.offerLearnedDetector"

        static let all = [
            appearance, mapColormap, diffractionColormap, intensityDisplay,
            showScaleBar, openBehaviour, exportScale, figureFormat, keepAwake,
            offerLearnedDetector,
        ]
    }
}
