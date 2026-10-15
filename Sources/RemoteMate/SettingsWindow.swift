import SwiftUI

/// 偏好设置窗口：顶部工具栏分栏（通用 / 远程 / 关于），与常见 Mac 应用的设置窗口一致。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    static let width: CGFloat = 460

    enum Tab: Int, CaseIterable {
        case general, remote, about

        var title: String {
            switch self {
            case .general: return "通用"
            case .remote: return "远程"
            case .about: return "关于"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .remote: return "power.circle"
            case .about: return "info.circle"
            }
        }
    }

    private var window: NSWindow?
    private var tabController: NSTabViewController?

    func show(_ tab: Tab? = nil) {
        if window == nil { makeWindow() }
        if let tab { tabController?.selectedTabViewItemIndex = tab.rawValue }
        // 菜单栏应用默认不在前台；激活后菜单栏面板失去焦点会自动收起
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // 窗口关闭后不销毁，每次打开都重新读取通知权限（用户可能刚在系统设置里改过）
        Task { await AppController.shared.notifications.refreshPermission() }
    }

    private func makeWindow() {
        let tabController = NSTabViewController()
        tabController.tabStyle = .toolbar
        // 保持窗口标题不变，不随所选分栏改成「通用」「远程」等
        tabController.canPropagateSelectedChildViewControllerTitle = false
        for tab in Tab.allCases {
            let item = NSTabViewItem(viewController: hosting(for: tab))
            item.label = tab.title
            item.image = Self.toolbarImage(tab.icon, description: tab.title)
            tabController.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabController)
        window.title = "远程伴侣设置"
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        self.tabController = tabController
    }

    /// SF Symbols 的外形尺寸各不相同（齿轮与带圆圈的符号视觉大小不一），
    /// 统一画进同样大小的画布并居中，保证工具栏图标大小、基线一致。
    private static func toolbarImage(_ name: String, description: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(config) else { return nil }
        let canvas = NSSize(width: 24, height: 24)
        // 按最长边缩放到同一尺寸
        let scale = 20 / max(symbol.size.width, symbol.size.height)
        let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let image = NSImage(size: canvas, flipped: false) { _ in
            symbol.draw(in: NSRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                                   width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    private func hosting(for tab: Tab) -> NSViewController {
        let controller = AppController.shared
        let view: AnyView
        switch tab {
        case .general: view = AnyView(GeneralSettingsView())
        case .remote: view = AnyView(RemoteSettingsView())
        case .about: view = AnyView(AboutSettingsView())
        }
        let hosting = NSHostingController(rootView: view
            .environmentObject(controller.prefs)
            .environmentObject(controller.sleep)
            .environmentObject(controller.network)
            .environmentObject(controller.updates)
            .environmentObject(controller.notifications))
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }
}

// MARK: - 通用

struct GeneralSettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var sleep: SleepManager
    @EnvironmentObject private var notifications: StatusNotifications

    var body: some View {
        SettingsGrid {
            SettingsRow("启动：") {
                Toggle("登录时启动远程伴侣", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
            }
            SettingsRow("通知：") {
                Toggle("远程状态变化时通知", isOn: $prefs.notifySleepChanges)
                if prefs.notifySleepChanges {
                    SettingsNote(notifications.permissionMessage, warning: notifications.needsSettings)
                    if notifications.needsSettings {
                        Button("打开系统通知设置") { notifications.openSettings() }
                            .controlSize(.small)
                    }
                }
            }
            SettingsRow("退出时：") {
                Toggle("关闭合盖不休眠", isOn: $prefs.restoreOnQuit)
                SettingsNote("防休眠和虚拟屏幕在退出时总会关闭。合盖不休眠是系统设置，取消勾选后退出远程伴侣，它仍会继续生效。")
            }
            if let error = prefs.lastError ?? sleep.lastError {
                SettingsRow("") {
                    HStack(alignment: .top, spacing: 6) {
                        SettingsNote(error, warning: true)
                        Spacer()
                        Button {
                            prefs.lastError = nil
                            sleep.lastError = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("关闭提示")
                    }
                }
            }
        }
    }
}

// MARK: - 一键远程

/// 只配置「一键开启远程模式」会带上哪些项目，不直接开关任何功能；即时开关在菜单栏面板里。
struct RemoteSettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        SettingsGrid {
            SettingsRow("防休眠：") {
                Toggle("接通电源时不休眠", isOn: $prefs.includeAC)
                Toggle("使用电池时不休眠", isOn: $prefs.includeBattery)
                Toggle("合盖不休眠", isOn: $prefs.includeLid)
            }
            SettingsRow("虚拟屏幕：") {
                Toggle("创建虚拟屏幕", isOn: $prefs.includeDisplay)
                Toggle("接有外接显示器时跳过", isOn: $prefs.skipDisplayIfExternal)
                    .disabled(!prefs.includeDisplay)
                    .help("跳过时，拔掉外接显示器后会自动创建；再接上会自动关闭。")
                SettingsNote("改动在下次一键开启或插拔外接显示器时生效，不会立即开关当前虚拟屏幕。")
            }
            SettingsRow("UU 远程：") {
                Toggle("启动 UU 远程", isOn: $prefs.launchUU)
                Toggle("被退出后自动重新启动（保活）", isOn: $prefs.keepUUAlive)
                    .disabled(!prefs.launchUU)
                    .help("每 10 秒检查一次；关闭远程模式后停止，不会退出 UU。")
                if !network.isUUInstalled {
                    SettingsNote("未安装 UU 远程，此项不会生效。")
                }
            }
            Divider().gridCellColumns(2)
            SettingsRow("自动开启：") {
                Toggle("启动远程伴侣后自动执行一键远程", isOn: $prefs.autoStartRemote)
            }
        } header: {
            Text("点击菜单栏中的「一键开启远程模式」时，会同时开启以下勾选的项目，关闭时一并关闭。")
        }
    }
}

// MARK: - 关于

struct AboutSettingsView: View {
    @EnvironmentObject private var updates: UpdateService

    private static let repository = URL(string: "https://github.com/erjin-zhi/remote-mate")!

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("远程伴侣").font(.title3.bold())
                        Text("版本 \(updates.currentVersion)\(buildText)")
                            .font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("让 Mac 在远程桌面时保持唤醒、提供虚拟屏幕")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if updates.isAvailable {
                    HStack {
                        Toggle("自动检查更新", isOn: Binding(
                            get: { updates.automaticallyChecks },
                            set: { updates.setAutomaticallyChecks($0) }
                        ))
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button("检查更新…") { updates.check() }
                            .disabled(!updates.canCheck)
                    }
                } else {
                    Text("开发构建未配置更新源").font(.caption).foregroundStyle(.tertiary)
                }
                Link("在 GitHub 上查看", destination: Self.repository)
                    .font(.callout)
            }
        }
        .padding(20)
        .frame(width: SettingsWindowController.width, alignment: .leading)
    }

    private var buildText: String {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              build != updates.currentVersion else { return "" }
        return "（\(build)）"
    }
}

// MARK: - 组件

/// 经典 Mac 偏好设置排版：左列右对齐的分组标签，右列为勾选框。所有分栏宽度一致，切换时窗口不会横向跳动。
private struct SettingsGrid<Content: View, Header: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 14) {
                content
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(width: SettingsWindowController.width, alignment: .leading)
    }
}

private extension SettingsGrid where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() })
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GridRow {
            Text(title)
                .frame(width: 80, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}

private struct SettingsNote: View {
    let text: String
    var warning = false

    init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(warning ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
