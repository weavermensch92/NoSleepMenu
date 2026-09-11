import Foundation

struct WeeklyUsage: Sendable {
    let remainingPercent: Int
    let resetsAt: Date
}

enum UsageReadError: Error {
    case missingCodex, disconnected, invalidResponse, unavailable
}

/// Uses the signed-in Codex app-server; credentials never leave its own auth storage.
enum CodexWeeklyUsageReader {
    static func parse(_ result: [String: Any]) throws -> WeeklyUsage {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let snapshot: [String: Any]?
        if let buckets {
            snapshot = buckets["codex"] as? [String: Any]
        } else {
            snapshot = result["rateLimits"] as? [String: Any]
        }
        guard let snapshot else { throw UsageReadError.unavailable }
        for key in ["primary", "secondary"] {
            guard let window = snapshot[key] as? [String: Any],
                  let minutes = window["windowDurationMins"] as? Int,
                  minutes == 7 * 24 * 60,
                  let used = window["usedPercent"] as? Double,
                  used.isFinite,
                  let reset = window["resetsAt"] as? Double,
                  reset.isFinite, reset > Date().timeIntervalSince1970 else { continue }
            return WeeklyUsage(remainingPercent: Int(max(0, min(100, 100 - used)).rounded()),
                               resetsAt: Date(timeIntervalSince1970: reset))
        }
        throw UsageReadError.unavailable
    }

    static func fetch(executablePath: String = "") throws -> WeeklyUsage {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = executablePath.isEmpty ? [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/ChatGPT.app/Contents/Resources/codex",
            home + "/Applications/Codex.app/Contents/Resources/codex",
            home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ] : [executablePath]
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw UsageReadError.missingCodex }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = home + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ value: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: value)
            bytes.append(10)
            try input.fileHandleForWriting.write(contentsOf: bytes)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "nosleepmenu_usage", "title": "NoSleepMenu", "version": "1.1.0"]
        ]])
        var pending = Data()
        while true {
            let bytes = output.fileHandleForReading.availableData
            guard !bytes.isEmpty else { throw UsageReadError.disconnected }
            pending.append(bytes)
            guard pending.count < 4_000_000 else { throw UsageReadError.invalidResponse }
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = message["id"] as? Int else { continue }
                if message["error"] != nil { throw UsageReadError.unavailable }
                if id == 1 {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2 {
                    guard let result = message["result"] as? [String: Any] else {
                        throw UsageReadError.invalidResponse
                    }
                    return try parse(result)
                }
            }
        }
    }
}
