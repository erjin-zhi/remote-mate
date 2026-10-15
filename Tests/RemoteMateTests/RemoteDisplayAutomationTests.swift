import XCTest
@testable import RemoteMate

final class RemoteDisplayAutomationTests: XCTestCase {
    func testExternalDisplayKeepsRequirementSatisfiedAfterManualOnThenOff() {
        // 对应用户操作：接有外接屏时，手动打开再关闭虚拟屏。
        for active in [false, true, false] {
            XCTAssertTrue(RemoteDisplayAutomation.isRequirementSatisfied(
                hasExternal: true, skipIfExternal: true,
                isActive: active, isRebuilding: false
            ), "An available external display must keep remote mode healthy")
        }
    }

    func testMissingVirtualDisplayIsOnlySatisfiedByAllowedExternalDisplay() {
        for external in [false, true] {
            for skip in [false, true] {
                XCTAssertEqual(RemoteDisplayAutomation.isRequirementSatisfied(
                    hasExternal: external, skipIfExternal: skip,
                    isActive: false, isRebuilding: false
                ), external && skip)
                for (active, rebuilding) in [(true, false), (false, true)] {
                    XCTAssertTrue(RemoteDisplayAutomation.isRequirementSatisfied(
                        hasExternal: external, skipIfExternal: skip,
                        isActive: active, isRebuilding: rebuilding
                    ))
                }
            }
        }
    }

    /// 用屏幕状态模拟执行器，验证多轮插拔后动作与待补建状态仍然一致。
    private struct Session {
        var automation = RemoteDisplayAutomation()
        var remoteModeOn = true
        var includeDisplay = true
        var skipIfExternal = true
        var isActive = false
        var isRebuilding = false
        var powerAllowsDisplay = true

        mutating func connectExternal(_ connected: Bool) -> RemoteDisplayAutomation.Action {
            let action = automation.externalDisplayChanged(
                hasExternal: connected,
                remoteModeOn: remoteModeOn,
                includeDisplay: includeDisplay,
                skipIfExternal: skipIfExternal,
                isActive: isActive,
                isRebuilding: isRebuilding,
                powerAllowsDisplay: powerAllowsDisplay
            )
            switch action {
            case .none: break
            case .start: isActive = true
            case .stop:
                isActive = false
                isRebuilding = false
            }
            return action
        }
    }

    func testUnchangedExternalDisplayPreservesManualStartAndRebuild() {
        for rebuilding in [false, true] {
            var session = Session()
            XCTAssertEqual(session.connectExternal(true), .none)
            session.automation.isWaitingForExternalDisplay = true
            // 与 AppController 的手动开启回调一致，取消待补建但保留显示器基线。
            session.automation.cancelPendingStart()
            session.isActive = !rebuilding
            session.isRebuilding = rebuilding
            // 电池允许防休眠时拔电源，或接电时改电池偏好，powerAllowsDisplay 仍为 true。
            for _ in 0..<3 {
                XCTAssertEqual(session.connectExternal(true), .none)
                XCTAssertFalse(session.automation.isWaitingForExternalDisplay)
            }
            XCTAssertEqual(session.connectExternal(false), .none)
            XCTAssertEqual(session.connectExternal(true), .stop)
            XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        }
    }

    func testEnablingAutomationDoesNotInventExternalConnection() {
        for disabledSetting in 0..<3 {
            var session = Session()
            session.remoteModeOn = disabledSetting != 0
            session.includeDisplay = disabledSetting != 1
            session.skipIfExternal = disabledSetting != 2
            session.isActive = true
            XCTAssertEqual(session.connectExternal(true), .none)
            session.remoteModeOn = true
            session.includeDisplay = true
            session.skipIfExternal = true
            XCTAssertEqual(session.connectExternal(true), .none)
            XCTAssertTrue(session.isActive)
            XCTAssertEqual(session.connectExternal(false), .none)
            XCTAssertEqual(session.connectExternal(true), .stop)
        }
    }

