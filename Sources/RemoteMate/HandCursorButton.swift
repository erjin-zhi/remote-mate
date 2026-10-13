import SwiftUI

/// 原生按钮承接整行点击和光标区域，避免 SwiftUI 在鼠标移动时覆盖 onHover 设置的光标。
struct HandCursorButton: NSViewRepresentable {
    var isEnabled: Bool
    var label: String
    var value: String
    var onHover: (Bool) -> Void
    var action: () -> Void

    func makeNSView(context: Context) -> NativeButton {
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
                options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self)
            addTrackingArea(area)
            hoverTracking = area
        }

        override func cursorUpdate(with event: NSEvent) {
            (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }
    }
}
