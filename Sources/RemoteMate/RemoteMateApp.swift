import SwiftUI

@main
struct RemoteMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(controller.prefs)
                .environmentObject(controller.sleep)
                .environmentObject(controller.display)
                .environmentObject(controller.network)
        } label: {
            MenuBarLabel()
                .environmentObject(controller.prefs)
                .environmentObject(controller.sleep)
                .environmentObject(controller.display)
                .environmentObject(controller.network)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject private var controller = AppController.shared
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var sleep: SleepManager
    @EnvironmentObject private var display: VirtualDisplayManager
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        let state = controller.remoteState
        Image(nsImage: state == .off ? MenuBarIcon.idle : MenuBarIcon.active)
            .renderingMode(.template)
            .frame(width: 20, height: 18)
            .help("RemoteMate · 远程伴侣 · \(statusDescription)")
            .accessibilityLabel("RemoteMate 远程伴侣")
            .accessibilityValue(statusDescription)
    }

    private var statusDescription: String {
        let mode: String
        switch controller.remoteState {
        case .off: mode = "远程模式未开启"
        case .partial: mode = "远程模式部分开启"
        case .on: mode = "远程模式已开启"
        case .paused: mode = "远程模式已暂停，等待供电恢复"
        }
        var active: [String] = []
        if sleep.isPreventingIdleSleep { active.append("防休眠生效") }
        if sleep.lidSleepDisabled { active.append("合盖不休眠生效") }
        if display.isActive { active.append("虚拟屏幕已开启") }
        if prefs.launchUU && prefs.keepUUAlive {
            active.append(network.isUUKeepAliveEnabled ? "UU 保活已启用" : "UU 保活未启用")
        }
        return ([mode] + active).joined(separator: "，")
    }
}
