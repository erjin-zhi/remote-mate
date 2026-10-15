import XCTest
@testable import RemoteMate

final class FeatureStatusTests: XCTestCase {
    private var idle: FeatureStatus {
        FeatureStatus(sleep: SleepStatus(power: .ac, idlePrevention: false, displayPrevention: false,
                                        lid: .disabled, lidChangeFailed: false),
                      remoteMode: false, virtualScreen: .disabled, uuKeepAlive: false)
    }

    private var remoteOn: FeatureStatus {
        var status = idle
        status.remoteMode = true
        status.sleep.idlePrevention = true
        status.sleep.displayPrevention = true
        status.sleep.lid = .enabled
        status.virtualScreen = .enabled
        return status
    }

    private func primed(_ status: FeatureStatus) -> FeatureStatusChanges {
        var changes = FeatureStatusChanges()
        XCTAssertNil(changes.notice(for: status))
        return changes
    }

    func testOneClickModeWaitsForLidAuthorizationAndSendsOneResult() {
        var changes = primed(idle)
        var pending = remoteOn
        pending.sleep.lid = .changing
        XCTAssertNil(changes.notice(for: pending), "Admin prompt pending: wait for the actual result")
        let notice = changes.notice(for: remoteOn)
        XCTAssertEqual(notice?.title, "远程模式已开启")
        XCTAssertEqual(notice?.body, "生效中：防休眠（屏幕常亮）、合盖不休眠、虚拟屏幕")
        XCTAssertNil(changes.notice(for: remoteOn))

        let off = changes.notice(for: idle)
        XCTAssertEqual(off?.title, "远程模式已关闭")
        XCTAssertEqual(off?.body, "Mac 将按系统设置休眠")
    }

    func testRemoteModeReportsLidFailureInsteadOfClaimingSuccess() {
        var changes = primed(idle)
        var failed = remoteOn
        failed.sleep.lid = .disabled
        failed.sleep.lidChangeFailed = true
        let notice = changes.notice(for: failed)!
        XCTAssertEqual(notice.title, "远程模式已开启")
        XCTAssertFalse(notice.body.contains("合盖不休眠、"))
        XCTAssertTrue(notice.body.contains("合盖不休眠设置未完成"))
    }

    func testStartingDisplayOnlyModeOnBatteryReportsPendingCreation() {
        var battery = idle
        battery.sleep.power = .battery
        var changes = primed(battery)
        battery.remoteMode = true
        battery.virtualScreen = .waitingForPower
        let notice = changes.notice(for: battery)
        XCTAssertEqual(notice?.title, "远程模式已暂停")
        XCTAssertEqual(notice?.body, "使用电池中，接通电源后创建虚拟屏幕")

        changes = primed(idle)
        battery.sleep.lid = .enabled
        let partiallyActive = changes.notice(for: battery)
        XCTAssertEqual(partiallyActive?.title, "远程模式已开启")
        XCTAssertEqual(partiallyActive?.body, "生效中：合盖不休眠；虚拟屏幕待接电后创建")
    }

    func testManualTogglesInPanelDoNotNotify() {
        var changes = primed(idle)
        var current = idle
        current.sleep.idlePrevention = true
        XCTAssertNil(changes.notice(for: current))
        current.sleep.displayPrevention = true
        XCTAssertNil(changes.notice(for: current))
        current.sleep.lid = .changing
        XCTAssertNil(changes.notice(for: current))
        current.sleep.lid = .enabled
        XCTAssertNil(changes.notice(for: current))
        current.virtualScreen = .enabled
        XCTAssertNil(changes.notice(for: current))
        current.virtualScreen = .rebuilding
        XCTAssertNil(changes.notice(for: current))
        current.virtualScreen = .enabled
        XCTAssertNil(changes.notice(for: current))
        current.uuKeepAlive = true
        XCTAssertNil(changes.notice(for: current))
    }

    func testUnpluggingThatPausesPreventionIsReported() {
        var changes = primed(remoteOn)
        var battery = remoteOn
        battery.sleep.power = .battery
        battery.sleep.idlePrevention = false
        battery.sleep.displayPrevention = false
        battery.sleep.lid = .changing
        let pending = changes.notice(for: battery)
        XCTAssertEqual(pending?.title, "已切换到电池供电")
        XCTAssertEqual(pending?.body, "空闲防休眠已关闭；合盖设置正在切换，可能需要管理员授权")
        XCTAssertNil(changes.notice(for: battery))
        battery.sleep.lid = .disabled
        let notice = changes.notice(for: battery)
        XCTAssertEqual(notice?.title, "已切换到电池供电")
        XCTAssertEqual(notice?.body, "防休眠已暂停，Mac 可能进入休眠")

        let back = changes.notice(for: remoteOn)
        XCTAssertEqual(back?.title, "已接通电源")
        XCTAssertEqual(back?.body, "当前生效：防休眠（屏幕常亮）、合盖不休眠")
    }

