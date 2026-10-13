import AppKit
import Combine
import Sparkle

/// 基于 Sparkle 的检查更新：读取 GitHub 上的 appcast，安装包来自对应版本的 GitHub Release。
@MainActor
final class UpdateService: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = false
    private var controller: SPUStandardUpdaterController?

    /// 未配置更新源（本地开发构建）时不显示更新入口
    var isAvailable: Bool { controller != nil }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // 定时检查到新版本时不抢占当前应用焦点（菜单栏应用必需）
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main).assign(to: &$automaticallyChecks)
        controller.startUpdater()
    }

    func check() {
        // 菜单栏弹窗会挡住更新窗口，先激活应用让 Sparkle 窗口置前
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
