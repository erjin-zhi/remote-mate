import AppKit
import CGVirtualDisplayPrivate
import CoreGraphics

struct Resolution: Hashable, Identifiable {
    let width: Int
    let height: Int

    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }

    /// 与远程端屏幕比例一致时画面铺满、不留黑边。
    var menuLabel: String {
        guard let note = Self.notes[self] else { return label }
        return "\(label)（\(note)）"
    }

    /// 按控制端设备分组，菜单里组与组之间用分隔线隔开；1920 × 1080 两端通用，单独放在中间。
    static let presetGroups: [[Resolution]] = [
        [
            .init(width: 1280, height: 720),
            .init(width: 1440, height: 900),
            .init(width: 1680, height: 1050),
            .init(width: 1920, height: 1200),
            .init(width: 2560, height: 1440),
            .init(width: 2560, height: 1600),
            .init(width: 3840, height: 2160),
        ],
        [
            .init(width: 1920, height: 1080),
        ],
        [
            .init(width: 1335, height: 939),
            .init(width: 1416, height: 984),
            .init(width: 1600, height: 1200),
        ],
    ]

    static var presets: [Resolution] { presetGroups.flatMap { $0 } }

    private static let notes: [Resolution: String] = [
        .init(width: 1280, height: 720): "流畅 16:9",
        // iPhone Duo 内屏 2670 × 1878（横屏）的一半，比例约 10:7
        .init(width: 1335, height: 939): "iPhone Duo 展开 10:7",
        // iPad Air 11 / iPad 2360 × 1640 的 0.6 倍
        .init(width: 1416, height: 984): "iPad 11 寸",
        .init(width: 1440, height: 900): "MacBook 16:10",
        .init(width: 1600, height: 1200): "iPad 13 寸 4:3",
        .init(width: 1680, height: 1050): "MacBook 大屏 16:10",
        .init(width: 1920, height: 1080): "通用 16:9",
        .init(width: 1920, height: 1200): "16:10",
        .init(width: 2560, height: 1600): "16:10",
        .init(width: 2560, height: 1440): "2K 16:9",
        .init(width: 3840, height: 2160): "4K 16:9",
    ]

    static let widthRange = 640...7680
    static let heightRange = 480...4320
}

@MainActor
final class VirtualDisplayManager: ObservableObject {
    private enum Keys {
        static let width = "display.width"
        static let height = "display.height"
        static let refreshRate = "display.refreshRate"
        static let hiDPI = "display.hiDPI"
        static let makeMain = "display.makeMain"
    }

    @Published private(set) var width: Int
    @Published private(set) var height: Int
    @Published var refreshRate: Double {
        didSet { UserDefaults.standard.set(refreshRate, forKey: Keys.refreshRate); applyIfActive() }
    }
    @Published var hiDPI: Bool {
        didSet { UserDefaults.standard.set(hiDPI, forKey: Keys.hiDPI); applyIfActive() }
    }
    @Published var makeMainOnStart: Bool {
        didSet { UserDefaults.standard.set(makeMainOnStart, forKey: Keys.makeMain) }
    }

    @Published private(set) var isActive = false
    /// 改分辨率或 HiDPI 时会先移除屏幕再重建，期间 `isActive` 短暂为假，但不代表用户关闭了它。
    @Published private(set) var isRebuilding = false
    @Published private(set) var displayID: CGDirectDisplayID = 0
    @Published private(set) var currentModeText = ""
    @Published var lastError: String?

    private var display: CGVirtualDisplay?
    private var appliedHiDPI = false
    private var maxWidth = 0
    private var maxHeight = 0

    init() {
        let defaults = UserDefaults.standard
        width = defaults.integer(forKey: Keys.width)
        height = defaults.integer(forKey: Keys.height)
        refreshRate = defaults.double(forKey: Keys.refreshRate)
        hiDPI = defaults.bool(forKey: Keys.hiDPI)
        makeMainOnStart = defaults.bool(forKey: Keys.makeMain)
    }

    var resolution: Resolution { Resolution(width: width, height: height) }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    func setResolution(width: Int, height: Int) {
        guard Resolution.widthRange.contains(width), Resolution.heightRange.contains(height) else {
            lastError = "分辨率需在 \(Resolution.widthRange.lowerBound)×\(Resolution.heightRange.lowerBound) 到 \(Resolution.widthRange.upperBound)×\(Resolution.heightRange.upperBound) 之间"
            return
        }
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        UserDefaults.standard.set(width, forKey: Keys.width)
        UserDefaults.standard.set(height, forKey: Keys.height)
        applyIfActive()
    }

    // MARK: - 生命周期

