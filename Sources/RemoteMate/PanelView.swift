import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var sleep: SleepManager
    @EnvironmentObject private var display: VirtualDisplayManager
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var updates: UpdateService

    @State private var customWidth = ""
    @State private var customHeight = ""
    @State private var editingCustom = false
    @State private var showPreferences = false
    @State private var hoveringUU = false
    @StateObject private var panelWindow = PanelWindowController()
    @FocusState private var focusedField: CustomField?

    private enum CustomField { case width, height }

    @ObservedObject private var controller = AppController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            remoteModeButton
            networkCard
            sleepCard
            displayCard
            errors
            preferencesSection
            footer
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        // 菜单栏弹窗在内容变矮时不会自动缩小，这里按内容实际高度手动调整窗口
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { panelWindow.fit(height: proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in panelWindow.fit(height: height) }
        })
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(PanelWindowAccessor(controller: panelWindow))
        .onAppear {
            editingCustom = false
            display.refreshModeText()
            network.startAutoRefresh()
            Task {
                await sleep.refreshLidState()
                await sleep.refreshPasswordless()
            }
        }
        .onDisappear { network.stopAutoRefresh() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack {
            Text("远程伴侣").font(.title3.bold())
            Spacer()
            HStack(spacing: 10) {
                Label(network.interfaceText, systemImage: network.isOnline ? "wifi" : "wifi.slash")
                Label(powerText, systemImage: powerIcon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var powerText: String {
        switch sleep.powerSource {
        case .ac: return sleep.batteryLevel.map { "电源 · \($0)%" } ?? "接通电源"
        case .battery: return sleep.batteryLevel.map { "电池 · \($0)%" } ?? "使用电池"
        case .unknown: return "电源未知"
        }
    }

    private var powerIcon: String {
        sleep.powerSource == .battery ? "battery.75percent" : "powerplug"
    }

    private var remoteModeButton: some View {
        let state = controller.remoteState
        let tint: Color = state == .on ? .accentColor : (state == .off ? .clear : .orange)
        return VStack(spacing: 6) {
            GlareCard(
                isEnabled: !sleep.lidBusy,
                label: state == .off ? "开启远程模式" : "关闭远程模式",
                value: remoteModeTitle(state),
                fill: state == .off ? Color.primary.opacity(0.07) : tint,
                highlight: state == .off ? 1 : 0.3,
                action: { controller.setRemoteMode(state == .off) }
            ) {
                HStack(spacing: 10) {
                    Image(systemName: state == .off ? "power" : "power.circle.fill")
                        .font(.title2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remoteModeTitle(state)).font(.headline)
                        Text(remoteModeSummary).font(.caption).opacity(0.85)
                    }
                    Spacer()
                    Text(state == .off ? "开启" : "关闭")
                        .font(.callout.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(state == .off ? Color.accentColor : Color.white.opacity(0.25)))
                        .foregroundStyle(.white)
                }
                .padding(12)
                .foregroundStyle(state == .off ? Color.primary : Color.white)
            }

            if controller.isDisplayPausedForBattery {
                Text(controller.displayPowerWaitDescription)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.isDisplayWaitingToCreateForPower && state != .on {
                Text(controller.displayPowerWaitDescription)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state == .partial {
                HStack {
                    Text("部分项目未能开启").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("重试开启剩余项") { controller.setRemoteMode(true) }
                        .controlSize(.small)
                        .disabled(sleep.lidBusy)
                }
            }
        }
    }

    private func remoteModeTitle(_ state: AppController.RemoteState) -> String {
        switch state {
        case .off: return "一键开启远程模式"
        case .partial: return "远程模式部分开启"
        case .on: return "远程模式已开启"
        case .paused: return "远程模式已暂停"
        }
    }

    // MARK: - 网络

    private var networkCard: some View {
        Card(title: "网络状况", icon: "network", accessory: {
            HStack(spacing: 6) {
                if network.proxyTUN {
                    Text("代理 TUN").font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help("默认路由由代理/VPN 虚拟网卡接管，外网与 UU 服务器延迟为经代理后的结果")
                }
                if network.isChecking {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        network.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("重新检测")
                }
            }
        }) {
            ProbeRow(title: "内网", probe: network.lan)
            ProbeRow(title: "外网", probe: network.wan)
            if network.isUUInstalled {
                ProbeRow(title: "UU 服务器", probe: network.uuService)
                uuApplicationRow
            }
        }
    }

    private var uuApplicationRow: some View {
        HStack(spacing: 8) {
            StatusDot(level: uuLevel)
            Text("UU 远程").font(.callout)
            Spacer()
            Text(network.isLaunchingUU ? "启动中…" : uuText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(uuNeedsLaunch ? Color.red : Color.secondary)
            if network.uuStatus == .running {
                Image(systemName: "arrow.up.forward")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(network.isLaunchingUU ? "显示" : "打开")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.12)))
            }
        }
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(hoveringUU ? 0.1 : 0)))
        .accessibilityHidden(true)
        .overlay {
            HandCursorButton(
                isEnabled: network.isUUInstalled,
                label: network.isLaunchingUU ? "启动完成后显示 UU 远程"
                    : network.uuStatus == .running ? "切换到 UU 远程" : "打开 UU 远程",
                value: network.isLaunchingUU ? "启动中" : uuText,
                onHover: { hoveringUU = $0 },
                action: { network.openUU(activate: true) }
            )
        }
        .onDisappear { hoveringUU = false }
    }

    private var uuNeedsLaunch: Bool {
        network.uuStatus.canLaunch && !network.isLaunchingUU
    }

    private var uuLevel: NetworkMonitor.Level {
        switch network.uuStatus {
        case .running: return .good
        case .backgroundOnly, .installedNotRunning, .notInstalled: return .bad
        }
    }

    private var uuText: String {
        switch network.uuStatus {
        case .running: return "主程序运行中"
        case .backgroundOnly, .installedNotRunning: return "未启动"
        case .notInstalled: return "未安装"
        }
    }

    private var remoteModeSummary: String {
        var items: [String] = []
        if prefs.includeAC { items.append("接电不休眠") }
        if prefs.includeBattery && sleep.hasBattery { items.append("电池不休眠") }
        if prefs.includeLid { items.append("合盖不休眠") }
        if prefs.includeDisplay { items.append("虚拟屏幕") }
        if prefs.launchUU && network.isUUInstalled { items.append(prefs.keepUUAlive ? "UU 保活" : "启动 UU") }
        return items.isEmpty ? "未选择可用项目，请检查偏好设置" : items.joined(separator: " · ")
    }

    // MARK: - 防休眠

    private var sleepCard: some View {
        Card(title: "防休眠", icon: "moon.zzz") {
            ToggleRow(
                title: "接通电源时不休眠",
                subtitle: sleep.powerSource != .battery ? "当前生效中的供电状态" : nil,
                isOn: $sleep.preventOnAC
            )
            if sleep.hasBattery {
                ToggleRow(
                    title: "使用电池时不休眠",
                    subtitle: sleep.powerSource == .battery ? "当前生效中的供电状态" : nil,
                    isOn: $sleep.preventOnBattery
                )
            }
            ToggleRow(title: "同时保持屏幕常亮", subtitle: "避免远程画面因屏幕休眠而黑屏", isOn: $sleep.keepDisplayAwake)

            Divider()

            ToggleRow(
                title: "合盖不休眠",
                subtitle: lidSubtitle,
                isOn: $sleep.lidModeEnabled,
                busy: sleep.lidBusy
            )
            HStack(spacing: 6) {
                Image(systemName: sleep.passwordlessEnabled ? "checkmark.shield" : "lock.shield")
                    .foregroundStyle(sleep.passwordlessEnabled ? .green : .secondary)
                Text(sleep.passwordlessEnabled ? "已开启免密码切换" : "每次切换都需输入密码")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(sleep.passwordlessEnabled ? "撤销" : "免密码授权") {
                    Task {
                        if sleep.passwordlessEnabled {
                            await sleep.uninstallPasswordless()
                        } else {
                            await sleep.installPasswordless()
                        }
                    }
                }
                .controlSize(.small)
                .help("在 /etc/sudoers.d 写入一条只允许执行 pmset disablesleep 的规则")
            }
        }
    }

    private var lidSubtitle: String {
        if sleep.lidBusy { return "正在切换 · 可能需要管理员授权" }
        if !sleep.lidStateAvailable { return "暂时无法确认系统状态" }
        if sleep.lidChangeFailed {
            return sleep.lidSleepDisabled ? "切换未完成 · 合盖不休眠仍在生效" : "切换未完成 · 合盖不休眠未生效"
        }
        if sleep.lidSleepDisabled { return "生效中 · 合盖也不休眠，注意散热" }
        if !sleep.lidModeEnabled { return "跟随上面的供电开关生效" }
        if sleep.lidShouldBeActive { return "未生效 · 请检查管理员授权" }
        return sleep.powerSource == .battery
            ? "已暂停 · 使用电池且未开启「使用电池时不休眠」"
            : "已暂停 · 未开启「接通电源时不休眠」"
    }

    // MARK: - 虚拟屏幕

    private var displayCard: some View {
        Card(title: "虚拟屏幕", icon: "display") {
            ToggleRow(
                title: "启用虚拟屏幕",
                subtitle: display.isRebuilding ? "正在应用新设置…"
                    : display.isActive ? displayStatus
                    : controller.isDisplayPausedForBattery || controller.isDisplayWaitingToCreateForPower
                        ? controller.displayPowerWaitDescription
                    : "无显示器或合盖时也能获得远程桌面画面",
                // 重建期间仍显示为开启，此时关掉会取消重建，而不是立即再建一块屏幕
                isOn: Binding(get: { display.isActive || display.isRebuilding }, set: { display.setEnabled($0) })
            )

            HStack {
                Text("分辨率").font(.callout)
                Spacer()
                Button("自定义…") {
                    customWidth = String(display.width)
                    customHeight = String(display.height)
                    editingCustom = true
                    DispatchQueue.main.async { focusedField = .width }
                }
                .controlSize(.small)
                .disabled(editingCustom)
                Menu(display.resolution.label) {
                    // 每组一个内联 Picker：使用菜单原生的勾选栏保持左对齐，Section 之间自动加分隔线
                    ForEach(Resolution.presetGroups.indices, id: \.self) { index in
                        Section {
                            Picker("分辨率", selection: Binding(
                                get: { display.resolution },
                                set: { selectResolution($0) }
                            )) {
                                ForEach(Resolution.presetGroups[index]) { preset in
                                    Text(preset.menuLabel).tag(preset)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                }
                .fixedSize()
            }

            if editingCustom {
                HStack(spacing: 6) {
                    Text("自定义").font(.callout)
                    Spacer()
                    TextField("宽", text: $customWidth)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .width)
                        .onSubmit { focusedField = .height }
                    Text("×").foregroundStyle(.secondary)
                    TextField("高", text: $customHeight)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .height)
                        .onSubmit(applyCustomResolution)
                    Button("应用", action: applyCustomResolution)
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                    Button {
                        editingCustom = false
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("刷新率").font(.callout)
                Spacer()
                Picker("", selection: $display.refreshRate) {
                    Text("30 Hz").tag(30.0)
                    Text("60 Hz").tag(60.0)
                    Text("120 Hz").tag(120.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }

            ToggleRow(title: "HiDPI（Retina）", subtitle: "画面更清晰，但远程传输像素翻倍", isOn: $display.hiDPI)
            ToggleRow(title: "启用时设为主显示器", subtitle: "菜单栏与程序坞移到虚拟屏幕", isOn: $display.makeMainOnStart)

            HStack {
                Button("设为主显示器") {
                    display.makeMain()
                }
                .disabled(!display.isActive || display.isMain)
                Spacer()
                Button("显示器设置…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private var displayStatus: String {
        var text = "ID \(display.displayID)"
        if !display.currentModeText.isEmpty { text += " · \(display.currentModeText)" }
        return text
    }

    private func selectResolution(_ resolution: Resolution) {
        display.setResolution(width: resolution.width, height: resolution.height)
        editingCustom = false
    }

    private func applyCustomResolution() {
        guard let w = Int(customWidth.trimmingCharacters(in: .whitespaces)),
              let h = Int(customHeight.trimmingCharacters(in: .whitespaces)) else {
            display.lastError = "请输入有效的数字"
            return
        }
        display.setResolution(width: w, height: h)
        if display.width == w && display.height == h {
            editingCustom = false
            focusedField = nil
        }
    }

    // MARK: - 错误提示

    @ViewBuilder
    private var errors: some View {
        ForEach(Array([sleep.lastError, display.lastError, prefs.lastError, network.lastError].compactMap { $0 }.enumerated()), id: \.offset) { _, message in
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    sleep.lastError = nil
                    display.lastError = nil
                    prefs.lastError = nil
                    network.lastError = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - 偏好设置

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showPreferences.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(showPreferences ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text("偏好设置")
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showPreferences {
            VStack(alignment: .leading, spacing: 6) {
                Text("一键远程模式包含").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("接电不休眠", isOn: $prefs.includeAC)
                    Toggle("电池不休眠", isOn: $prefs.includeBattery)
                    Toggle("合盖不休眠", isOn: $prefs.includeLid)
                }
                HStack {
                    Toggle("创建虚拟屏幕", isOn: $prefs.includeDisplay)
                    Toggle("已接外接显示器时不创建", isOn: $prefs.skipDisplayIfExternal)
                        .disabled(!prefs.includeDisplay)
                }
                HStack {
                    Toggle("自动启动 UU 远程", isOn: $prefs.launchUU)
                        .help("开启远程模式时，若 UU 主程序未运行则启动一次。")
                    Toggle("UU 保活", isOn: $prefs.keepUUAlive)
                        .disabled(!prefs.launchUU)
                        .help("需同时开启远程模式和自动启动 UU。每 10 秒检查一次，手动退出 UU 后也会重新启动；关闭远程模式或取消任一勾选即停止保活，不退出 UU。")
                }
                if prefs.launchUU && !network.isUUInstalled {
                    Text("未安装 UU 远程，自动启动与保活不可用")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("登录时启动远程伴侣", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
                Toggle("启动后自动开启远程模式", isOn: $prefs.autoStartRemote)
                Toggle("退出时恢复合盖休眠", isOn: $prefs.restoreOnQuit)
                if updates.isAvailable {
                    Divider()
                    HStack {
                        Toggle("自动检查更新", isOn: Binding(
                            get: { updates.automaticallyChecks },
                            set: { updates.setAutomaticallyChecks($0) }
                        ))
                        Spacer()
                        Text("版本 \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
                        Button("检查更新…") { updates.check() }
                            .controlSize(.small)
                            .disabled(!updates.canCheck)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .padding(.top, 6)
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Text("退出后防休眠与虚拟屏幕将自动关闭")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .controlSize(.small)
        }
    }
}

// MARK: - 组件

struct Card<Accessory: View, Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).font(.subheadline.bold())
                Spacer()
                accessory
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

/// 悬停时随指针轻微倾斜，并在指针处泛起高光和边缘反光，类似 App Store 卡片的立体效果。
/// 点击与手型光标交给 HandCursorButton，它放在 3D 变换之外，保证点击区域不随倾斜偏移。
struct GlareCard<Content: View>: View {
    var isEnabled: Bool
    var cornerRadius: CGFloat = 10
    var label: String
    var value: String
    var fill: Color
    /// 光效强度：彩色底配白字时要调低，避免高光把文字冲淡
    var highlight: Double = 1
    var action: () -> Void
    @ViewBuilder var content: Content

    @State private var hovering = false
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        let active = hovering && isEnabled
        let center = UnitPoint(x: pointer.x, y: pointer.y)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // 光效都画在内容下方，文字和按钮保持原色不被冲淡
        content
            .background {
                ZStack {
                    shape.fill(fill)
                    // 整体提亮一层，像卡片被抬起；指针处再加一团柔和的白色高光
                    shape.fill(Color.white.opacity(0.35 * highlight))
                    shape.fill(RadialGradient(colors: [Color.white.opacity(0.6 * highlight), Color.white.opacity(0)],
                                              center: center, startRadius: 0, endRadius: 160))
                }
                .opacity(active ? 1 : 0)
                .background(shape.fill(fill))
            }
            .overlay(
                shape.strokeBorder(RadialGradient(colors: [Color.white.opacity(0.9), Color.primary.opacity(0.06)],
                                                  center: center, startRadius: 0, endRadius: 220),
                                   lineWidth: 1)
                    .opacity(active ? 1 : 0)
            )
            .clipShape(shape)
            .opacity(isEnabled ? 1 : 0.6)
            .rotation3DEffect(.degrees(active ? (0.5 - pointer.y) * 5 : 0),
                              axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.degrees(active ? (pointer.x - 0.5) * 4 : 0),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: .black.opacity(active ? 0.12 : 0), radius: active ? 8 : 0, y: active ? 3 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pointer)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: active)
            .accessibilityHidden(true)
            .overlay {
                HandCursorButton(
                    isEnabled: isEnabled,
                    label: label,
                    value: value,
                    onHover: { inside in
                        hovering = inside
                        if !inside { pointer = CGPoint(x: 0.5, y: 0.5) }
                    },
                    action: action,
                    onMove: { pointer = $0 },
                    showsToolTip: false
                )
            }
            .onDisappear { hovering = false }
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: icon, accessory: { EmptyView() }, content: content)
    }
}

struct StatusDot: View {
    let level: NetworkMonitor.Level

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch level {
        case .good: return .green
        case .fair: return .yellow
        case .bad: return .red
        case .unknown: return .gray
        }
    }
}

struct ProbeRow: View {
    let title: String
    let probe: NetworkMonitor.Probe

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(level: probe.level)
            Text(title).font(.callout)
            Spacer()
            Text(probe.value).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .help(probe.detail)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            }
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(busy)
        }
    }
}

/// 持有承载面板的 NSWindow：设为不透明，并按内容高度调整大小（保持顶边贴着菜单栏）。
@MainActor
final class PanelWindowController: ObservableObject {
    weak var window: NSWindow? {
        didSet {
            guard let window, window !== oldValue else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            if let pendingHeight { fit(height: pendingHeight) }
        }
    }
    private var pendingHeight: CGFloat?

    func fit(height: CGFloat) {
        guard height > 0 else { return }
        pendingHeight = height
        guard let window else { return }
        let contentRect = window.contentRect(forFrameRect: window.frame)
        guard abs(contentRect.height - height) > 0.5 else { return }
        var frame = window.frame
        let newHeight = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentRect.width, height: height)).height
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        window.setFrame(frame, display: true)
    }
}

struct PanelWindowAccessor: NSViewRepresentable {
    let controller: PanelWindowController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { controller.window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { controller.window = nsView.window }
    }
}
