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
                .environmentObject(controller.updates)
        } label: {
            MenuBarLabel()
                .environmentObject(controller.prefs)
                .environmentObject(controller.sleep)
                .environmentObject(controller.display)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var sleep: SleepManager
    @EnvironmentObject private var display: VirtualDisplayManager

    var body: some View {
        let anyOn = sleep.isPreventingIdleSleep || sleep.lidSleepDisabled || display.isActive
        Image(nsImage: anyOn ? MenuBarIcon.active : MenuBarIcon.idle)
            .renderingMode(.template)
            .frame(width: 20, height: 18)
            .help("RemoteMate · 远程伴侣 · \(statusDescription)")
            .accessibilityLabel("RemoteMate 远程伴侣")
            .accessibilityValue(statusDescription)
    }

    private var statusDescription: String {
        var active: [String] = []
        if sleep.isPreventingIdleSleep { active.append("防休眠生效") }
        if sleep.lidSleepDisabled { active.append("合盖不休眠生效") }
        if display.isActive { active.append("虚拟屏幕已开启") }
        return active.isEmpty ? "防休眠与虚拟屏幕均未生效" : active.joined(separator: "，")
    }
}
