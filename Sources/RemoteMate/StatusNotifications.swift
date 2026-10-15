import AppKit
import Combine
import UserNotifications

@MainActor
final class StatusNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var permissionMessage = "正在检查通知权限…"
    @Published private(set) var needsSettings = false

    private let identifier = "remote-mate.sleep-status"
    private var center: UNUserNotificationCenter?
    private var enabled = false
    private var changes = FeatureStatusChanges()
    private var pending: StatusNotice?
    private var deliveryTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    func start(controller: AppController) {
        // UNUserNotificationCenter 在裸 SwiftPM 可执行文件中不可用。
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            permissionMessage = "请通过 RemoteMate.app 使用系统通知"
            return
        }
        center = UNUserNotificationCenter.current()
        center?.delegate = self
        _ = changes.notice(for: controller.featureStatus)

        controller.objectWillChange
            .merge(with: controller.sleep.objectWillChange, controller.display.objectWillChange,
                   controller.network.objectWillChange)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self, weak controller] in
                guard let self, let controller else { return }
                guard let notice = self.changes.notice(for: controller.featureStatus), self.enabled else { return }
                self.enqueue(notice)
            }
            .store(in: &cancellables)

        controller.prefs.$notifySleepChanges.removeDuplicates()
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        if value {
            guard authorizationTask == nil else { return }
            authorizationTask = Task { [weak self] in
                guard let self, let center = self.center else { return }
                do {
                    let settings = await center.notificationSettings()
                    if settings.authorizationStatus == .notDetermined {
                        _ = try await center.requestAuthorization(options: [.alert])
                    }
                    await self.refreshPermission()
                } catch {
                    self.permissionMessage = "通知授权失败：\(error.localizedDescription)"
                    self.needsSettings = true
                }
                self.authorizationTask = nil
            }
        } else {
            pending = nil
            center?.removePendingNotificationRequests(withIdentifiers: [identifier])
            center?.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    func refreshPermission() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        needsSettings = settings.authorizationStatus == .denied || settings.alertSetting == .disabled
        switch settings.authorizationStatus {
        case .notDetermined: permissionMessage = "开启后允许通知，即可接收状态变化提醒"
        case .denied: permissionMessage = "通知权限未开启，请在系统设置中允许 RemoteMate 通知"
        default:
            permissionMessage = settings.alertSetting == .enabled
                ? "远程模式开关、插拔电源或外接显示器影响远程时通知；横幅受系统专注模式影响"
                : "通知横幅未开启，请在系统设置中开启提醒"
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func enqueue(_ status: StatusNotice) {
        pending = status
        guard deliveryTask == nil else { return }
        // 串行发送；权限查询期间发生的多次变化只保留最新状态。
        deliveryTask = Task { [weak self] in
            guard let self, let center = self.center else { return }
            if let authorizationTask = self.authorizationTask { await authorizationTask.value }
            while self.enabled, self.pending != nil {
                let settings = await center.notificationSettings()
                guard self.enabled, let latest = self.pending else { break }
                self.pending = nil
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    await self.refreshPermission()
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = latest.title
                content.body = latest.body
                content.threadIdentifier = self.identifier
                do {
                    // 固定标识替换历史状态，通知中心不会积累相互矛盾的旧提醒。
                    try await center.add(UNNotificationRequest(identifier: self.identifier, content: content, trigger: nil))
                    if !self.enabled {
                        center.removeDeliveredNotifications(withIdentifiers: [self.identifier])
                        center.removePendingNotificationRequests(withIdentifiers: [self.identifier])
                    }
                } catch {
                    self.permissionMessage = "状态通知发送失败：\(error.localizedDescription)"
                }
            }
            self.deliveryTask = nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
