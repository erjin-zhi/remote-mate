import AppKit
import IOKit.ps
import IOKit.pwr_mgt

@MainActor
final class SleepManager: ObservableObject {
    enum PowerSource { case ac, battery, unknown }

    private enum Keys {
        static let ac = "sleep.preventOnAC"
        static let battery = "sleep.preventOnBattery"
        static let display = "sleep.keepDisplayAwake"
        static let lidMode = "sleep.lidMode"
        static let ownsLid = "sleep.ownsLidSetting"
    }

    private static let sudoersPath = "/etc/sudoers.d/remote-mate"

    @Published var preventOnAC: Bool {
        didSet { UserDefaults.standard.set(preventOnAC, forKey: Keys.ac); updateAssertions(); reconcileLid() }
    }
    @Published var preventOnBattery: Bool {
        didSet { UserDefaults.standard.set(preventOnBattery, forKey: Keys.battery); updateAssertions(); reconcileLid() }
    }
    @Published var keepDisplayAwake: Bool {
        didSet { UserDefaults.standard.set(keepDisplayAwake, forKey: Keys.display); updateAssertions() }
    }
    /// 用户是否开启「合盖不休眠」。实际是否禁用系统休眠还取决于供电，见 `lidShouldBeActive`。
    @Published var lidModeEnabled: Bool {
        didSet { UserDefaults.standard.set(lidModeEnabled, forKey: Keys.lidMode); reconcileLid() }
    }

    @Published private(set) var powerSource: PowerSource = .unknown
    @Published private(set) var hasBattery = false
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isPreventingIdleSleep = false
    @Published private(set) var lidSleepDisabled = false
    @Published private(set) var lidBusy = false
    @Published private(set) var passwordlessEnabled = false
    @Published var lastError: String?

