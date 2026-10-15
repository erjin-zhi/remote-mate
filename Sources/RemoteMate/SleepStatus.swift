import Foundation

/// 仅包含实际状态；电量刷新和未生效的偏好变化不会产生新通知。
struct SleepStatus: Equatable {
    enum Power: Equatable { case ac, battery, unknown }
    enum Lid: Equatable { case unknown, changing, enabled, disabled }

    var power: Power
    var idlePrevention: Bool
    var displayPrevention: Bool
    var lid: Lid
    var lidChangeFailed: Bool

    var powerDescription: String {
        switch power {
        case .ac: return "已接通电源"
        case .battery: return "正在使用电池"
        case .unknown: return "供电状态未知"
        }
    }

    var body: String {
        var lines = [
            "空闲防休眠：\(idlePrevention ? "已开启" : "已关闭，由系统决定休眠")",
            "屏幕常亮：\(displayPrevention ? "已开启" : "已关闭")",
        ]
        switch lid {
        case .unknown: lines.append("合盖不休眠：暂时无法确认")
        case .changing: lines.append("合盖不休眠：正在切换，可能需要管理员授权")
        case .enabled: lines.append("合盖不休眠：已开启")
        case .disabled: lines.append("合盖不休眠：已关闭")
        }
        if lidChangeFailed { lines.append("合盖设置未完成，请打开远程伴侣检查") }
        return lines.joined(separator: "\n")
    }
}
