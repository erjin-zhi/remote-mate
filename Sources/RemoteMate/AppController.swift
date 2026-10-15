import AppKit
import Combine

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    let prefs: Preferences
    let sleep: SleepManager
    let display: VirtualDisplayManager
    let network: NetworkMonitor
    let updates = UpdateService()
    let notifications = StatusNotifications()
    private lazy var statusItemMenu = StatusItemMenu(updates: updates)

    private var displayAutomation = RemoteDisplayAutomation()
    /// 只有用户点过顶部的一键按钮才算进入远程模式；单独操作下方各项开关不影响它。
    @Published private(set) var isRemoteModeOn = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Preferences.registerDefaults()
        prefs = Preferences()
        sleep = SleepManager()
        display = VirtualDisplayManager()
        network = NetworkMonitor()

        $isRemoteModeOn.combineLatest(prefs.$launchUU, prefs.$keepUUAlive)
            .sink { [weak self] remoteModeOn, launchUU, keepAlive in
                self?.network.updateUUKeepAlive(remoteModeOn: remoteModeOn, launchUU: launchUU, keepAlive: keepAlive)
            }
            .store(in: &cancellables)

        // 只有插拔外接显示器和供电变化才会自动开关虚拟屏幕；
        // 修改包含项不立即生效（设置页有说明），否则会关掉正在使用的屏幕。
        display.$hasExternalDisplay
            .combineLatest(sleep.$powerSource, sleep.$preventOnBattery)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
            .sink { [weak self] hasExternal, powerSource, preventOnBattery in
                guard let self else { return }
                let action = self.displayAutomation.externalDisplayChanged(
                    hasExternal: hasExternal,
                    remoteModeOn: self.isRemoteModeOn,
                    includeDisplay: self.prefs.includeDisplay,
                    skipIfExternal: self.prefs.skipDisplayIfExternal,
                    isActive: self.display.isActive,
                    isRebuilding: self.display.isRebuilding,
                    powerAllowsDisplay: powerSource != .battery || preventOnBattery
                )
                switch action {
                case .none: break
                case .start: self.display.start()
                case .stop: self.display.stop()
                }
            }
            .store(in: &cancellables)

        // 取消纳入时只撤销待补建 / 待恢复，不动当前屏幕
        prefs.$includeDisplay.combineLatest(prefs.$skipDisplayIfExternal)
            .sink { [weak self] includeDisplay, skipIfExternal in
                self?.displayAutomation.preferencesChanged(includeDisplay: includeDisplay, skipIfExternal: skipIfExternal)
            }
            .store(in: &cancellables)

        // 屏幕一旦真正创建（含用户手动打开），取消待补建，避免后续插拔撤销用户的手动关闭。
        // 顶部是否正常独立按当前屏幕和偏好判断，不依赖这个标记。
        display.$isActive
            .removeDuplicates()
            .sink { [weak self] active in
                if active { self?.displayAutomation.cancelPendingStart() }
            }
            .store(in: &cancellables)

        // 远程模式下用户把纳入的各项都手动关掉后，视为退出远程模式，
        // 否则之后单独打开某一项时按钮又会显示为「部分开启」。
        // 未启用保活时，退出最后一个运行中的 UU 也会退出模式；保活中则继续等待重启。
        var hadOtherEnabled = modeStatus.hasOtherEnabled
        sleep.objectWillChange.merge(with: display.objectWillChange, prefs.objectWillChange, network.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                let status = self.modeStatus
                let shouldExit = status.shouldExit(hadOtherEnabled: hadOtherEnabled)
                hadOtherEnabled = status.hasOtherEnabled
                guard self.isRemoteModeOn, shouldExit else { return }
                self.displayAutomation.cancelPendingStart()
                self.isRemoteModeOn = false
            }
            .store(in: &cancellables)
    }

    private var shouldSkipDisplay: Bool {
        prefs.skipDisplayIfExternal && display.hasExternalDisplay
    }

    private var powerAllowsDisplay: Bool {
        sleep.powerSource != .battery || sleep.preventOnBattery
    }

    var isDisplayPausedForBattery: Bool {
        isRemoteModeOn && prefs.includeDisplay && displayAutomation.isDisplayPausedForPower
            && !display.isActive && !display.isRebuilding
    }

    var isDisplayWaitingToCreateForPower: Bool {
        isRemoteModeOn && prefs.includeDisplay && displayAutomation.powerWaitReason == .pendingCreation
            && !display.isActive && !display.isRebuilding
    }

    var displayPowerWaitDescription: String {
        let state = isDisplayPausedForBattery ? "虚拟屏幕已暂停" : "虚拟屏幕尚未创建"
        return shouldSkipDisplay
            ? "\(state)，等待外接显示器断开且供电允许后创建"
            : "\(state)，接电或开启「使用电池时不休眠」后创建"
    }

    typealias RemoteState = RemoteModeStatus.State

    private var modeStatus: RemoteModeStatus {
        var parts: [Bool] = []
        if prefs.includeAC { parts.append(sleep.preventOnAC) }
        if prefs.includeBattery && sleep.hasBattery { parts.append(sleep.preventOnBattery) }
        if prefs.includeLid { parts.append(sleep.lidModeEnabled) }
        let displaySatisfied: Bool? = prefs.includeDisplay
            ? RemoteDisplayAutomation.isRequirementSatisfied(
                hasExternal: display.hasExternalDisplay,
                skipIfExternal: prefs.skipDisplayIfExternal,
                isActive: display.isActive,
                isRebuilding: display.isRebuilding
            ) : nil
        // UU 保活也是远程模式的一项；只选择 UU 时仍能通过主按钮关闭。
        if prefs.launchUU && network.isUUInstalled {
            parts.append(network.isUUKeepAliveEnabled || network.isLaunchingUU || network.uuStatus == .running)
        }
        return RemoteModeStatus(otherParts: parts, displaySatisfied: displaySatisfied,
                                displayPaused: isDisplayPausedForBattery || isDisplayWaitingToCreateForPower)
    }

    /// 未通过一键按钮开启时始终为关闭；开启后再根据被纳入的各项开关判断是否全部生效。
    var remoteState: RemoteState {
        modeStatus.state(remoteModeOn: isRemoteModeOn)
    }

    func setRemoteMode(_ on: Bool) {
        network.refreshUUStatus()
        isRemoteModeOn = on
        // 退出模式时无论虚拟屏幕是否仍被纳入，都要取消待补建
        if !on { displayAutomation.cancelPendingStart() }
        if prefs.includeAC { sleep.preventOnAC = on }
        if prefs.includeBattery { sleep.preventOnBattery = on }
        if prefs.includeDisplay {
            if on {
                displayAutomation.prepareForRemoteMode(
                    powerAllowsDisplay: powerAllowsDisplay, skipDisplay: shouldSkipDisplay,
                    isActive: display.isActive, isRebuilding: display.isRebuilding
                )
            }
            display.setEnabled(on && powerAllowsDisplay && !displayAutomation.isWaitingForExternalDisplay)
        }
        // 自动启动仍只在一键开启时执行一次，持续保活需要单独勾选。
        if on && prefs.launchUU {
            if network.isUUInstalled {
                network.launchUUIfNeeded()
            } else if !prefs.keepUUAlive {
                // 启用保活时，未安装提示已由 updateUUKeepAlive 写入。
                network.lastError = "未找到 UU 远程，请先将其安装到应用程序文件夹。"
            }
        }
        if prefs.includeLid { sleep.lidModeEnabled = on }
        if on && modeStatus.otherParts.isEmpty && modeStatus.displaySatisfied == nil { isRemoteModeOn = false }
    }

    var featureStatus: FeatureStatus {
        let virtualScreen: FeatureStatus.VirtualScreen
        if display.isRebuilding { virtualScreen = .rebuilding }
        else if display.isActive { virtualScreen = .enabled }
        else if displayAutomation.isDisplayPausedForPower { virtualScreen = .pausedForBattery }
        else if displayAutomation.isWaitingForPower { virtualScreen = .waitingForPower }
        else if displayAutomation.isWaitingForExternalDisplay { virtualScreen = .waiting }
        else { virtualScreen = .disabled }
        return FeatureStatus(
            sleep: sleep.status,
            remoteMode: isRemoteModeOn,
            virtualScreen: virtualScreen,
            uuKeepAlive: network.isUUKeepAliveEnabled,
            hasExternalDisplay: display.hasExternalDisplay,
            sleepError: sleep.lastError,
            displayError: display.lastError
        )
    }

    func didFinishLaunching() {
        notifications.start(controller: self)
        updates.start()
        statusItemMenu.install()
        if prefs.autoStartRemote { setRemoteMode(true) }
    }

    func willTerminate() {
        network.updateUUKeepAlive(remoteModeOn: false, launchUU: prefs.launchUU, keepAlive: prefs.keepUUAlive)
        display.stop()
        if prefs.restoreOnQuit { sleep.restoreLidSleepSynchronously() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppController.shared.didFinishLaunching() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppController.shared.willTerminate() }
    }
}
