// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RemoteMate",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        // 私有 API CGVirtualDisplay 的 Objective-C 声明（实现位于系统 CoreGraphics 框架内）
        .target(
            name: "CGVirtualDisplayPrivate",
            path: "Sources/CGVirtualDisplayPrivate",
            linkerSettings: [.linkedFramework("CoreGraphics")]
        ),
        .executableTarget(
            name: "RemoteMate",
            dependencies: ["CGVirtualDisplayPrivate", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/RemoteMate",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                // Sparkle.framework 随 App 打包在 Contents/Frameworks 中
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "RemoteMateTests", dependencies: ["RemoteMate"]),
    ]
)
