import AppKit

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var languagePopup = NSPopUpButton()
    private var codexCheck = NSButton()
    private var claudeCheck = NSButton()
    private var loginCheck = NSButton()
    private var executableField = NSTextField()
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
            rebuildContent()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }

    private func rebuildContent() {
        guard let window else { return }
        window.title = "NoSleepMenu — " + L("설정")
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 420))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        let languageLabel = NSTextField(labelWithString: L("언어"))
        languageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: [L("시스템 언어"), "한국어", "English"])
        languagePopup.selectItem(at: ["system", "ko", "en"].firstIndex(of: AppSettings.language) ?? 0)
        let languageRow = NSStackView(views: [languageLabel, languagePopup])
        languageRow.spacing = 20
        stack.addArrangedSubview(languageRow)

        codexCheck = NSButton(checkboxWithTitle: L("Codex 주간 잔액 표시"), target: nil, action: nil)
        codexCheck.state = AppSettings.codexEnabled ? .on : .off
        claudeCheck = NSButton(checkboxWithTitle: L("Claude 주간 잔액 표시"), target: nil, action: nil)
        claudeCheck.state = AppSettings.claudeEnabled ? .on : .off
        loginCheck = NSButton(checkboxWithTitle: L("로그인 시 자동 실행"), target: nil, action: nil)
        loginCheck.state = LoginItemManager.isEnabled ? .on : .off
        for check in [codexCheck, claudeCheck, loginCheck] { stack.addArrangedSubview(check) }

        let pathLabel = NSTextField(labelWithString: L("Codex 실행 파일 (선택 사항)"))
        pathLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(pathLabel)
        executableField = NSTextField(string: AppSettings.codexExecutablePath)
        executableField.placeholderString = L("비워 두면 자동으로 찾습니다")
        executableField.setAccessibilityLabel(L("Codex 실행 파일 (선택 사항)"))
        let browse = NSButton(title: L("찾아보기…"), target: self, action: #selector(browseExecutable))
        let pathRow = NSStackView(views: [executableField, browse])
        pathRow.distribution = .fill
        pathRow.spacing = 8
        stack.addArrangedSubview(pathRow)
        pathRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        executableField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let note = NSTextField(wrappingLabelWithString: L("Codex는 1분, Claude는 5분마다 갱신합니다. 각 서비스의 CLI에 로그인해야 합니다."))
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let apply = NSButton(title: L("적용"), target: self, action: #selector(apply))
        apply.keyEquivalent = "\r"
        stack.addArrangedSubview(apply)
        window.contentView = content
    }

    @objc private func browseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L("Codex 실행 파일 (선택 사항)")
        if panel.runModal() == .OK, let url = panel.url { executableField.stringValue = url.path }
    }

    @objc private func apply() {
        let path = executableField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty && (!path.hasPrefix("/") || !FileManager.default.isExecutableFile(atPath: path)) {
            showError(L("실행 가능한 Codex 파일의 절대 경로를 선택하세요.")); return
        }
        do {
            if (loginCheck.state == .on) != LoginItemManager.isEnabled { try LoginItemManager.setEnabled(loginCheck.state == .on) }
        } catch { showError(L("자동 실행 설정을 저장하지 못했습니다.") + "\n" + error.localizedDescription); return }
        AppSettings.language = ["system", "ko", "en"][max(0, languagePopup.indexOfSelectedItem)]
        AppSettings.codexEnabled = codexCheck.state == .on
        AppSettings.claudeEnabled = claudeCheck.state == .on
        AppSettings.codexExecutablePath = path
        onChange()
        rebuildContent()
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: L("확인"))
        alert.runModal()
    }
}