    private var systemAssertion: IOPMAssertionID?
    private var displayAssertion: IOPMAssertionID?
    private var lidStateKnown = false
    private var lidReconcilePending = false
    /// 系统的 disablesleep 是否由本应用打开；只撤销自己打开的，避免误改其他工具的设置。
    private var ownsLidSetting: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.ownsLid) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.ownsLid) }
    }

    init() {
        let defaults = UserDefaults.standard
        preventOnAC = defaults.bool(forKey: Keys.ac)
        preventOnBattery = defaults.bool(forKey: Keys.battery)
        keepDisplayAwake = defaults.bool(forKey: Keys.display)
        lidModeEnabled = defaults.bool(forKey: Keys.lidMode)
        refreshPowerSource()
        observePowerSource()
        Task {
            await refreshLidState()
            await refreshPasswordless()
            lidStateKnown = true
            reconcileLid()
        }
    }

    // MARK: - 空闲防休眠（IOPMAssertion，无需权限）

    /// 当前供电状态下是否应阻止休眠。台式机等无电池机型视为接通电源。
    var shouldPreventNow: Bool {
        powerSource == .battery ? preventOnBattery : preventOnAC
    }

    private func updateAssertions() {
        let want = shouldPreventNow
        setAssertion(&systemAssertion, type: "PreventUserIdleSystemSleep", enabled: want)
        setAssertion(&displayAssertion, type: "PreventUserIdleDisplaySleep", enabled: want && keepDisplayAwake)
        isPreventingIdleSleep = systemAssertion != nil
    }

    private func setAssertion(_ id: inout IOPMAssertionID?, type: String, enabled: Bool) {
        if enabled, id == nil {
            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "RemoteMate remote session" as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                id = newID
            } else {
                lastError = "创建防休眠断言失败（\(result)）"
            }
        } else if !enabled, let existing = id {
            IOPMAssertionRelease(existing)
            id = nil
        }
    }

    // MARK: - 供电状态

    private func observePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let manager = Unmanaged<SleepManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.refreshPowerSource() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func refreshPowerSource() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            powerSource = .unknown
            updateAssertions()
            return
        }
        let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        switch type {
        case kIOPMACPowerKey: powerSource = .ac
        case kIOPMBatteryPowerKey: powerSource = .battery
        default: powerSource = .unknown
        }

        var foundBattery = false
        var level: Int?
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            foundBattery = true
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                level = current * 100 / max
            }
        }
        hasBattery = foundBattery
        batteryLevel = level
        updateAssertions()
        reconcileLid()
    }

    // MARK: - 合盖不休眠（pmset disablesleep，需要 root）

    func refreshLidState() async {
        let result = await Shell.runAsync("/usr/bin/pmset", ["-g"])
        lidSleepDisabled = Self.parseSleepDisabled(result.output)
    }

    static func parseSleepDisabled(_ output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled" { return parts.last == "1" }
        }
        return false
    }

    /// 合盖不休眠跟随供电：接电源时需开启「接通电源时不休眠」，用电池时需开启「使用电池时不休眠」。
    var lidShouldBeActive: Bool {
        lidModeEnabled && shouldPreventNow
    }

    /// 让系统的 disablesleep 与期望状态一致。插拔电源、切换开关时都会调用。
    private func reconcileLid() {
        guard lidStateKnown else { return }
        guard !lidBusy else {
            lidReconcilePending = true
            return
        }
        let want = lidShouldBeActive
        if want == lidSleepDisabled {
            if want { ownsLidSetting = true }
            return
        }
        // 系统已被其他工具禁用休眠时不去撤销
        if !want && !ownsLidSetting { return }
        Task { await applyLid(want) }
    }

    private func applyLid(_ disabled: Bool) async {
        lidBusy = true
        let value = disabled ? "1" : "0"
        var result: ShellResult = (1, "")
        if passwordlessEnabled {
            result = await Shell.runAsync("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])
            if result.status != 0 { passwordlessEnabled = false }
        }
        // 免密码规则不存在或失效时，改用系统密码弹窗
        if result.status != 0 {
            result = await Shell.runAsAdmin("/usr/bin/pmset -a disablesleep \(value)")
        }
        await refreshLidState()
        if lidSleepDisabled == disabled {
            ownsLidSetting = disabled
        } else if Shell.isUserCancel(result) {
            // 用户取消授权：开启时撤回开关，避免反复弹窗
            if disabled { lidModeEnabled = false }
        } else {
            lastError = "设置合盖不休眠失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        lidBusy = false
        if lidReconcilePending {
            lidReconcilePending = false
            reconcileLid()
        }
    }

    /// 退出时同步调用，恢复系统默认的合盖休眠。
    func restoreLidSleepSynchronously() {
        guard lidSleepDisabled, ownsLidSetting else { return }
        ownsLidSetting = false
        if passwordlessEnabled,
           Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]).status == 0 {
            return
        } else {
            Shell.run("/usr/bin/osascript", Shell.adminArgs("/usr/bin/pmset -a disablesleep 0"))
        }
    }

    // MARK: - 免密码授权（sudoers 规则，仅允许切换 disablesleep）

    func refreshPasswordless() async {
        // 不能只看 `sudo -l <cmd>` 的退出码：管理员账户的 (ALL) ALL 也会让它成功，但仍需要密码
        let result = await Shell.runAsync("/usr/bin/sudo", ["-n", "-l"])
        if result.status == 0 {
            passwordlessEnabled = result.output.contains("NOPASSWD: /usr/bin/pmset -a disablesleep")
        } else {
            passwordlessEnabled = FileManager.default.fileExists(atPath: Self.sudoersPath)
        }
    }

    func installPasswordless() async {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else {
            lastError = "用户名包含特殊字符，无法自动写入授权规则"
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let script = [
            "set -e",
            "TMP=$(/usr/bin/mktemp)",
            "trap '/bin/rm -f \"$TMP\"' EXIT",
            "/bin/echo '\(rule)' > \"$TMP\"",
            "/usr/sbin/visudo -cf \"$TMP\" >/dev/null",
            "/bin/mkdir -p /etc/sudoers.d",
            "/usr/bin/install -m 0440 -o root -g wheel \"$TMP\" \(Self.sudoersPath)",
        ].joined(separator: "\n")
        let result = await Shell.runAsAdmin(script)
        if result.status != 0 && !Shell.isUserCancel(result) {
            lastError = "授权失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        await refreshPasswordless()
    }

    func uninstallPasswordless() async {
        let result = await Shell.runAsAdmin("/bin/rm -f \(Self.sudoersPath)")
        if result.status != 0 && !Shell.isUserCancel(result) {
            lastError = "移除授权失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        await refreshPasswordless()
    }
}
