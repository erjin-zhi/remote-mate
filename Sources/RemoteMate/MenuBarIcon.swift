import AppKit

/// Fixed monitor silhouette with a hollow/solid status light.
/// Reports local feature activity, never remote connection status.
enum MenuBarIcon {
    static let idle = make(active: false)
    static let active = make(active: true)

    private static func make(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let screen = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 4.5, width: 18, height: 12),
                xRadius: 2, yRadius: 2
            )
            screen.lineWidth = 1.5
            screen.stroke()

            let stand = NSBezierPath()
            stand.lineWidth = 1.5
            stand.lineCapStyle = .round
            stand.move(to: NSPoint(x: 10, y: 4.5))
            stand.line(to: NSPoint(x: 10, y: 1.5))
            stand.move(to: NSPoint(x: 6, y: 1.5))
            stand.line(to: NSPoint(x: 14, y: 1.5))
            stand.stroke()

            // 空心态需要足够大的内孔，否则在菜单栏尺寸下看起来和实心一样
            if active {
                NSBezierPath(ovalIn: NSRect(x: 7, y: 7.5, width: 6, height: 6)).fill()
            } else {
                let ring = NSBezierPath(ovalIn: NSRect(x: 7, y: 7.5, width: 6, height: 6))
                ring.lineWidth = 1
                ring.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
