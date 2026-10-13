import SwiftUI

@main
struct RmtPilotApp: App {
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
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var sleep: SleepManager
    @EnvironmentObject private var display: VirtualDisplayManager

    var body: some View {
        let anyOn = sleep.isPreventingIdleSleep || sleep.lidSleepDisabled || display.isActive
        Image(systemName: anyOn ? "dot.radiowaves.left.and.right" : "moon.zzz")
    }
}
