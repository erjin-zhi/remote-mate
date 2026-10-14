import XCTest
@testable import RemoteMate

@MainActor
final class UUPreferencesTests: XCTestCase {
    func testNewInstallDefaultsToOneShotLaunchWithoutKeepAlive() {
        let suite = "RemoteMateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: defaults)
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.launchUU)
        XCTAssertFalse(prefs.keepUUAlive)
    }

    func testExistingLaunchPreferenceDoesNotOptIntoKeepAlive() {
        for launch in [false, true] {
            let suite = "RemoteMateTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(launch, forKey: Preferences.Keys.launchUU)
            Preferences.registerDefaults(in: defaults)
            let prefs = Preferences(defaults: defaults)
            XCTAssertEqual(prefs.launchUU, launch)
            XCTAssertFalse(prefs.keepUUAlive)
        }
    }

    func testKeepAliveIsSavedIndependentlyFromLaunchPreference() {
        let suite = "RemoteMateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: defaults)
        let prefs = Preferences(defaults: defaults)
        prefs.keepUUAlive = true
        prefs.launchUU = false
        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.launchUU)
        XCTAssertTrue(reloaded.keepUUAlive, "Disabling automatic launch preserves the inactive keep-alive choice")
    }
}
