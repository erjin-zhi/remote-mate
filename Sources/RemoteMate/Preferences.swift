import Foundation
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    enum Keys {
        static let includeAC = "remote.includeAC"
        static let includeBattery = "remote.includeBattery"
        static let includeLid = "remote.includeLid"
        static let includeDisplay = "remote.includeDisplay"
        static let launchUU = "remote.launchUU"
        static let autoStartRemote = "app.autoStartRemote"
        static let restoreOnQuit = "app.restoreLidOnQuit"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.includeAC: true,
            Keys.includeBattery: false,
            Keys.includeLid: true,
            Keys.includeDisplay: true,
            Keys.launchUU: true,
            Keys.autoStartRemote: false,
            Keys.restoreOnQuit: true,
            "sleep.keepDisplayAwake": true,
            "display.width": 1920,
            "display.height": 1080,
            "display.refreshRate": 60.0,
            "display.hiDPI": false,
            "display.makeMain": false,
        ])
    }

    @Published var includeAC: Bool { didSet { save(includeAC, Keys.includeAC) } }
    @Published var includeBattery: Bool { didSet { save(includeBattery, Keys.includeBattery) } }
    @Published var includeLid: Bool { didSet { save(includeLid, Keys.includeLid) } }
    @Published var includeDisplay: Bool { didSet { save(includeDisplay, Keys.includeDisplay) } }
    @Published var launchUU: Bool { didSet { save(launchUU, Keys.launchUU) } }
    @Published var autoStartRemote: Bool { didSet { save(autoStartRemote, Keys.autoStartRemote) } }
    @Published var restoreOnQuit: Bool { didSet { save(restoreOnQuit, Keys.restoreOnQuit) } }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var lastError: String?

    init() {
        let d = UserDefaults.standard
        includeAC = d.bool(forKey: Keys.includeAC)
        includeBattery = d.bool(forKey: Keys.includeBattery)
        includeLid = d.bool(forKey: Keys.includeLid)
        includeDisplay = d.bool(forKey: Keys.includeDisplay)
        launchUU = d.bool(forKey: Keys.launchUU)
        autoStartRemote = d.bool(forKey: Keys.autoStartRemote)
        restoreOnQuit = d.bool(forKey: Keys.restoreOnQuit)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "登录启动设置失败：\(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
