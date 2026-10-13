import AppKit

// Design assets only. This script does not launch the app or change sleep settings.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func mark(_ state: String, color: NSColor, power: Bool = false) {
    color.setStroke()
    color.setFill()
    let frame = NSBezierPath(roundedRect: NSRect(x: 1, y: 4.5, width: 18, height: 12), xRadius: 2, yRadius: 2)
    frame.lineWidth = 1.5
    frame.stroke()
    let stand = NSBezierPath()
    stand.lineWidth = 1.5
    stand.lineCapStyle = .round
    stand.move(to: NSPoint(x: 10, y: 4.5))
    stand.line(to: NSPoint(x: 10, y: 1.5))
    stand.move(to: NSPoint(x: 6, y: 1.5))
    stand.line(to: NSPoint(x: 14, y: 1.5))
    stand.stroke()
    if state == "attention" {
        let stem = NSBezierPath()
        stem.lineWidth = 1.7
        stem.lineCapStyle = .round
        stem.move(to: NSPoint(x: 10, y: 13.5))
        stem.line(to: NSPoint(x: 10, y: 10))
        stem.stroke()
        NSBezierPath(ovalIn: NSRect(x: 9.1, y: 6.8, width: 1.8, height: 1.8)).fill()
    } else if power {
        if state == "active" {
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 10, y: 10), radius: 3.1, startAngle: 140, endAngle: 40, clockwise: false)
            ring.lineWidth = 1.35
            ring.lineCapStyle = .round
            ring.stroke()
            let stem = NSBezierPath()
            stem.lineWidth = 1.35
            stem.lineCapStyle = .round
            stem.move(to: NSPoint(x: 10, y: 14))
            stem.line(to: NSPoint(x: 10, y: 10.5))
            stem.stroke()
        }
    } else {
        let light = NSBezierPath(ovalIn: NSRect(x: 7.5, y: 8, width: 5, height: 5))
        light.lineWidth = 1.25
        if state == "active" { light.fill() } else { light.stroke() }
    }
}

func render(width: Int, height: Int, scale: Int = 2, draw: () -> Void) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func save(_ bitmap: NSBitmapImageRep, _ name: String) throws {
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}

for state in ["idle", "active", "attention"] {
    for scale in [1, 2] {
        try save(render(width: 20, height: 18, scale: scale) { mark(state, color: .black) },
                 "menu-\(state)\(scale == 2 ? "@2x" : "").png")
        try save(render(width: 20, height: 18, scale: scale) { mark(state, color: .black, power: true) },
                 "menu-power-\(state)\(scale == 2 ? "@2x" : "").png")
    }
    let center: String
    if state == "attention" {
        center = "<path d=\"M10 4.5v3.5\" stroke-width=\"1.7\"/><circle cx=\"10\" cy=\"10.3\" r=\".9\" fill=\"currentColor\" stroke=\"none\"/>"
    } else {
        center = "<circle cx=\"10\" cy=\"7.5\" r=\"2.5\" fill=\"\(state == "active" ? "currentColor" : "none")\" stroke-width=\"1.25\"/>"
    }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="18" viewBox="0 0 20 18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
    <rect x="1" y="1.5" width="18" height="12" rx="2"/><path d="M10 13.5v3M6 16.5h8"/>
    \(center)
    </svg>
    """
    try svg.write(to: destination.appendingPathComponent("menu-\(state).svg"), atomically: true, encoding: .utf8)
    let powerCenter = state == "attention" ? center : state == "idle" ? "" : "<path d=\"M7.625 6.007a3.1 3.1 0 1 0 4.75 0M10 4v3.5\" stroke-width=\"1.35\"/>"
    let powerSVG = svg.replacingOccurrences(of: center, with: powerCenter)
    try powerSVG.write(to: destination.appendingPathComponent("menu-power-\(state).svg"), atomically: true, encoding: .utf8)
}

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
        .foregroundColor: color
    ])
}

func drawMark(_ state: String, x: CGFloat, y: CGFloat, scale: CGFloat, color: NSColor, power: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x, yBy: y)
    transform.scale(by: scale)
    transform.concat()
    mark(state, color: color, power: power)
    NSGraphicsContext.restoreGraphicsState()
}

let preview = render(width: 920, height: 650) {
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 920, height: 650).fill()
    text("RemoteMate · 远程伴侣", x: 36, y: 600, size: 25, color: .black, bold: true)
    text("菜单栏图标提案  /  同一轮廓，清楚区分功能状态", x: 36, y: 572, size: 14, color: .darkGray)
    text("当前方案", x: 36, y: 519, size: 15, color: .black, bold: true)
    for (index, symbol) in ["moon.zzz", "dot.radiowaves.left.and.right"].enumerated() {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
        image.draw(in: NSRect(x: 160 + index * 210, y: 516, width: 28, height: 23))
        text(index == 0 ? "关闭" : "任一功能生效", x: CGFloat(202 + index * 210), y: 519, size: 13, color: .darkGray)
    }
    text("A · 显示器 + 电源（推荐）", x: 36, y: 459, size: 15, color: .black, bold: true)
    let states = ["idle", "active", "attention"]
    let powerLabels = ["未生效 · 空屏", "功能生效 · 电源", "需处理 · 感叹号"]
    for i in 0..<3 {
        let x = CGFloat(165 + i * 245)
        drawMark(states[i], x: x, y: 398, scale: 2.5, color: .black, power: true)
        text(powerLabels[i], x: x - 15, y: 370, size: 13, color: .darkGray)
    }
    text("深色 · 实际尺寸", x: 36, y: 328, size: 12, color: .darkGray)
    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 165, y: 313, width: 630, height: 42), xRadius: 8, yRadius: 8).fill()
    for i in 0..<3 { drawMark(states[i], x: CGFloat(205 + i * 245), y: 326, scale: 1, color: .white, power: true) }
    text("B · 显示器 + 状态灯", x: 36, y: 275, size: 15, color: .black, bold: true)
    let labels = ["未生效 · 空心灯", "功能生效 · 实心灯", "需处理 · 感叹号"]
    for i in 0..<3 {
        let x = CGFloat(165 + i * 245)
        drawMark(states[i], x: x, y: 213, scale: 2.5, color: .black)
        text(labels[i], x: x - 15, y: 185, size: 13, color: .darkGray)
    }
    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 36, y: 96, width: 848, height: 70), xRadius: 12, yRadius: 12).fill()
    text("深色菜单栏 · 实际尺寸", x: 54, y: 124, size: 13, color: .white)
    for i in 0..<3 { drawMark(states[i], x: CGFloat(320 + i * 180), y: 122, scale: 1, color: .white) }
    text("20 × 18 pt · 单色 Template · 固定占位 · 无常驻动画", x: 36, y: 56, size: 13, color: .darkGray)
    text("“功能生效”只表示本机防休眠或虚拟屏幕状态，不代表远程已连接。", x: 36, y: 30, size: 13, color: .darkGray)
}
try save(preview, "menu-bar-preview.png")
