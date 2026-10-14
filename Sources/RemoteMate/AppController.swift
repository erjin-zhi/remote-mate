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

    /// 只有用户点过顶部的一键按钮才算进入远程模式；单独操作下方各项开关不影响它。
    @Published private(set) var isRemoteModeOn = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Preferences.registerDefaults()
        prefs = Preferences()
        sleep = SleepManager()
        display = VirtualDisplayManager()
        network = NetworkMonitor()

        // 远程模式下用户把纳入的各项都手动关掉后，视为退出远程模式，
        // 否则之后单独打开某一项时按钮又会显示为「部分开启」。
        sleep.objectWillChange.merge(with: display.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.isRemoteModeOn, !self.includedParts.contains(true) else { return }
                self.isRemoteModeOn = false
            }
            .store(in: &cancellables)
    }

    enum RemoteState { case off, partial, on }

    private var includedParts: [Bool] {
        var parts: [Bool] = []
        if prefs.includeAC { parts.append(sleep.preventOnAC) }
        if prefs.includeBattery && sleep.hasBattery { parts.append(sleep.preventOnBattery) }
        if prefs.includeLid { parts.append(sleep.lidModeEnabled) }
        if prefs.includeDisplay { parts.append(display.isActive || display.isRebuilding) }
        return parts
    }

    /// 未通过一键按钮开启时始终为关闭；开启后再根据被纳入的各项开关判断是否全部生效。
    var remoteState: RemoteState {
        let parts = includedParts
        guard isRemoteModeOn, parts.contains(true) else { return .off }
        return parts.allSatisfy { $0 } ? .on : .partial
    }

    func setRemoteMode(_ on: Bool) {
        isRemoteModeOn = on
        if prefs.includeAC { sleep.preventOnAC = on }
        if prefs.includeBattery { sleep.preventOnBattery = on }
        if prefs.includeDisplay { display.setEnabled(on) }
        // 只在开启时拉起 UU 远程；关闭远程模式不退出 UU，以免断开正在进行的远程会话
        if on && prefs.launchUU { network.launchUUIfNeeded() }
        if prefs.includeLid { sleep.lidModeEnabled = on }
    }

    func didFinishLaunching() {
        updates.start()
        if prefs.autoStartRemote { setRemoteMode(true) }
    }

    func willTerminate() {
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