    func testPowerPauseStillStopsManuallyStartedDisplayWithUnchangedExternalScreen() {
        var session = Session()
        XCTAssertEqual(session.connectExternal(true), .none)
        session.isActive = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(true), .stop)
        XCTAssertTrue(session.automation.isWaitingForPower)
        XCTAssertTrue(session.automation.isDisplayPausedForPower)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testWaitingForExternalDisplayDoesNotBecomeAPausedDisplayOnBattery() {
        var session = Session()
        XCTAssertEqual(session.connectExternal(true), .none)
        session.automation.isWaitingForExternalDisplay = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertTrue(session.automation.isWaitingForPower)
        XCTAssertFalse(session.automation.isDisplayPausedForPower)
        XCTAssertEqual(session.automation.powerWaitReason, .pendingCreation)
        // 重复系统事件不能把等待创建变成实际暂停。
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertFalse(session.automation.isDisplayPausedForPower)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.automation.powerWaitReason)
        XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testPendingCreationSurvivesUnplugOnBatteryAndStartsOnPowerRecovery() {
        var session = Session()
        session.automation.isWaitingForExternalDisplay = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertEqual(session.connectExternal(false), .none)
        XCTAssertEqual(session.automation.powerWaitReason, .pendingCreation)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testEnteringRemoteModeDistinguishesPendingCreationFromActualPowerPause() {
        for (active, rebuilding) in [(false, false), (true, false), (false, true)] {
            var automation = RemoteDisplayAutomation()
            automation.prepareForRemoteMode(powerAllowsDisplay: false, skipDisplay: true,
                                            isActive: active, isRebuilding: rebuilding)
            XCTAssertTrue(automation.isWaitingForPower)
            XCTAssertEqual(automation.isDisplayPausedForPower, active || rebuilding)
            automation.cancelPendingStart()
            XCTAssertNil(automation.powerWaitReason)
        }
    }

    func testRebuildPausedByBatteryRetainsItsReasonAcrossRepeatedEvents() {
        var session = Session()
        session.isRebuilding = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(false), .stop)
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertTrue(session.automation.isDisplayPausedForPower)
    }

    func testBatteryTransitionStopsDisplayForEitherDockEventOrder() {
        for powerArrivesFirst in [true, false] {
            var session = Session()
            session.automation.isWaitingForExternalDisplay = true
            if powerArrivesFirst {
                session.powerAllowsDisplay = false
                XCTAssertEqual(session.connectExternal(true), .none)
                XCTAssertEqual(session.connectExternal(false), .none)
            } else {
                XCTAssertEqual(session.connectExternal(false), .start)
                session.powerAllowsDisplay = false
                XCTAssertEqual(session.connectExternal(false), .stop)
            }
            XCTAssertFalse(session.isActive)
            XCTAssertTrue(session.automation.isWaitingForPower)
            XCTAssertEqual(session.connectExternal(false), .none)
            session.powerAllowsDisplay = true
            XCTAssertEqual(session.connectExternal(false), .start)
        }
    }

    func testBatteryPauseDoesNotDependOnExternalDisplaySkipPreference() {
        var session = Session()
        session.skipIfExternal = false
        session.isActive = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(false), .stop)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testBatteryPauseCancelsRebuildAndRestoresWhenPowerAllows() {
        var session = Session()
        session.isRebuilding = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(false), .stop)
        XCTAssertFalse(session.isRebuilding)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testRestoringPowerWithExternalScreenDefersUntilUnplug() {
        var session = Session()
        session.isActive = true
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(false), .stop)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertFalse(session.automation.isWaitingForPower)
        XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testBatteryPauseDoesNotReactivateManuallyDisabledDisplay() {
        var session = Session()
        session.powerAllowsDisplay = false
        XCTAssertEqual(session.connectExternal(false), .none)
        session.powerAllowsDisplay = true
        XCTAssertEqual(session.connectExternal(false), .none)
    }

    func testLeavingRemoteModeOrExcludingDisplayCancelsBatteryResume() {
        for excluded in [true, false] {
            var session = Session()
            session.isActive = true
            session.powerAllowsDisplay = false
            XCTAssertEqual(session.connectExternal(false), .stop)
            if excluded { session.includeDisplay = false } else { session.remoteModeOn = false }
            XCTAssertEqual(session.connectExternal(false), .none)
            XCTAssertFalse(session.automation.isWaitingForPower)
            session.powerAllowsDisplay = true
            XCTAssertEqual(session.connectExternal(false), .none)
        }
    }

