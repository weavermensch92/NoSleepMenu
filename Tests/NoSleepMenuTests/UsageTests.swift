import XCTest
@testable import NoSleepMenu

final class UsageTests: XCTestCase {
    private let future = Date().timeIntervalSince1970 + 3600
    private func window(_ used: Double, minutes: Int = 10080) -> [String: Any] {
        ["usedPercent": used, "windowDurationMins": minutes, "resetsAt": future]
    }
    func testCodexPrimaryAndSecondaryWeeklyWindows() throws {
        let primary = try CodexWeeklyUsageReader.parse(["rateLimits": ["primary": window(8)]])
        XCTAssertEqual(primary.remainingPercent, 92)
        let secondary = try CodexWeeklyUsageReader.parse(["rateLimits": ["primary": window(90, minutes: 300), "secondary": window(24)]])
        XCTAssertEqual(secondary.remainingPercent, 76)
    }
    func testCodexPrefersNamedBucketAndRejectsMissingOrExpired() throws {
        let value = try CodexWeeklyUsageReader.parse(["rateLimits": ["primary": window(80)], "rateLimitsByLimitId": ["codex": ["primary": window(8)]]])
        XCTAssertEqual(value.remainingPercent, 92)
        for invalid: [String: Any] in [[:], ["rateLimits": ["primary": window(20, minutes: 300)]], ["rateLimitsByLimitId": ["other": [:]]], ["rateLimits": ["primary": ["windowDurationMins": 10080, "usedPercent": 1, "resetsAt": 1]]]] {
            XCTAssertThrowsError(try CodexWeeklyUsageReader.parse(invalid))
        }
    }
    func testClampRemaining() throws {
        XCTAssertEqual(try CodexWeeklyUsageReader.parse(["rateLimits": ["primary": window(150)]]).remainingPercent, 0)
        XCTAssertEqual(try CodexWeeklyUsageReader.parse(["rateLimits": ["primary": window(-10)]]).remainingPercent, 100)
    }
    func testClaudeDateFormatsAndMissingValues() throws {
        for reset in ["2099-01-01T00:00:00Z", "2099-01-01T00:00:00.123456+00:00"] {
            let data = try JSONSerialization.data(withJSONObject: ["seven_day": ["utilization": 1, "resets_at": reset]])
            XCTAssertEqual(try ClaudeWeeklyUsageReader.parse(data).remainingPercent, 99)
        }
        for invalid in ["{}", "{\"seven_day\":null}", "{\"seven_day\":{\"utilization\":1,\"resets_at\":\"2000-01-01T00:00:00Z\"}}"] {
            XCTAssertThrowsError(try ClaudeWeeklyUsageReader.parse(Data(invalid.utf8)))
        }
    }
    func testOwnBundlePreferencesUseStandardStore() {
        XCTAssertTrue(AppSettings.preferences(for: AppIdentity.bundleID) === UserDefaults.standard)
    }
    func testLocalization() {
        XCTAssertEqual(Localization.resolvedLanguage("system", preferredLanguages: ["ko-KR"]), "ko")
        XCTAssertEqual(Localization.resolvedLanguage("system", preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(Localization.resolvedLanguage("en", preferredLanguages: ["ko-KR"]), "en")
        XCTAssertEqual(Localization.text("잠자기 방지", language: "en"), "Prevent sleep")
        XCTAssertEqual(Localization.text("%@ 주간 잔액 조회 중…", language: "en", values: ["Claude"]), "Loading Claude weekly remaining…")
    }
}
