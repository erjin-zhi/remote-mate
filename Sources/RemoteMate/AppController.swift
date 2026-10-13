import AppKit

@MainActor
final class AppController {
    static let shared = AppController()

    let prefs: Preferences
    let sleep: SleepManager
    let display: VirtualDisplayManager
    let network: NetworkMonitor

    private init() {
        Preferences.registerDefaults()
        prefs = Preferences()
        sleep = SleepManager()
        display = VirtualDisplayManager()
        network = NetworkMonitor()
    }

    enum RemoteState { case off, partial, on }

    /// 根据被纳入一键远程模式的各项开关，判断整体状态。
    var remoteState: RemoteState {
        var parts: [Bool] = []
        if prefs.includeAC { parts.append(sleep.preventOnAC) }
        if prefs.includeBattery && sleep.hasBattery { parts.append(sleep.preventOnBattery) }
        if prefs.includeLid { parts.append(sleep.lidModeEnabled) }
        if prefs.includeDisplay { parts.append(display.isActive) }
        if parts.isEmpty || !parts.contains(true) { return .off }
        return parts.allSatisfy { $0 } ? .on : .partial
    }

    func setRemoteMode(_ on: Bool) {
        if prefs.includeAC { sleep.preventOnAC = on }
        if prefs.includeBattery { sleep.preventOnBattery = on }
        if prefs.includeDisplay { display.setEnabled(on) }
        // 只在开启时拉起 UU 远程；关闭远程模式不退出 UU，以免断开正在进行的远程会话
        if on && prefs.launchUU { network.launchUUIfNeeded() }
        if prefs.includeLid { sleep.lidModeEnabled = on }
    }

    func didFinishLaunching() {
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
