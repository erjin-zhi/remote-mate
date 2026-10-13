import SwiftUI
import Darwin

/// macOS 默认只允许前台应用设置光标。点击「打开」后 UU 远程成为前台应用，面板仍停留在屏幕上，
/// 不开启此属性时手型光标要等本应用重新激活才会出现。通过 dlsym 调用私有接口，缺失时静默跳过。
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static let enable: Void = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connSym = dlsym(handle, "_CGSDefaultConnection"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connSym, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSym, to: SetConnectionProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }()
}

/// 原生按钮承接整行点击和光标区域，避免 SwiftUI 在鼠标移动时覆盖 onHover 设置的光标。
struct HandCursorButton: NSViewRepresentable {
    var isEnabled: Bool
    var label: String
    var value: String
    var onHover: (Bool) -> Void
    var action: () -> Void

    func makeNSView(context: Context) -> NativeButton {
        _ = BackgroundCursor.enable
        let button = NativeButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(NativeButton.invokeAction)
        return button
    }

    func updateNSView(_ button: NativeButton, context: Context) {
        button.onPress = action
        button.onHover = onHover
        button.isEnabled = isEnabled
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(value)
        button.window?.invalidateCursorRects(for: button)
    }

    final class NativeButton: NSButton {
        var onPress: (() -> Void)?
        var onHover: ((Bool) -> Void)?
        private var hoverTracking: NSTrackingArea?

        // 启动结束后按钮重新可用时鼠标往往停在原地，且 UU 被激活后本应用不再是活跃应用，
        // 光标矩形不会重新生效；这里在状态切换时直接按鼠标位置刷新光标。
        override var isEnabled: Bool {
            didSet {
                guard isEnabled != oldValue else { return }
                window?.invalidateCursorRects(for: self)
                refreshCursorIfHovered()
            }
        }

        private func refreshCursorIfHovered() {
            guard let window, !isHidden else { return }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard bounds.contains(point) else { return }
            (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        @objc func invokeAction() {
            guard isEnabled else { return }
            onPress?()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTracking { removeTrackingArea(hoverTracking) }
            let area = NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self)
            addTrackingArea(area)
            hoverTracking = area
        }

        override func cursorUpdate(with event: NSEvent) {
            (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        // 本应用非活跃时不会收到 cursorUpdate，用 mouseMoved 兜底（需配合 BackgroundCursor）。
        override func mouseMoved(with event: NSEvent) {
            (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        override func mouseEntered(with event: NSEvent) {
            (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }
    }
}
