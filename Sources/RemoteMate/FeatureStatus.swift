import Foundation

struct StatusNotice: Equatable {
    var title: String
    var body: String
}

/// 通知只关心实际生效的状态；偏好开关由用户在面板里直接操作，面板已有反馈。
struct FeatureStatus: Equatable {
    enum VirtualScreen: Equatable {
        case enabled, disabled, rebuilding
        /// 远程模式因接有外接显示器而暂停虚拟屏幕，拔掉后自动创建。
        case waiting
        /// 远程模式因电池供电暂停虚拟屏幕，供电允许后自动恢复。
        case pausedForBattery
        /// 尚未创建的屏幕等待供电，不能描述成已暂停或已恢复。
        case waitingForPower
    }

    var sleep: SleepStatus
    var remoteMode: Bool
    var virtualScreen: VirtualScreen
    var uuKeepAlive: Bool
    /// 用于区分插拔触发的切换和手动开关虚拟屏幕
    var hasExternalDisplay = false
    var sleepError: String?
    var displayError: String?

    /// 合盖切换（可能在等管理员授权）和虚拟屏幕重建都是中间态，等结果落定再比较。
    var isSettling: Bool {
        sleep.lid == .changing || virtualScreen == .rebuilding
    }

    fileprivate var activeFeatures: [String] {
        var names: [String] = []
        if sleep.idlePrevention { names.append(sleep.displayPrevention ? "防休眠（屏幕常亮）" : "防休眠") }
        if sleep.lid == .enabled { names.append("合盖不休眠") }
        if virtualScreen == .enabled { names.append("虚拟屏幕") }
        if uuKeepAlive { names.append("UU 保活") }
        return names
    }
}

/// 只在远程会话真正受影响时通知：
/// - 远程模式开启 / 关闭（含自动开启、各项被关完后自动退出）；
/// - 插拔电源导致防休眠、合盖不休眠或虚拟屏幕实际状态改变，或远程模式下供电变化；
/// - 插拔外接显示器触发虚拟屏幕自动关闭 / 重建；
/// - 合盖设置失败、防休眠或虚拟屏幕出错。
/// 供电变化不等待合盖授权，先告知已确认状态，再在切换结束后补充结果。
struct FeatureStatusChanges {
    private var previous: FeatureStatus?
    private var pendingPower: FeatureStatus?

    mutating func notice(for current: FeatureStatus) -> StatusNotice? {
        if current.sleep.lid == .changing,
           let powerBaseline = pendingPower ?? previous,
           powerBaseline.sleep.power != current.sleep.power,
           let notice = powerNotice(from: powerBaseline, to: current, failures: []) {
            pendingPower = current
            return notice
        }
        // 中间态不更新基线，落定后与操作前比较，一次操作只发一条最终结果。
        guard !current.isSettling else { return nil }
        defer {
            previous = current
            pendingPower = nil
        }
        guard let old = previous else { return nil }

        let failures = Self.failures(from: old, to: current)

        if old.remoteMode != current.remoteMode {
            return remoteModeNotice(current, failures: failures)
        }
        // 授权期间可能反复插拔，最终即使回到原供电状态也要补充合盖结果。
        let powerBaseline = old.sleep.power != current.sleep.power ? old : (pendingPower ?? old)
        if old.sleep.power != current.sleep.power || pendingPower != nil,
           let notice = powerNotice(from: powerBaseline, to: current, failures: failures) {
            return notice
        }
        if let notice = displayAutomationNotice(from: old, to: current, failures: failures) {
            return notice
        }
        if let first = failures.first {
            return StatusNotice(title: first.title, body: ([first.body] + failures.dropFirst().map(\.title))
                .filter { !$0.isEmpty }.joined(separator: "；"))
        }
        return nil
    }

    private func remoteModeNotice(_ current: FeatureStatus, failures: [StatusNotice]) -> StatusNotice {
        let features = current.activeFeatures
        if current.remoteMode && current.virtualScreen == .waitingForPower && features.isEmpty {
            return StatusNotice(title: "远程模式已暂停",
                                body: Self.join("使用电池中，接通电源后创建虚拟屏幕", failures))
        }
        if current.remoteMode && current.virtualScreen == .pausedForBattery && features.isEmpty {
            return StatusNotice(title: "远程模式已暂停",
                                body: Self.join("虚拟屏幕因电池供电暂停，接电或开启电池防休眠后自动恢复", failures))
        }
        var body: String
        if current.remoteMode {
            body = features.isEmpty ? "当前没有功能生效，请打开远程伴侣检查" : "生效中：\(features.joined(separator: "、"))"
            if current.virtualScreen == .waitingForPower { body += "；虚拟屏幕待接电后创建" }
        } else {
            body = features.isEmpty ? "Mac 将按系统设置休眠" : "仍在生效：\(features.joined(separator: "、"))"
        }
        return StatusNotice(title: current.remoteMode ? "远程模式已开启" : "远程模式已关闭",
                            body: Self.join(body, failures))
    }

