// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RmtPilot",
    platforms: [.macOS(.v14)],
    targets: [
        // 私有 API CGVirtualDisplay 的 Objective-C 声明（实现位于系统 CoreGraphics 框架内）
        .target(
            name: "CGVirtualDisplayPrivate",
            path: "Sources/CGVirtualDisplayPrivate",
            linkerSettings: [.linkedFramework("CoreGraphics")]
        ),
        .executableTarget(
            name: "RmtPilot",
            dependencies: ["CGVirtualDisplayPrivate"],
            path: "Sources/RmtPilot",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
