/// 将临时供电暂停与用户关闭全部项目区分，保留纯屏幕会话的接电恢复能力。
struct RemoteModeStatus {
    enum State { case off, partial, on, paused }

    var otherParts: [Bool]
    var displaySatisfied: Bool?
    /// 包括已暂停屏幕和仍未创建的屏幕；只控制会话保留，不用于“已暂停”文案。
    var displayPaused: Bool

    var hasOtherEnabled: Bool { otherParts.contains(true) }
    private var parts: [Bool] { otherParts + (displaySatisfied.map { [$0] } ?? []) }

    func state(remoteModeOn: Bool) -> State {
        guard remoteModeOn else { return .off }
        guard parts.contains(true) else { return displayPaused ? .paused : .off }
        return parts.allSatisfy { $0 } ? .on : .partial
    }

    func shouldExit(hadOtherEnabled: Bool) -> Bool {
        // 自动暂停本身不退出；暂停时用户再关完其他项目，则取消整个会话。
        !parts.contains(true) && (!displayPaused || hadOtherEnabled)
    }
}
