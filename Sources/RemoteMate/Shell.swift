import Foundation

typealias ShellResult = (status: Int32, output: String)

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func runAsync(_ path: String, _ args: [String]) async -> ShellResult {
        await Task.detached { run(path, args) }.value
    }

    /// 通过系统授权弹窗以管理员身份执行 shell 命令。
    static func adminArgs(_ command: String) -> [String] {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
    }

    static func runAsAdmin(_ command: String) async -> ShellResult {
        await runAsync("/usr/bin/osascript", adminArgs(command))
    }

    static func isUserCancel(_ result: ShellResult) -> Bool {
        result.output.contains("-128")
    }
}