    func start() {
        isRebuilding = false
        guard display == nil else { return }
        let scale = hiDPI ? 2 : 1
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "RemoteMate Display"
        descriptor.maxPixelsWide = UInt32(width * scale)
        descriptor.maxPixelsHigh = UInt32(height * scale)
        // 按约 96 PPI 估算物理尺寸，让系统给出合理的默认缩放
        descriptor.sizeInMillimeters = CGSize(width: Double(width) / 96 * 25.4, height: Double(height) / 96 * 25.4)
        // 固定的厂商/序列号让 macOS 记住该屏幕的排列位置
        descriptor.vendorID = 0x524D
        descriptor.productID = 0x0001
        descriptor.serialNum = 0x0001
        descriptor.terminationHandler = { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleTermination() }
        }

        guard let newDisplay = CGVirtualDisplay(descriptor: descriptor) else {
            lastError = "创建虚拟屏幕失败"
            return
        }
        display = newDisplay
        appliedHiDPI = hiDPI
        maxWidth = width
        maxHeight = height

        guard applyModes(to: newDisplay) else {
            display = nil
            lastError = "虚拟屏幕不接受当前分辨率设置"
            return
        }
        isActive = true
        displayID = newDisplay.displayID

        // 新屏幕需要片刻才会出现在显示器列表里
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isActive else { return }
            self.selectCurrentMode()
            if self.makeMainOnStart { self.makeMain() }
            self.refreshModeText()
        }
    }

    func stop() {
        isRebuilding = false
        display = nil  // 释放对象即移除虚拟屏幕
        isActive = false
        displayID = 0
        currentModeText = ""
    }

    private func handleTermination() {
        guard isActive else { return }
        stop()
        lastError = "虚拟屏幕已被系统移除"
    }

    // MARK: - 模式

    private func applyIfActive() {
        guard let display else { return }
        if hiDPI == appliedHiDPI, width <= maxWidth, height <= maxHeight, applyModes(to: display) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.selectCurrentMode()
                self?.refreshModeText()
            }
        } else {
            // 超出最大像素或切换 HiDPI 时需要重建屏幕
            stop()
            isRebuilding = true
            // 等待期间用户关闭了屏幕（stop 会清掉 isRebuilding）就不再重建
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.isRebuilding else { return }
                self.start()
            }
        }
    }

    /// 当前分辨率放在首位，其余为不超过最大像素的预设，方便在系统设置里切换。
    private func modeList() -> [Resolution] {
        let selected = resolution
        let others = Resolution.presets.filter {
            $0 != selected && $0.width <= maxWidth && $0.height <= maxHeight
        }
        return [selected] + others.reversed()
    }

    private func applyModes(to display: CGVirtualDisplay) -> Bool {
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = appliedHiDPI ? 1 : 0
        settings.modes = modeList().map {
            CGVirtualDisplayMode(width: UInt32($0.width), height: UInt32($0.height), refreshRate: refreshRate)
        }
        return display.apply(settings)
    }

    private func selectCurrentMode() {
        guard displayID != 0 else { return }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else { return }
        let pixelWidth = width * (appliedHiDPI ? 2 : 1)
        let candidates = modes.filter { $0.width == width && $0.height == height }
        guard let target = candidates.first(where: { $0.pixelWidth == pixelWidth && abs($0.refreshRate - refreshRate) < 1 })
            ?? candidates.first(where: { $0.pixelWidth == pixelWidth })
            ?? candidates.first else { return }

        if let current = CGDisplayCopyDisplayMode(displayID),
           current.width == target.width, current.height == target.height,
           current.pixelWidth == target.pixelWidth, current.refreshRate == target.refreshRate {
            return
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayWithDisplayMode(config, displayID, target, nil)
        CGCompleteDisplayConfiguration(config, .permanently)
    }

    /// 平移所有屏幕坐标，使虚拟屏幕位于原点，即成为主显示器（菜单栏和程序坞所在）。
    func makeMain() {
        guard displayID != 0, CGMainDisplayID() != displayID else { return }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        let origin = CGDisplayBounds(displayID).origin
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for id in ids {
            let bounds = CGDisplayBounds(id)
            CGConfigureDisplayOrigin(config, id, Int32(bounds.minX - origin.x), Int32(bounds.minY - origin.y))
        }
        if CGCompleteDisplayConfiguration(config, .permanently) != .success {
            lastError = "设置主显示器失败"
        }
    }

    var isMain: Bool { displayID != 0 && CGMainDisplayID() == displayID }

    func refreshModeText() {
        guard displayID != 0, let mode = CGDisplayCopyDisplayMode(displayID) else {
            currentModeText = ""
            return
        }
        var text = "\(mode.width)×\(mode.height) @\(Int(mode.refreshRate.rounded()))Hz"
        if mode.pixelWidth > mode.width {
            text += " · HiDPI \(mode.pixelWidth)×\(mode.pixelHeight)"
        }
        currentModeText = text
    }
}
