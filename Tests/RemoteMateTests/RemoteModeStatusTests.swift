import XCTest
@testable import RemoteMate

final class RemoteModeStatusTests: XCTestCase {
    func testDisplayOnlyBatteryPauseKeepsSessionButDoesNotClaimEnabled() {
        let status = RemoteModeStatus(otherParts: [], displaySatisfied: false, displayPaused: true)
        XCTAssertEqual(status.state(remoteModeOn: true), .paused)
        XCTAssertFalse(status.shouldExit(hadOtherEnabled: false))
        XCTAssertEqual(status.state(remoteModeOn: false), .off)
    }

    func testBatteryPauseWithOtherEnabledPartsIsPartial() {
        let status = RemoteModeStatus(otherParts: [true], displaySatisfied: false, displayPaused: true)
        XCTAssertEqual(status.state(remoteModeOn: true), .partial)
        XCTAssertFalse(status.shouldExit(hadOtherEnabled: true))
    }

    func testTurningOffLastOtherPartDuringPauseEndsSession() {
        let status = RemoteModeStatus(otherParts: [false, false], displaySatisfied: false, displayPaused: true)
        XCTAssertTrue(status.shouldExit(hadOtherEnabled: true))
        // 同样的空闲状态如果仅来自供电暂停，不应取消后续恢复。
        XCTAssertFalse(status.shouldExit(hadOtherEnabled: false))
    }

    func testPowerRecoveryReturnsDisplayOnlySessionToEnabled() {
        let status = RemoteModeStatus(otherParts: [], displaySatisfied: true, displayPaused: false)
        XCTAssertEqual(status.state(remoteModeOn: true), .on)
        XCTAssertFalse(status.shouldExit(hadOtherEnabled: false))
    }

    func testManuallyDisabledDisplayDoesNotKeepSessionAlive() {
        let status = RemoteModeStatus(otherParts: [], displaySatisfied: false, displayPaused: false)
        XCTAssertEqual(status.state(remoteModeOn: true), .off)
        XCTAssertTrue(status.shouldExit(hadOtherEnabled: false))
    }

    func testUsableExternalDisplayStillKeepsSessionEnabled() {
        let status = RemoteModeStatus(otherParts: [], displaySatisfied: true, displayPaused: true)
        XCTAssertEqual(status.state(remoteModeOn: true), .on)
        XCTAssertFalse(status.shouldExit(hadOtherEnabled: true))
    }

    func testExitingPausedSessionCancelsLaterPowerRecovery() {
        var automation = RemoteDisplayAutomation()
        XCTAssertEqual(automation.externalDisplayChanged(
            hasExternal: false, remoteModeOn: true, includeDisplay: true,
            skipIfExternal: true, isActive: true, isRebuilding: false,
            powerAllowsDisplay: false
        ), .stop)
        let status = RemoteModeStatus(otherParts: [false], displaySatisfied: false,
                                      displayPaused: automation.isWaitingForPower)
        XCTAssertTrue(status.shouldExit(hadOtherEnabled: true))
        automation.cancelPendingStart()
        XCTAssertFalse(automation.isWaitingForPower)
        XCTAssertEqual(automation.externalDisplayChanged(
            hasExternal: false, remoteModeOn: false, includeDisplay: true,
            skipIfExternal: true, isActive: false, isRebuilding: false,
            powerAllowsDisplay: true
        ), .none)
    }
}
