import Foundation

enum Localization {
    static var language: String {
        resolvedLanguage(AppSettings.language, preferredLanguages: Locale.preferredLanguages)
    }
    static func resolvedLanguage(_ selected: String, preferredLanguages: [String]) -> String {
        if selected == "ko" || selected == "en" { return selected }
        return preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en"
    }
    static let english: [String: String] = [
        "%@ 주간 잔액 %@ · %@ 초기화": "%@ weekly remaining %@ · resets %@",
        "%@ 주간 잔액 조회 중…": "Loading %@ weekly remaining…",
        "Claude 사용량 조회 실패 — 네트워크를 확인하세요.": "Could not load Claude usage. Check your network.",
        "Claude 인증 갱신 필요 — Claude Code에서 /usage를 실행하세요.": "Refresh Claude authentication by running /usage in Claude Code.",
        "Claude 조회 제한 — 잠시 후 자동으로 다시 확인합니다.": "Claude requests are rate limited. Retrying later.",
        "Claude 주간 잔액 조회 중…": "Loading Claude weekly remaining…",
        "Claude 주간 잔액 표시": "Show Claude weekly remaining",
        "Claude 주간 한도를 조회할 수 없습니다.": "Claude weekly limits are unavailable.",
        "Codex 실행 파일 (선택 사항)": "Codex executable (optional)",
        "Codex 주간 잔액 조회 중…": "Loading Codex weekly remaining…",
        "Codex 주간 잔액 표시": "Show Codex weekly remaining",
        "Codex는 1분, Claude는 5분마다 갱신합니다. 각 서비스의 CLI에 로그인해야 합니다.": "Codex refreshes every minute; Claude every 5 minutes. Sign in to each service’s CLI.",
        "OFF - Sunshine 실행 여부와 무관": "OFF — independent of the Sunshine service",
        "OFF - 닫힘 처리 안 함": "OFF — no lid-close actions",
        "OFF - 잠자기 방지 꺼짐": "OFF — normal sleep behavior",
        "ON - Sunshine 대응 + 화면/키보드/음량 최소화": "ON — streaming mode, dimming & mute",
        "ON - 닫히면 화면/키보드/음량 최소화": "ON — dim & mute when the lid closes",
        "ON - 앱/덮개 닫힘 모두 방지": "ON — prevents idle and lid sleep",
        "ON - 잠자기 방지를 켜면 적용": "ON — applies while sleep prevention is enabled",
        "ON - 화면 유지, 닫힘 시 내장 화면 최저 밝기": "ON — keeps display awake; dims built-in display on lid close",
        "Sunshine 대응 OFF": "Sunshine OFF",
        "Sunshine 대응 ON": "Sunshine ON",
        "Sunshine 대응 모드": "Sunshine compatibility",
        "Sunshine 대응 모드 변경을 반영했습니다: OFF": "Sunshine compatibility updated: OFF",
        "Sunshine 대응 모드 변경을 반영했습니다: ON": "Sunshine compatibility updated: ON",
        "Sunshine 대응 모드를 껐습니다.": "Sunshine compatibility disabled.",
        "Sunshine 대응 모드를 켰습니다.": "Sunshine compatibility enabled.",
        "Sunshine 화면 유지 assertion 생성 실패: %@": "Could not create streaming display assertion: %@",
        "pmset 상태를 읽지 못했습니다.": "Could not read pmset status.",
        "관리자 인증을 기다리는 중...": "Waiting for administrator authentication…",
        "기존 잠자기 방지 상태를 앱과 동기화했습니다.": "Synced existing sleep prevention settings.",
        "닫힘 시 화면/키보드/음량 끄기": "Dim display, keyboard & mute on lid close",
        "닫힘 시 화면/키보드/음량 끄기를 껐습니다.": "Lid-close dimming and mute disabled.",
        "닫힘 시 화면/키보드/음량 끄기를 켰습니다.": "Lid-close dimming and mute enabled.",
        "덮개 닫힘": "Lid closed",
        "덮개 닫힘을 감지했습니다.": "Lid close detected.",
        "덮개 열림": "Lid open",
        "덮개 열림을 감지했습니다.": "Lid open detected.",
        "로그인 시 자동 실행": "Launch at login",
        "비워 두면 자동으로 찾습니다": "Leave empty to detect automatically",
        "비활성 - 잠자기 방지 권한 설정 필요": "Disabled — sleep prevention needs authorization",
        "비활성 - 잠자기 방지를 먼저 켜세요": "Disabled — enable sleep prevention first",
        "사용량 조회 실패 — Codex 로그인과 네트워크를 확인하세요.": "Could not load usage. Check Codex login and your network.",
        "상태 새로고침": "Refresh status",
        "설정": "Settings",
        "설정…": "Settings…",
        "설정을 변경하지 못했습니다.": "Could not change the setting.",
        "시스템 언어": "System language",
        "실행 가능한 Codex 파일의 절대 경로를 선택하세요.": "Choose an absolute path to an executable Codex file.",
        "언어": "Language",
        "일부 ON - 덮개 차단만 켜짐": "Partly ON — only system sleep disabled",
        "일부 ON - 앱 idle sleep만 방지": "Partly ON — only idle sleep prevented",
        "자동 실행 설정을 저장하지 못했습니다.": "Could not save the launch-at-login setting.",
        "잠자기 방지": "Prevent sleep",
        "잠자기 방지 OFF": "Sleep prevention OFF",
        "잠자기 방지 ON": "Sleep prevention ON",
        "잠자기 방지 assertion 생성 실패: %@": "Could not create sleep assertion: %@",
        "잠자기 방지 assertion 해제 실패: system=%@, display=%@": "Could not release sleep assertions: system=%@, display=%@",
        "잠자기 방지 일부 ON": "Sleep prevention partly ON",
        "잠자기 방지가 복원되었습니다.": "Sleep prevention restored.",
        "잠자기 방지를 껐습니다.": "Sleep prevention disabled.",
        "잠자기 방지를 끄는 중...": "Disabling sleep prevention…",
        "잠자기 방지를 켜는 중...": "Enabling sleep prevention…",
        "잠자기 방지를 켰습니다.": "Sleep prevention enabled.",
        "적용": "Apply",
        "종료": "Quit",
        "찾아보기…": "Browse…",
        "화면 스트리밍 assertion 해제 실패: %@": "Could not release display streaming assertion: %@",
        "확인": "OK",
    ]
    static func text(_ key: String, language: String, values: [String] = []) -> String {
        var text = language == "ko" ? key : (english[key] ?? key)
        for value in values {
            if let range = text.range(of: "%@") { text.replaceSubrange(range, with: value) }
        }
        return text
    }
}

func L(_ key: String, _ values: String...) -> String {
    Localization.text(key, language: Localization.language, values: values)
}