    func testPausedDisplayDoesNotCountAsAnAvailableScreen() {
        XCTAssertFalse(RemoteDisplayAutomation.isRequirementSatisfied(
            hasExternal: false, skipIfExternal: true,
            isActive: false, isRebuilding: false
        ))
    }

    func testSkippedDisplayIsCreatedAndRemovedAcrossRepeatedReconnects() {
        var session = Session()
        session.automation.isWaitingForExternalDisplay = true

        for _ in 0..<3 {
            XCTAssertEqual(session.connectExternal(false), .start)
            XCTAssertTrue(session.isActive)
            XCTAssertFalse(session.automation.isWaitingForExternalDisplay)
            XCTAssertEqual(session.connectExternal(true), .stop)
            XCTAssertFalse(session.isActive)
            XCTAssertTrue(session.automation.isWaitingForExternalDisplay,
                          "Automatic removal must keep remote mode waiting for the next unplug")
            XCTAssertEqual(session.connectExternal(true), .none)
            XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        }
    }

    func testFirstConnectionAlsoStopsDisplayStartedWithoutExternalScreen() {
        var session = Session()
        session.isActive = true
        XCTAssertEqual(session.connectExternal(true), .stop)
        XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testConnectionDuringRebuildCancelsPendingDisplayCreation() {
        var session = Session()
        session.isRebuilding = true
        XCTAssertEqual(session.connectExternal(true), .stop)
        XCTAssertFalse(session.isRebuilding)
        XCTAssertTrue(session.automation.isWaitingForExternalDisplay)
        XCTAssertEqual(session.connectExternal(false), .start)
    }

    func testManualShutdownIsNotUndoneByHotPlugging() {
        var session = Session()
        XCTAssertEqual(session.connectExternal(true), .none)
        XCTAssertFalse(session.automation.isWaitingForExternalDisplay)
        XCTAssertEqual(session.connectExternal(false), .none)
        XCTAssertFalse(session.isActive)
    }

    func testAutomaticSwitchingRequiresRemoteModeAndBothDisplayPreferences() {
        for (mode, included, skip) in [(false, true, true), (true, false, true), (true, true, false)] {
            var session = Session()
            session.remoteModeOn = mode
            session.includeDisplay = included
            session.skipIfExternal = skip
            session.isActive = true
            XCTAssertEqual(session.connectExternal(true), .none)
            XCTAssertTrue(session.isActive)
            XCTAssertEqual(session.connectExternal(false), .none)
        }
    }

    func testPreferenceChangesNeverToggleTheCurrentDisplay() {
        var automation = RemoteDisplayAutomation()
        automation.prepareForRemoteMode(powerAllowsDisplay: false, skipDisplay: false,
                                        isActive: true, isRebuilding: false)
        XCTAssertTrue(automation.isDisplayPausedForPower)
        automation.preferencesChanged(includeDisplay: true, skipIfExternal: true)
        XCTAssertTrue(automation.isDisplayPausedForPower, "Ticking an option keeps the pending resume")
        automation.preferencesChanged(includeDisplay: false, skipIfExternal: true)
        XCTAssertFalse(automation.isWaitingForPower)

        automation.isWaitingForExternalDisplay = true
        automation.preferencesChanged(includeDisplay: true, skipIfExternal: false)
        XCTAssertFalse(automation.isWaitingForExternalDisplay)
    }

    func testDisablingAutomationWhileWaitingDoesNotCreateDisplayOnUnplug() {
        for (mode, included, skip) in [(false, true, true), (true, false, true), (true, true, false)] {
            var session = Session()
            session.automation.isWaitingForExternalDisplay = true
            session.remoteModeOn = mode
            session.includeDisplay = included
            session.skipIfExternal = skip
            XCTAssertEqual(session.connectExternal(false), .none)
            XCTAssertFalse(session.isActive)
            XCTAssertFalse(session.automation.isWaitingForExternalDisplay)
        }
    }
}
