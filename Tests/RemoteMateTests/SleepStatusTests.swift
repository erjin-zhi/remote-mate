import XCTest
@testable import RemoteMate

final class SleepStatusTests: XCTestCase {
    private let pluggedIn = SleepStatus(power: .ac, idlePrevention: true, displayPrevention: true,
                                        lid: .enabled, lidChangeFailed: false)

    func testPendingAndCancelledLidChangeNeverClaimSleepWasRestored() {
        var pending = pluggedIn
        pending.power = .battery
        pending.idlePrevention = false
        pending.displayPrevention = false
        pending.lid = .changing
        XCTAssertTrue(pending.body.contains("正在切换"))
        XCTAssertFalse(pending.body.contains("合盖不休眠：已关闭"))
        var cancelled = pending
        cancelled.lid = .enabled
        cancelled.lidChangeFailed = true
        XCTAssertTrue(cancelled.body.contains("合盖不休眠：已开启"))
        XCTAssertTrue(cancelled.body.contains("合盖设置未完成"))
    }

    func testUnknownStateDoesNotClaimLidSleepIsAllowed() {
        var unknown = pluggedIn
        unknown.power = .unknown
        unknown.lid = .unknown
        XCTAssertTrue(unknown.powerDescription.contains("未知"))
        XCTAssertTrue(unknown.body.contains("暂时无法确认"))
        XCTAssertFalse(unknown.body.contains("合盖不休眠：已关闭"))
    }
}
