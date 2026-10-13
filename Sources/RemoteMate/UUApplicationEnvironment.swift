import AppKit

/// 将主程序、常驻后台服务和启动动作分开，避免用服务进程推断客户端运行状态。
@MainActor
struct UUApplicationEnvironment {
    nonisolated static let bundleIdentifier = "com.netease.uuremote"

    var isInstalled: () -> Bool
    var isClientRunning: () -> Bool
    var isBackgroundRunning: () -> Bool
    var open: (Bool) async throws -> Void

    static var live: Self {
        Self(
            isInstalled: { FileManager.default.fileExists(atPath: NetworkMonitor.uuAppPath) },
            isClientRunning: {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                    .contains { !$0.isTerminated }
            },
            isBackgroundRunning: {
                ["UURemoteDaemon", "UURemoteService", "UURemoteServer"].contains {
                    Shell.run("/usr/bin/pgrep", ["-x", $0]).status == 0
                }
            },
            open: { activate in
                let config = NSWorkspace.OpenConfiguration()
                config.activates = activate
                _ = try await NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: NetworkMonitor.uuAppPath), configuration: config
                )
            }
        )
    }
}
