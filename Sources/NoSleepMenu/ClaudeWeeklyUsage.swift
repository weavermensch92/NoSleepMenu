import Foundation

enum ClaudeUsageError: Error {
    case loginRequired, unavailable, throttled
    var message: String {
        switch self {
        case .loginRequired: return L("Claude 인증 갱신 필요 — Claude Code에서 /usage를 실행하세요.")
        case .unavailable: return L("Claude 주간 한도를 조회할 수 없습니다.")
        case .throttled: return L("Claude 조회 제한 — 잠시 후 자동으로 다시 확인합니다.")
        }
    }
}

enum ClaudeWeeklyUsageReader {
    /// Read only the existing Claude Code credential. Never log or duplicate tokens.
    private static func accessToken() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel(); try? output.fileHandleForReading.close() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = root["claudeAiOauth"] as? [String: Any],
              let token = auth["accessToken"] as? String, !token.isEmpty else {
            throw ClaudeUsageError.loginRequired
        }
        return token
    }

    static func parse(_ data: Data) throws -> WeeklyUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let week = root["seven_day"] as? [String: Any],
              let used = week["utilization"] as? Double, used.isFinite,
              let resetText = week["resets_at"] as? String else { throw ClaudeUsageError.unavailable }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var reset = formatter.date(from: resetText)
        if reset == nil {
            formatter.formatOptions = [.withInternetDateTime]
            reset = formatter.date(from: resetText)
        }
        guard let reset, reset > Date() else { throw ClaudeUsageError.unavailable }
        return WeeklyUsage(remainingPercent: Int(max(0, min(100, 100 - used)).rounded()), resetsAt: reset)
    }

    static func fetch() async throws -> WeeklyUsage {
        let token = try await Task.detached(priority: .utility) { try accessToken() }.value
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("NoSleepMenu/1.2.0", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.unavailable }
        switch response.statusCode {
        case 200: return try parse(data)
        case 401, 403: throw ClaudeUsageError.loginRequired
        case 429: throw ClaudeUsageError.throttled
        default: throw ClaudeUsageError.unavailable
        }
    }
}
