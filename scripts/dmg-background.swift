// 生成 DMG 安装窗口背景图：用法 swift dmg-background.swift <输出.png> <缩放倍数>
import AppKit

let args = CommandLine.arguments
let output = args[1]
let scale = CGFloat(Double(args[2]) ?? 1)

// 与 build-dmg.sh 中的窗口尺寸、图标位置保持一致。
let size = CGSize(width: 660, height: 400)
let appCenter = CGPoint(x: 180, y: 200)
let appsCenter = CGPoint(x: 480, y: 200)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// AppKit 坐标原点在左下角，Finder 图标坐标原点在左上角，这里统一翻转为左上角。
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)
let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
NSGraphicsContext.current = flipped

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// 背景：极浅的薄荷绿渐变，呼应 App 图标。
NSGradient(colors: [color(0xFBFEFD), color(0xEAF7F3)])!
    .draw(in: CGRect(origin: .zero, size: size), angle: 90)

// 两个柔和的光斑托住图标。
for center in [appCenter, appsCenter] {
    let glow = NSGradient(colors: [color(0xFFFFFF, 0.95), color(0xFFFFFF, 0)])!
    glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 118, options: [])
}

// 标题
func drawText(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat, kern: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                .paragraphStyle: style, .kern: kern]
    let height = (text as NSString).size(withAttributes: attrs).height
    (text as NSString).draw(in: CGRect(x: 0, y: centerY - height / 2, width: size.width, height: height),
                            withAttributes: attrs)
}
drawText("安装 RemoteMate · 远程伴侣", font: .systemFont(ofSize: 20, weight: .semibold),
         color: color(0x1F3B36), centerY: 56)
drawText("为远程连接，一键准备好你的 Mac", font: .systemFont(ofSize: 12.5, weight: .regular),
         color: color(0x5E7C76), centerY: 84)

// 拖动箭头：轻微上拱的虚线弧 + 圆润箭头。
let start = CGPoint(x: appCenter.x + 88, y: appCenter.y - 4)
let end = CGPoint(x: appsCenter.x - 92, y: appsCenter.y - 4)
let control = CGPoint(x: (start.x + end.x) / 2, y: appCenter.y - 46)
let arrowColor = color(0x2BB39C)

// 箭头方向沿曲线末端切线；虚线在箭头前留出空隙，避免与箭头粘连。
let angle = atan2(end.y - control.y, end.x - control.x)
let arcEnd = CGPoint(x: end.x - 9 * cos(angle), y: end.y - 9 * sin(angle))
let arc = NSBezierPath()
arc.move(to: start)
arc.curve(to: arcEnd, controlPoint1: control, controlPoint2: control)
arc.lineWidth = 3
arc.lineCapStyle = .round
arc.setLineDash([0.1, 9], count: 2, phase: 0)
arrowColor.withAlphaComponent(0.85).setStroke()
arc.stroke()

let head = NSBezierPath()
let len: CGFloat = 12, spread: CGFloat = .pi / 4.2
head.move(to: CGPoint(x: end.x - len * cos(angle - spread), y: end.y - len * sin(angle - spread)))
head.line(to: end)
head.line(to: CGPoint(x: end.x - len * cos(angle + spread), y: end.y - len * sin(angle + spread)))
head.lineWidth = 3
head.lineCapStyle = .round
head.lineJoinStyle = .round
arrowColor.setStroke()
head.stroke()

// 底部操作提示胶囊
let hint = "将「远程伴侣」拖到「Applications」文件夹即可完成安装"
let hintFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
let hintWidth = (hint as NSString).size(withAttributes: [.font: hintFont]).width + 36
let pill = CGRect(x: (size.width - hintWidth) / 2, y: 304, width: hintWidth, height: 30)
color(0xFFFFFF, 0.8).setFill()
NSBezierPath(roundedRect: pill, xRadius: 15, yRadius: 15).fill()
color(0x2BB39C, 0.25).setStroke()
let border = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 14.5, yRadius: 14.5)
border.lineWidth = 1
border.stroke()
drawText(hint, font: hintFont, color: color(0x2E5A53), centerY: pill.midY)

drawText("Drag RemoteMate to Applications to install", font: .systemFont(ofSize: 10.5),
         color: color(0x8AA59F), centerY: 352)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