    func testPowerChangeIsQuietUnlessItMattersForRemote() {
        var changes = primed(idle)
        var battery = idle
        battery.sleep.power = .battery
        XCTAssertNil(changes.notice(for: battery), "Nothing enabled and remote mode off")

        changes = primed(remoteOn)
        var stillProtected = remoteOn
        stillProtected.sleep.power = .battery
        let notice = changes.notice(for: stillProtected)
        XCTAssertEqual(notice?.title, "已切换到电池供电")
        XCTAssertEqual(notice?.body, "防休眠继续生效")
    }

    func testPowerNoticeIncludesDisplayPauseAndSettledRecovery() {
        var changes = primed(remoteOn)
        var battery = remoteOn
        battery.sleep.power = .battery
        battery.sleep.idlePrevention = false
        battery.sleep.displayPrevention = false
        battery.sleep.lid = .disabled
        battery.virtualScreen = .pausedForBattery
        let paused = changes.notice(for: battery)
        XCTAssertEqual(paused?.title, "已切换到电池供电")
        XCTAssertEqual(paused?.body, "防休眠已暂停，Mac 可能进入休眠；虚拟屏幕已暂停")
        XCTAssertNil(changes.notice(for: battery))

        var rebuilding = remoteOn
        rebuilding.virtualScreen = .rebuilding
        XCTAssertNil(changes.notice(for: rebuilding))
        let restored = changes.notice(for: remoteOn)
        XCTAssertEqual(restored?.title, "已接通电源")
        XCTAssertEqual(restored?.body, "当前生效：防休眠（屏幕常亮）、合盖不休眠；虚拟屏幕已恢复")
        XCTAssertNil(changes.notice(for: remoteOn))
    }

    func testDisplayChangeAloneQualifiesForPowerNotice() {
        var enabled = idle
        enabled.virtualScreen = .enabled
        var changes = primed(enabled)
        var battery = enabled
        battery.sleep.power = .battery
        battery.virtualScreen = .pausedForBattery
        XCTAssertEqual(changes.notice(for: battery)?.body,
                       "防休眠未开启，Mac 可能进入休眠；虚拟屏幕已暂停")
        XCTAssertEqual(changes.notice(for: enabled)?.body,
                       "防休眠未开启，Mac 可能进入休眠；虚拟屏幕已恢复")
    }

    func testPowerRecoveryWithExternalDisplayDoesNotClaimDisplayRestored() {
        var battery = remoteOn
        battery.sleep.power = .battery
        battery.virtualScreen = .pausedForBattery
        var changes = primed(battery)
        var waiting = remoteOn
        waiting.virtualScreen = .waiting
        waiting.hasExternalDisplay = true
        let notice = changes.notice(for: waiting)
        XCTAssertEqual(notice?.title, "已接通电源")
        XCTAssertEqual(notice?.body, "防休眠继续生效；虚拟屏幕等待外接显示器断开后恢复")
        XCTAssertEqual(changes.notice(for: remoteOn)?.title, "外接显示器已断开")
    }

    func testFailedDisplayRecoveryDoesNotClaimSuccess() {
        var battery = remoteOn
        battery.sleep.power = .battery
        battery.virtualScreen = .pausedForBattery
        var changes = primed(battery)
        var failed = remoteOn
        failed.virtualScreen = .disabled
        failed.displayError = "创建虚拟屏幕失败"
        let notice = changes.notice(for: failed)
        XCTAssertEqual(notice?.title, "已接通电源")
        XCTAssertEqual(notice?.body, "防休眠继续生效；创建虚拟屏幕失败")
    }

    func testPowerNoticeDoesNotWaitForLidAuthorizationAndReportsCancellation() {
        var changes = primed(remoteOn)
        var pending = remoteOn
        pending.sleep.power = .battery
        pending.sleep.idlePrevention = false
        pending.sleep.displayPrevention = false
        pending.sleep.lid = .changing
        pending.virtualScreen = .pausedForBattery
        let notice = changes.notice(for: pending)
        XCTAssertEqual(notice?.title, "已切换到电池供电")
        XCTAssertEqual(notice?.body, "空闲防休眠已关闭；合盖设置正在切换，可能需要管理员授权；虚拟屏幕已暂停")
        XCTAssertNil(changes.notice(for: pending), "Repeated pending snapshots must not repeat the alert")

        pending.sleep.lid = .enabled
        pending.sleep.lidChangeFailed = true
        let cancelled = changes.notice(for: pending)
        XCTAssertEqual(cancelled?.title, "已切换到电池供电")
        XCTAssertTrue(cancelled?.body.contains("合盖不休眠") == true)
        XCTAssertTrue(cancelled?.body.contains("合盖不休眠设置未完成") == true)
        XCTAssertFalse(cancelled?.body.contains("防休眠已暂停") == true)
        XCTAssertNil(changes.notice(for: pending))
    }

