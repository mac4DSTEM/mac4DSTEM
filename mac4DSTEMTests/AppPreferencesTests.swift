import XCTest
import SwiftUI
import Observation
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Pins `AppPreferences` (session S21, `ROADMAP.md` "Settings window,
/// Xcode-style sidebar") and the two seams `AppState` reaches it through:
/// the primary "Open Dataset…" behaviour and a fresh window's starting
/// colormap/intensity/engine choice. Every test uses a private
/// `UserDefaults` suite — never `.standard` — so a run here can never plant
/// a preference another test, or the real app, reads back (the same hazard
/// `SessionSidecarLocatorTests` guards against for bookmarks).
@MainActor
final class AppPreferencesTests: XCTestCase {

    /// A scratch suite, cleaned up when the test ends — the
    /// `SessionSidecarLocatorTests` shape.
    private func scratchDefaults() -> (UserDefaults, () -> Void) {
        let suite = "mac4dstem.tests.apppreferences.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("could not make a scratch defaults suite")
            return (.standard, {})
        }
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    // MARK: Defaults equal today's shipped behaviour

    /// BREAK-FIRST evidence, 2026-09-21: temporarily changed `showScaleBar`'s
    /// default from `true` to `false` in `AppPreferences.swift` and reran this
    /// test alone (`-only-testing:mac4DSTEMTests/AppPreferencesTests/testEveryKeyDefaultsToTodaysBehaviour`)
    /// — failed red (exit 65), reverted, reran green. Not vacuous.
    func testEveryKeyDefaultsToTodaysBehaviour() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let prefs = AppPreferences(defaults: defaults)

        XCTAssertEqual(prefs.appearance, .system)
        XCTAssertEqual(prefs.mapColormap, .viridis)
        XCTAssertEqual(prefs.diffractionColormap, .viridis)
        XCTAssertEqual(prefs.intensityDisplay, .log)
        XCTAssertTrue(prefs.showScaleBar)
        XCTAssertEqual(prefs.openBehaviour, .direct)
        XCTAssertFalse(prefs.keepAwake)
        XCTAssertEqual(prefs.logVerbosity, .normal)
        XCTAssertEqual(prefs.enginePreference, .automatic)
        XCTAssertTrue(prefs.offerLearnedDetector)
    }

    // MARK: Round-trip through a private suite

    /// Writes through one instance, reads back through a SECOND instance over
    /// the SAME suite — proves persistence in the store, not just an
    /// in-memory property the first instance happened to remember.
    func testEveryKeyRoundTripsThroughItsOwnSuite() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let writer = AppPreferences(defaults: defaults)

        writer.appearance = .dark
        writer.mapColormap = .rdbu
        writer.diffractionColormap = .inferno
        writer.intensityDisplay = .linear
        writer.showScaleBar = false
        writer.openBehaviour = .options
        writer.keepAwake = true
        writer.logVerbosity = .verbose
        writer.enginePreference = .metal
        writer.offerLearnedDetector = false

        let reader = AppPreferences(defaults: defaults)
        XCTAssertEqual(reader.appearance, .dark)
        XCTAssertEqual(reader.mapColormap, .rdbu)
        XCTAssertEqual(reader.diffractionColormap, .inferno)
        XCTAssertEqual(reader.intensityDisplay, .linear)
        XCTAssertFalse(reader.showScaleBar)
        XCTAssertEqual(reader.openBehaviour, .options)
        XCTAssertTrue(reader.keepAwake)
        XCTAssertEqual(reader.logVerbosity, .verbose)
        XCTAssertEqual(reader.enginePreference, .metal)
        XCTAssertFalse(reader.offerLearnedDetector)
    }

    func testPreferenceWritesInvalidateObservation() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let prefs = AppPreferences(defaults: defaults)
        let changed = expectation(description: "preference write invalidated observation")

        withObservationTracking {
            _ = prefs.showScaleBar
        } onChange: {
            changed.fulfill()
        }
        prefs.showScaleBar = false

        wait(for: [changed], timeout: 1)
    }

    // MARK: Reset restores every default

    /// BREAK-FIRST evidence, 2026-09-21: temporarily removed `enginePreference`
    /// from `Keys.all` (a "skip one key" mutation) and reran this test alone
    /// — failed red (exit 65: `enginePreference` stayed `.metal` instead of
    /// resetting to `.automatic`), reverted, reran green.
    func testResetRestoresEveryKeyToItsDefault() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let prefs = AppPreferences(defaults: defaults)

        prefs.appearance = .light
        prefs.mapColormap = .gray
        prefs.diffractionColormap = .gray
        prefs.intensityDisplay = .linear
        prefs.showScaleBar = false
        prefs.openBehaviour = .options
        prefs.keepAwake = true
        prefs.logVerbosity = .verbose
        prefs.enginePreference = .metal
        prefs.offerLearnedDetector = false

        prefs.resetAllToDefaults()

        XCTAssertEqual(prefs.appearance, .system)
        XCTAssertEqual(prefs.mapColormap, .viridis)
        XCTAssertEqual(prefs.diffractionColormap, .viridis)
        XCTAssertEqual(prefs.intensityDisplay, .log)
        XCTAssertTrue(prefs.showScaleBar)
        XCTAssertEqual(prefs.openBehaviour, .direct)
        XCTAssertFalse(prefs.keepAwake)
        XCTAssertEqual(prefs.logVerbosity, .normal)
        XCTAssertEqual(prefs.enginePreference, .automatic)
        XCTAssertTrue(prefs.offerLearnedDetector)
    }

    // MARK: Theme → ColorScheme? (pure)

    func testAppearanceMapsToColorSchemeExactly() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    // MARK: AppState reads the defaults at construction

    /// The seam is `AppState.init`, not a re-applied default: a fresh
    /// window's diffraction/map colormap, intensity display and ACOM engine
    /// start from the preference. Nothing here claims an analysis's own
    /// colormap choice (a diverging strain/DPC map) is affected — that stays
    /// untouched, per `AppState+ResultPresentation.swift`/`AppState+DPC.swift`.
    func testAppStateSeedsItsDisplayDefaultsFromPreferences() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let prefs = AppPreferences(defaults: defaults)
        prefs.diffractionColormap = .inferno
        prefs.mapColormap = .rdbu
        prefs.intensityDisplay = .linear
        prefs.enginePreference = .metal

        let appState = AppState(preferences: prefs)

        XCTAssertEqual(appState.patternColormap, .inferno)
        XCTAssertEqual(appState.resultPresentation.resultColormap, .rdbu)
        XCTAssertFalse(appState.logScale)
        XCTAssertEqual(appState.acomSession.backend, .metal)
    }

    /// `requestOpenDataset()` is the shared "Open Dataset…" gesture; the
    /// separate, always-explicit `requestOpenDatasetWithOptions()` is
    /// untouched by this preference (asserted second, below).
    func testRequestOpenDatasetHonoursThePreferenceButOptionsStaysExplicit() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let prefs = AppPreferences(defaults: defaults)
        prefs.openBehaviour = .options

        let appState = AppState(preferences: prefs)
        appState.requestOpenDataset()
        XCTAssertTrue(appState.configureOnOpen)

        prefs.openBehaviour = .direct
        appState.requestOpenDataset()
        XCTAssertFalse(appState.configureOnOpen)

        appState.requestOpenDatasetWithOptions()
        XCTAssertTrue(appState.configureOnOpen)
    }

    // MARK: A bare AppState() must never read the owner's real UserDefaults

    /// Finding C (adversarial review, 2026-09-21): before the fix,
    /// `AppState.init`'s `preferences` fallback was `AppPreferences()`, whose
    /// default store is `UserDefaults.standard` — and this test target runs
    /// HOSTED INSIDE mac4DSTEM.app under the unit gate, so `.standard` IS the
    /// app's own domain. A colormap the owner changed in Settings would then
    /// seed every one of the ~123 bare `AppState()`/`AppState(recents:)` call
    /// sites across mac4DSTEMTests. This test plants a marker directly under
    /// the real `prefs.mapColormap` key `AppPreferences` itself uses
    /// (`Session/AppPreferences.swift`'s `Keys.mapColormap`), constructs a
    /// bare `AppState()`, and asserts the marker did NOT seed it — the marker
    /// is removed in `defer` unconditionally, so a failing assertion here can
    /// never leave a stray key in the owner's real prefs.
    ///
    /// BREAK-FIRST evidence, 2026-09-21: reverted `AppState.init`'s fallback
    /// to `AppPreferences()` (dropping `scratchPreferencesDefaults()`) and
    /// reran this test alone
    /// (`-only-testing:mac4DSTEMTests/AppPreferencesTests/testBareAppStateNeverReadsTheOwnersRealUserDefaults`)
    /// — failed red (exit 65: `resultColormap` came back `.inferno`, the
    /// planted marker), reverted, reran green.
    func testBareAppStateNeverReadsTheOwnersRealUserDefaults() {
        let key = "prefs.mapColormap"
        let priorValue = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(ColormapKind.inferno.rawValue, forKey: key)
        defer {
            if let priorValue {
                UserDefaults.standard.set(priorValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let appState = AppState()

        XCTAssertNotEqual(
            appState.resultPresentation.resultColormap, .inferno,
            "a bare AppState() must never seed from the real UserDefaults.standard"
        )
    }
}
