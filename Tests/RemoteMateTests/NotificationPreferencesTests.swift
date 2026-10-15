import XCTest
@testable import RemoteMate

final class NotificationPreferencesTests: XCTestCase {
    @MainActor
    func testNotificationsDefaultOnAndRememberOptOut() {
        let suite = "RemoteMateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: defaults)
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.notifySleepChanges)
        preferences.notifySleepChanges = false
        Preferences.registerDefaults(in: defaults)
        XCTAssertFalse(Preferences(defaults: defaults).notifySleepChanges)
    }
}