    func testPowerReconnectedDuringAuthorizationReportsLatestState() {
        var changes = primed(remoteOn)
        var pending = remoteOn
        pending.sleep.power = .battery
        pending.sleep.lid = .changing
        pending.virtualScreen = .pausedForBattery
        XCTAssertEqual(changes.notice(for: pending)?.title, "已切换到电池供电")
        pending.sleep.power = .ac
        pending.virtualScreen = .rebuilding
        let reconnecting = changes.notice(for: pending)
        XCTAssertEqual(reconnecting?.title, "已接通电源")
        XCTAssertTrue(reconnecting?.body.contains("虚拟屏幕正在重建") == true)
        XCTAssertFalse(reconnecting?.body.contains("虚拟屏幕已恢复") == true)
        XCTAssertNil(changes.notice(for: pending))
        let settled = changes.notice(for: remoteOn)
        XCTAssertEqual(settled?.title, "已接通电源")
        XCTAssertTrue(settled?.body.contains("虚拟屏幕已恢复") == true)
        XCTAssertFalse(settled?.body.contains("正在切换") == true)
        XCTAssertNil(changes.notice(for: remoteOn))
    }

    func testExternalDisplayAutomationIsReported() {
        var changes = primed(remoteOn)
        var waiting = remoteOn
        waiting.virtualScreen = .waiting
        waiting.hasExternalDisplay = true
        XCTAssertEqual(changes.notice(for: waiting)?.title, "已接入外接显示器")
        XCTAssertEqual(changes.notice(for: remoteOn)?.title, "外接显示器已断开")
    }

    func testManualStartWhileWaitingIsNotReportedAsDisconnect() {
        var waiting = remoteOn
        waiting.virtualScreen = .waiting
        waiting.hasExternalDisplay = true
        var changes = primed(waiting)
        var manual = waiting
        manual.virtualScreen = .enabled
        XCTAssertNil(changes.notice(for: manual), "External display still attached: user turned the screen on")
    }

    func testPowerChangeWhileWaitingForExternalDisplayDoesNotClaimPauseOrRecovery() {
        var waiting = remoteOn
        waiting.virtualScreen = .waiting
        var changes = primed(waiting)
        var battery = waiting
        battery.sleep.power = .battery
        battery.virtualScreen = .waitingForPower
        let unplugged = changes.notice(for: battery)
        XCTAssertEqual(unplugged?.title, "已切换到电池供电")
        XCTAssertEqual(unplugged?.body, "防休眠继续生效；虚拟屏幕将在接通电源后创建")
        XCTAssertFalse(unplugged?.body.contains("虚拟屏幕已暂停") == true)
        let pluggedIn = changes.notice(for: waiting)
        XCTAssertEqual(pluggedIn?.title, "已接通电源")
        XCTAssertTrue(pluggedIn?.body.contains("仍等待外接显示器断开后创建") == true)
        XCTAssertFalse(pluggedIn?.body.contains("已恢复") == true)
    }

    func testPowerRecoveryCreatesPreviouslyUncreatedScreen() {
        var battery = remoteOn
        battery.sleep.power = .battery
        battery.virtualScreen = .waitingForPower
        var changes = primed(battery)
        let notice = changes.notice(for: remoteOn)
        XCTAssertEqual(notice?.title, "已接通电源")
        XCTAssertTrue(notice?.body.contains("虚拟屏幕已创建") == true)
        XCTAssertFalse(notice?.body.contains("已恢复") == true)
    }

    func testFailuresAreReportedOnceAndRecoveryIsQuiet() {
        var changes = primed(idle)
        var current = idle
        current.displayError = "创建虚拟屏幕失败"
        XCTAssertEqual(changes.notice(for: current)?.title, "创建虚拟屏幕失败")
        XCTAssertNil(changes.notice(for: current))
        current.displayError = nil
        XCTAssertNil(changes.notice(for: current))

        current.sleep.lid = .enabled
        _ = changes.notice(for: current)
        current.sleep.lidChangeFailed = true
        let failure = changes.notice(for: current)
        XCTAssertEqual(failure?.title, "合盖不休眠设置未完成")
        XCTAssertEqual(failure?.body, "合盖不休眠仍在生效")
    }

    func testInitialLidReadDoesNotNotify() {
        var current = idle
        current.sleep.lid = .unknown
        var changes = primed(current)
        current.sleep.lid = .enabled
        XCTAssertNil(changes.notice(for: current))
    }
}
