/// 远程模式下，外接显示器与虚拟屏幕之间的切换状态。
struct RemoteDisplayAutomation {
    enum Action: Equatable { case none, start, stop }

    var isWaitingForExternalDisplay = false
    enum PowerWaitReason { case pausedDisplay, pendingCreation }
    private(set) var powerWaitReason: PowerWaitReason?
    var isWaitingForPower: Bool { powerWaitReason != nil }
    var isDisplayPausedForPower: Bool { powerWaitReason == .pausedDisplay }
    private var previousHasExternal = false

    mutating func cancelPendingStart() {
        isWaitingForExternalDisplay = false
        powerWaitReason = nil
    }

    /// 偏好变化不是插拔事件：只撤销不再适用的等待，从不返回开关动作。
    mutating func preferencesChanged(includeDisplay: Bool, skipIfExternal: Bool) {
        if !includeDisplay { cancelPendingStart() }
        if !skipIfExternal { isWaitingForExternalDisplay = false }
    }

    mutating func prepareForRemoteMode(powerAllowsDisplay: Bool, skipDisplay: Bool,
                                      isActive: Bool, isRebuilding: Bool) {
        cancelPendingStart()
        if !powerAllowsDisplay {
            powerWaitReason = isActive || isRebuilding ? .pausedDisplay : .pendingCreation
        } else {
            isWaitingForExternalDisplay = skipDisplay && !isActive
        }
    }

    /// 状态是否满足取决于当前屏幕和偏好，不取决于虚拟屏幕此前是否被自动跳过。
    /// 待补建标记只控制插拔行为，手动开关不应让可用的外接屏被判为缺少屏幕。
    static func isRequirementSatisfied(
        hasExternal: Bool,
        skipIfExternal: Bool,
        isActive: Bool,
        isRebuilding: Bool
    ) -> Bool {
        isActive || isRebuilding || (hasExternal && skipIfExternal)
    }

    mutating func externalDisplayChanged(
        hasExternal: Bool,
        remoteModeOn: Bool,
        includeDisplay: Bool,
        skipIfExternal: Bool,
        isActive: Bool,
        isRebuilding: Bool,
        powerAllowsDisplay: Bool = true
    ) -> Action {
        let externalJustConnected = hasExternal && !previousHasExternal
        // 即使自动化未启用也更新基线；供电和偏好变化不能伪装成显示器接入。
        previousHasExternal = hasExternal
        guard remoteModeOn, includeDisplay else {
            cancelPendingStart()
            return .none
        }

        // 电池暂停优先于拔屏补建，两个系统事件无论以什么顺序到达都不能留下虚拟屏幕。
        if !powerAllowsDisplay {
            if isActive || isRebuilding {
                powerWaitReason = .pausedDisplay
            } else if !isWaitingForPower && isWaitingForExternalDisplay {
                powerWaitReason = .pendingCreation
            }
            isWaitingForExternalDisplay = false
            return isActive || isRebuilding ? .stop : .none
        }

        let resumeAfterPower = isWaitingForPower
        powerWaitReason = nil
        if !skipIfExternal { isWaitingForExternalDisplay = false }

        if hasExternal && skipIfExternal {
            if resumeAfterPower { isWaitingForExternalDisplay = true }
            guard externalJustConnected || resumeAfterPower else { return .none }
            // 已手动关闭的虚拟屏幕不重新纳入自动切换；重建中的屏幕仍算开启。
            guard isActive || isRebuilding else { return .none }
            isWaitingForExternalDisplay = true
            return .stop
        }

        guard isWaitingForExternalDisplay || resumeAfterPower else { return .none }
        isWaitingForExternalDisplay = false
        return .start
    }
}
