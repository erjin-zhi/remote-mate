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

            let light = NSBezierPath(ovalIn: NSRect(x: 7.5, y: 8, width: 5, height: 5))
            light.lineWidth = 1.25
            if active { light.fill() } else { light.stroke() }
            return true
        }
        image.isTemplate = true
        return image
    }
}
