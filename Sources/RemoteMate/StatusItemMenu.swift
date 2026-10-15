import AppKit

/// 菜单栏图标的右键菜单。SwiftUI 的 MenuBarExtra 不提供右键事件，
/// 这里拦截发往本应用状态栏窗口的右键点击，弹出原生菜单；左键仍打开面板。
@MainActor
final class StatusItemMenu: NSObject {
    private let updates: UpdateService
    private var monitor: Any?

    init(updates: UpdateService) {
        self.updates = updates
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = event.window, Self.isStatusBarWindow(window),
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  let view = window.contentView else { return event }
            // 面板开着时先收起，避免右键菜单与面板叠在一起
            if let panel = PanelWindowController.current, panel.isVisible { panel.close() }
            self.makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
            return nil
        }
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        // 依赖 macOS 私有窗口类名；系统改名时右键菜单可能失效。
        // 匹配失败时继续传递原事件，不影响左键面板，也不强转私有类型。
        NSStringFromClass(type(of: window)).contains("StatusBarWindow")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("关于远程伴侣", #selector(showAbout)))
        if updates.isAvailable {
            let check = item("检查更新…", #selector(checkForUpdates))
            check.isEnabled = updates.canCheck
            menu.addItem(check)
        }
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("退出远程伴侣", #selector(quit), key: "q"))
        menu.autoenablesItems = false
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showAbout() { SettingsWindowController.shared.show(.about) }

    @objc private func checkForUpdates() { updates.check() }

    @objc private func showSettings() { SettingsWindowController.shared.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