    private func powerNotice(from old: FeatureStatus, to current: FeatureStatus, failures: [StatusNotice]) -> StatusNotice? {
        let idleChanged = old.sleep.idlePrevention != current.sleep.idlePrevention
        // 合盖状态从未知变为已知只是读取完成，不算插拔电源造成的变化。
        let lidChanged = old.sleep.lid != current.sleep.lid && old.sleep.lid != .unknown && current.sleep.lid != .unknown
        let displayPaused = old.virtualScreen != .pausedForBattery && current.virtualScreen == .pausedForBattery
        let displayRestored = (old.virtualScreen == .pausedForBattery || old.virtualScreen == .rebuilding)
            && current.virtualScreen == .enabled
        let displayWaiting = old.virtualScreen == .pausedForBattery && current.virtualScreen == .waiting
        guard current.remoteMode || idleChanged || lidChanged || displayPaused || displayRestored || displayWaiting else { return nil }

        let title: String
        switch current.sleep.power {
        case .ac: title = "已接通电源"
        case .battery: title = "已切换到电池供电"
        case .unknown: title = "供电状态未知"
        }
        var body: String
        if current.sleep.lid == .changing {
            body = current.sleep.idlePrevention ? "空闲防休眠生效中" : "空闲防休眠已关闭"
            body += "；合盖设置正在切换，可能需要管理员授权"
        } else if idleChanged || lidChanged {
            let paused = !current.sleep.idlePrevention && current.sleep.lid != .enabled
            let features = current.activeFeatures.filter { $0 != "虚拟屏幕" && $0 != "UU 保活" }
            body = paused ? "防休眠已暂停，Mac 可能进入休眠" : "当前生效：\(features.joined(separator: "、"))"
        } else {
            body = current.sleep.idlePrevention ? "防休眠继续生效" : "防休眠未开启，Mac 可能进入休眠"
        }
        if displayPaused { body += "；虚拟屏幕已暂停" }
        if displayRestored { body += "；虚拟屏幕已恢复" }
        if displayWaiting { body += "；虚拟屏幕等待外接显示器断开后恢复" }
        if current.virtualScreen == .waitingForPower {
            body += "；虚拟屏幕将在接通电源后创建"
        }
        if old.virtualScreen == .waitingForPower && current.virtualScreen == .waiting {
            body += "；虚拟屏幕仍等待外接显示器断开后创建"
        }
        if old.virtualScreen == .waitingForPower && current.virtualScreen == .enabled {
            body += "；虚拟屏幕已创建"
        }
        if current.virtualScreen == .rebuilding { body += "；虚拟屏幕正在重建" }
        return StatusNotice(title: title, body: Self.join(body, failures))
    }

    private func displayAutomationNotice(from old: FeatureStatus, to current: FeatureStatus,
                                         failures: [StatusNotice]) -> StatusNotice? {
        switch (old.virtualScreen, current.virtualScreen) {
        case (.enabled, .waiting) where current.hasExternalDisplay:
            return StatusNotice(title: "已接入外接显示器",
                                body: Self.join("虚拟屏幕已关闭，拔掉外接显示器后自动重建", failures))
        // 等待期间用户手动打开虚拟屏幕时外接屏仍在，不能说成「已断开」
        case (.waiting, .enabled) where !current.hasExternalDisplay:
            return StatusNotice(title: "外接显示器已断开", body: Self.join("虚拟屏幕已重新创建", failures))
        default:
            return nil
        }
    }

    private static func failures(from old: FeatureStatus, to current: FeatureStatus) -> [StatusNotice] {
        var result: [StatusNotice] = []
        if current.sleep.lidChangeFailed && !old.sleep.lidChangeFailed {
            result.append(StatusNotice(
                title: "合盖不休眠设置未完成",
                body: current.sleep.lid == .enabled ? "合盖不休眠仍在生效" : "合盖后 Mac 仍会休眠"
            ))
        }
        for (before, after) in [(old.sleepError, current.sleepError), (old.displayError, current.displayError)] {
            if let after, before != after { result.append(StatusNotice(title: after, body: "")) }
        }
        return result
    }

    private static func join(_ body: String, _ failures: [StatusNotice]) -> String {
        ([body] + failures.map(\.title)).joined(separator: "；")
    }
}
