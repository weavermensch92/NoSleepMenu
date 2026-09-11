import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt
import NoSleepMenuSupport

private let sleepPreferenceKey = "sleepPreventionEnabled"
private let lidBrightnessPreferenceKey = "lidBrightnessManagementEnabled"
private let sunshineResponseModePreferenceKey = "sunshineResponseModeEnabled"
private let savedBuiltInDisplayBrightnessKey = "savedBuiltInDisplayBrightness"
private let savedKeyboardBrightnessKey = "savedKeyboardBrightness"
private let lastOpenKeyboardBrightnessKey = "lastOpenKeyboardBrightness"
private let savedSystemOutputVolumeKey = "savedSystemOutputVolume"
private let preferencesChangedNotificationName = "io.github.nosleepmenu.preferences-changed"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let defaults = AppSettings.defaults
    private let sleepController = SleepAssertionController()
    private let systemSleepService = SystemSleepService()
    private let lidMonitor = LidMonitor()
    private lazy var lidBrightnessController = LidBrightnessController(defaults: defaults)

    private let sleepToggleRow = ToggleMenuRow(title: L("잠자기 방지"))
    private let sunshineToggleRow = ToggleMenuRow(title: L("Sunshine 대응 모드"))
    private let lidBrightnessToggleRow = ToggleMenuRow(title: L("닫힘 시 화면/키보드/음량 끄기"))

    private lazy var sleepToggleMenuItem = NSMenuItem()
    private lazy var sunshineToggleMenuItem = NSMenuItem()
    private lazy var lidBrightnessMenuItem = NSMenuItem()
    private lazy var stateMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var refreshMenuItem = NSMenuItem(
        title: L("상태 새로고침"),
        action: #selector(refreshFromMenu),
        keyEquivalent: "r"
    )
    private lazy var messageMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private var isSystemSleepDisabled = false
    private var isSunshineModeEnabled = false
    private var isLidClosed = false
    private var isBusy = false
    private var lastMessage: String?
    private var lidTimer: Timer?
    private var systemStatusTimer: Timer?
    private var claudeUsageTimer: Timer?
    private var isRefreshingClaudeUsage = false
    private var claudeWeeklyUsage: WeeklyUsage?
    private var claudeUsageError: String?
    private lazy var claudeUsageMenuItem = NSMenuItem(title: L("Claude 주간 잔액 조회 중…"), action: nil, keyEquivalent: "")
    private var claudeLogo: NSImage? { VendorAssets.logo(.claude) }
    private var usageTimer: Timer?
    private var isRefreshingUsage = false
    private var weeklyUsage: WeeklyUsage?
    private var usageError: String?
    private lazy var usageMenuItem = NSMenuItem(title: L("Codex 주간 잔액 조회 중…"), action: nil, keyEquivalent: "")
    private var chatGPTLogo: NSImage? { VendorAssets.logo(.codex) }
    private var preferencesObserver: DarwinNotificationObserver?

    private var isSleepPreventionEnabled: Bool {
        sleepController.isEnabled
    }

    private var isSleepPreventionActive: Bool {
        isSleepPreventionEnabled || isSystemSleepDisabled
    }

    private var isFullSleepPreventionEnabled: Bool {
        isSleepPreventionEnabled && isSystemSleepDisabled
    }

    private var canManageClosedLidBrightness: Bool {
        isSleepPreventionEnabled && isSystemSleepDisabled
    }

    private var isLidBrightnessManagementEnabled: Bool {
        get {
            if defaults.object(forKey: lidBrightnessPreferenceKey) == nil {
                return true
            }

            return defaults.bool(forKey: lidBrightnessPreferenceKey)
        }
        set {
            defaults.set(newValue, forKey: lidBrightnessPreferenceKey)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSettings.migrateLegacyPreferences()
        configureStatusItem()
        configureMenu()
        refreshWeeklyUsage()
        refreshClaudeUsage()
        claudeUsageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshClaudeUsage() }
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshWeeklyUsage() }
        }
        startPreferencesObserver()
        restoreSavedSleepPreference()
        refreshSystemSleepStatus()
        refreshSunshineModePreference()
        startLidPolling()
        startSystemStatusPolling()
        updateUI()
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        claudeUsageTimer?.invalidate()
        usageTimer?.invalidate()
        preferencesObserver = nil
        lidBrightnessController.restoreAfterOpen()
        sleepController.setEnabled(false)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.toolTip = L("잠자기 방지")
        button.imagePosition = .imageRight
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        updateStatusButton()
    }

    private func configureMenu() {
        usageMenuItem.isEnabled = false
        menu.addItem(usageMenuItem)
        claudeUsageMenuItem.isEnabled = false
        menu.addItem(claudeUsageMenuItem)
        menu.addItem(.separator())
        sleepToggleMenuItem.view = sleepToggleRow
        menu.addItem(sleepToggleMenuItem)

        sunshineToggleMenuItem.view = sunshineToggleRow
        menu.addItem(sunshineToggleMenuItem)

        lidBrightnessMenuItem.view = lidBrightnessToggleRow
        menu.addItem(lidBrightnessMenuItem)

        menu.addItem(.separator())

        stateMenuItem.isEnabled = false
        menu.addItem(stateMenuItem)

        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)

        menu.addItem(.separator())

        messageMenuItem.isEnabled = false
        messageMenuItem.isHidden = true
        menu.addItem(messageMenuItem)

        let settingsItem = NSMenuItem(title: L("설정…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitMenuItem = NSMenuItem(title: L("종료"), action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        sleepToggleRow.onToggle = { [weak self] isOn in
            Task { @MainActor in
                self?.setSleepPrevention(isOn)
            }
        }

        sunshineToggleRow.onToggle = { [weak self] isOn in
            Task { @MainActor in
                self?.setSunshineMode(isOn)
            }
        }

        lidBrightnessToggleRow.onToggle = { [weak self] isOn in
            Task { @MainActor in
                self?.setLidBrightnessManagement(isOn)
            }
        }

        statusItem.menu = menu
    }

    private func restoreSavedSleepPreference() {
        guard defaults.bool(forKey: sleepPreferenceKey) else {
            return
        }

        isSystemSleepDisabled = true

        switch sleepController.setEnabled(true) {
        case .success:
            lastMessage = L("잠자기 방지가 복원되었습니다.")
            syncStreamingAssertion()
        case .failure(let error):
            isSystemSleepDisabled = false
            lastMessage = error.localizedDescription
        }
    }

    private func setSleepPrevention(_ enabled: Bool) {
        guard !isBusy else {
            updateUI()
            return
        }

        if enabled {
            enableSleepPrevention()
        } else {
            disableSleepPrevention()
        }
    }

    private func enableSleepPrevention() {
        isBusy = true
        lastMessage = isSystemSleepDisabled ? L("잠자기 방지를 켜는 중...") : L("관리자 인증을 기다리는 중...")
        updateUI()

        switch sleepController.setEnabled(true) {
        case .success:
            break
        case .failure(let error):
            isBusy = false
            lastMessage = error.localizedDescription
            updateUI()
            return
        }

        guard !isSystemSleepDisabled else {
            isBusy = false
            defaults.set(true, forKey: sleepPreferenceKey)
            lastMessage = L("잠자기 방지를 켰습니다.")
            syncStreamingAssertion()
            updateBrightnessForCurrentLidState()
            updateUI()
            return
        }

        setSystemSleepDisabled(true, keepEnabledOnFailure: false)
    }

    private func disableSleepPrevention() {
        isBusy = true
        lastMessage = isSystemSleepDisabled ? L("관리자 인증을 기다리는 중...") : L("잠자기 방지를 끄는 중...")
        updateUI()

        guard isSystemSleepDisabled else {
            sleepController.setEnabled(false)
            defaults.set(false, forKey: sleepPreferenceKey)
            isBusy = false
            lastMessage = L("잠자기 방지를 껐습니다.")
            syncStreamingAssertion()
            updateBrightnessForCurrentLidState()
            updateUI()
            return
        }

        setSystemSleepDisabled(false, keepEnabledOnFailure: true)
    }

    private func setLidBrightnessManagement(_ enabled: Bool) {
        isLidBrightnessManagementEnabled = enabled

        if enabled {
            lastMessage = L("닫힘 시 화면/키보드/음량 끄기를 켰습니다.")
        } else {
            lidBrightnessController.restoreAfterOpen()
            lastMessage = L("닫힘 시 화면/키보드/음량 끄기를 껐습니다.")
        }

        updateBrightnessForCurrentLidState()
        updateUI()
    }

    private func setSystemSleepDisabled(_ enabled: Bool, keepEnabledOnFailure: Bool) {
        let service = systemSleepService
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                service.setSystemSleepDisabled(enabled)
            }.value

            isBusy = false

            switch result {
            case .success:
                isSystemSleepDisabled = enabled

                if enabled {
                    defaults.set(true, forKey: sleepPreferenceKey)
                    lastMessage = L("잠자기 방지를 켰습니다.")
                    syncStreamingAssertion()
                } else {
                    sleepController.setEnabled(false)
                    defaults.set(false, forKey: sleepPreferenceKey)
                    lastMessage = L("잠자기 방지를 껐습니다.")
                    syncStreamingAssertion()
                }
            case .failure(let error):
                lastMessage = error.localizedDescription

                if keepEnabledOnFailure {
                    _ = sleepController.setEnabled(true)
                    defaults.set(true, forKey: sleepPreferenceKey)
                } else {
                    sleepController.setEnabled(false)
                    defaults.set(false, forKey: sleepPreferenceKey)
                }

                syncStreamingAssertion()
            }

            refreshSystemSleepStatus()
        }
    }

    private func setSunshineMode(_ enabled: Bool) {
        guard !isBusy else {
            updateUI()
            return
        }

        isSunshineModeEnabled = enabled
        defaults.set(enabled, forKey: sunshineResponseModePreferenceKey)
        defaults.synchronize()
        lastMessage = enabled ? L("Sunshine 대응 모드를 켰습니다.") : L("Sunshine 대응 모드를 껐습니다.")
        syncStreamingAssertion()
        updateBrightnessForCurrentLidState()
        updateUI()
    }

    @objc private func refreshFromMenu() {
        refreshWeeklyUsage()
        refreshClaudeUsage()
        refreshSystemSleepStatus()
        refreshSunshineModePreference(showMessage: true)
        pollLidState()
    }

    private func refreshSystemSleepStatus() {
        let service = systemSleepService

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                service.currentSystemSleepDisabled()
            }.value

            switch result {
            case .success(let disabled):
                isSystemSleepDisabled = disabled
                syncAppAssertionWithSystemIfNeeded()
            case .failure(let error):
                lastMessage = error.localizedDescription
            }

            updateBrightnessForCurrentLidState()
            updateUI()
        }
    }

    private func refreshSunshineModePreference(showMessage: Bool = false) {
        syncSunshineModePreferenceFromDefaults(showMessage: showMessage)
        syncStreamingAssertion()
        updateBrightnessForCurrentLidState(readLatestPreference: false)
        updateUI()
    }

    @discardableResult
    private func syncSunshineModePreferenceFromDefaults(showMessage: Bool = false) -> Bool {
        defaults.synchronize()
        let enabled = defaults.bool(forKey: sunshineResponseModePreferenceKey)
        let changed = enabled != isSunshineModeEnabled
        isSunshineModeEnabled = enabled

        if changed && showMessage {
            lastMessage = enabled
                ? L("Sunshine 대응 모드 변경을 반영했습니다: ON")
                : L("Sunshine 대응 모드 변경을 반영했습니다: OFF")
        }

        return changed
    }

    private func startLidPolling() {
        lidTimer?.invalidate()
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollLidState()
            }
        }

        pollLidState()
    }

    private func startSystemStatusPolling() {
        systemStatusTimer?.invalidate()
        systemStatusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSystemSleepStatus()
                self?.refreshSunshineModePreference()
            }
        }
    }

    private func startPreferencesObserver() {
        preferencesObserver = DarwinNotificationObserver(name: preferencesChangedNotificationName) { [weak self] in
            Task { @MainActor in
                self?.refreshSunshineModePreference(showMessage: true)
            }
        }
    }

    private func syncAppAssertionWithSystemIfNeeded() {
        guard isSystemSleepDisabled, !isSleepPreventionEnabled else {
            return
        }

        switch sleepController.setEnabled(true) {
        case .success:
            defaults.set(true, forKey: sleepPreferenceKey)
            syncStreamingAssertion()
            if lastMessage == nil {
                lastMessage = L("기존 잠자기 방지 상태를 앱과 동기화했습니다.")
            }
        case .failure(let error):
            lastMessage = error.localizedDescription
        }
    }

    private func pollLidState() {
        if syncSunshineModePreferenceFromDefaults() {
            syncStreamingAssertion()
        }

        guard let closed = lidMonitor.isClosed() else {
            return
        }

        let changed = closed != isLidClosed
        isLidClosed = closed

        if changed {
            lastMessage = closed ? L("덮개 닫힘을 감지했습니다.") : L("덮개 열림을 감지했습니다.")
        }

        updateBrightnessForCurrentLidState(readLatestPreference: false)
        updateUI()
    }

    private func updateBrightnessForCurrentLidState(readLatestPreference: Bool = true) {
        if readLatestPreference, syncSunshineModePreferenceFromDefaults() {
            syncStreamingAssertion()
        }

        let externalDisplayConnected = lidBrightnessController.isExternalDisplayConnected()
        let shouldApplyManagedLidDimming = isLidBrightnessManagementEnabled && canManageClosedLidBrightness
        let shouldApplySunshineLidDimming = isSunshineModeEnabled && canManageClosedLidBrightness
        let shouldApplyExternalDisplayPriority = externalDisplayConnected && canManageClosedLidBrightness
        let shouldDimBuiltInDisplay = isLidClosed && (
            shouldApplyManagedLidDimming || shouldApplySunshineLidDimming || shouldApplyExternalDisplayPriority
        )
        let shouldDimKeyboard = isLidClosed && shouldApplyManagedLidDimming
        let shouldManageAudio = isLidClosed && shouldApplyManagedLidDimming

        if shouldDimBuiltInDisplay || shouldDimKeyboard || shouldManageAudio {
            lidBrightnessController.applyClosedLidState(
                dimBuiltInDisplay: shouldDimBuiltInDisplay,
                dimKeyboard: shouldDimKeyboard,
                manageAudio: shouldManageAudio,
                externalOnly: isLidClosed && externalDisplayConnected
            )
        } else {
            lidBrightnessController.restoreAfterOpen()
            if !isLidClosed {
                lidBrightnessController.rememberOpenLidBrightness()
            }
        }
    }

    private func syncStreamingAssertion() {
        let shouldKeepDisplayAwake = isSunshineModeEnabled && canManageClosedLidBrightness
        let result = sleepController.setDisplayStreamingEnabled(shouldKeepDisplayAwake)

        if case .failure(let error) = result {
            lastMessage = error.localizedDescription
        }
    }

    private func updateUI() {
        sleepToggleRow.setOn(isSleepPreventionActive)
        sleepToggleRow.setEnabled(!isBusy)
        sleepToggleRow.setDetail(sleepPreventionDetailText())

        sunshineToggleRow.setOn(isSunshineModeEnabled)
        sunshineToggleRow.setEnabled(!isBusy)
        sunshineToggleRow.setDetail(sunshineModeDetailText())

        let lidControlEnabled = !isBusy && canManageClosedLidBrightness
        lidBrightnessToggleRow.setOn(lidControlEnabled && isLidBrightnessManagementEnabled)
        lidBrightnessToggleRow.setEnabled(lidControlEnabled)
        lidBrightnessToggleRow.setDetail(lidBrightnessDetailText())

        let sleepState = isFullSleepPreventionEnabled
            ? L("잠자기 방지 ON")
            : (isSleepPreventionActive ? L("잠자기 방지 일부 ON") : L("잠자기 방지 OFF"))
        let sunshineState = isSunshineModeEnabled ? L("Sunshine 대응 ON") : L("Sunshine 대응 OFF")
        let lidState = isLidClosed ? L("덮개 닫힘") : L("덮개 열림")
        stateMenuItem.title = [sleepState, sunshineState, lidState].joined(separator: " · ")

        refreshMenuItem.isEnabled = !isBusy

        if let lastMessage {
            messageMenuItem.title = lastMessage
            messageMenuItem.isHidden = false
        } else {
            messageMenuItem.isHidden = true
        }

        updateStatusButton()
    }

    private func sleepPreventionDetailText() -> String {
        if isSleepPreventionEnabled && isSystemSleepDisabled {
            return L("ON - 앱/덮개 닫힘 모두 방지")
        }

        if isSystemSleepDisabled {
            return L("일부 ON - 덮개 차단만 켜짐")
        }

        if isSleepPreventionEnabled {
            return L("일부 ON - 앱 idle sleep만 방지")
        }

        return L("OFF - 잠자기 방지 꺼짐")
    }

    private func lidBrightnessDetailText() -> String {
        if !isSleepPreventionEnabled {
            return L("비활성 - 잠자기 방지를 먼저 켜세요")
        }

        if !isSystemSleepDisabled {
            return L("비활성 - 잠자기 방지 권한 설정 필요")
        }

        return isLidBrightnessManagementEnabled
            ? (isSunshineModeEnabled
                ? L("ON - Sunshine 대응 + 화면/키보드/음량 최소화")
                : L("ON - 닫히면 화면/키보드/음량 최소화"))
            : L("OFF - 닫힘 처리 안 함")
    }

    private func sunshineModeDetailText() -> String {
        if isSunshineModeEnabled {
            return canManageClosedLidBrightness
                ? L("ON - 화면 유지, 닫힘 시 내장 화면 최저 밝기")
                : L("ON - 잠자기 방지를 켜면 적용")
        }

        return L("OFF - Sunshine 실행 여부와 무관")
    }

    private func refreshWeeklyUsage() {
        guard AppSettings.codexEnabled, !isRefreshingUsage else { return }
        isRefreshingUsage = true
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try CodexWeeklyUsageReader.fetch(executablePath: AppSettings.codexExecutablePath) }
            }.value
            isRefreshingUsage = false
            switch result {
            case .success(let value):
                weeklyUsage = value
                usageError = nil
            case .failure:
                weeklyUsage = nil
                usageError = L("사용량 조회 실패 — Codex 로그인과 네트워크를 확인하세요.")
            }
            updateStatusButton()
        }
    }

    private func refreshClaudeUsage() {
        guard AppSettings.claudeEnabled, !isRefreshingClaudeUsage else { return }
        isRefreshingClaudeUsage = true
        Task {
            do {
                claudeWeeklyUsage = try await ClaudeWeeklyUsageReader.fetch()
                claudeUsageError = nil
            } catch {
                claudeWeeklyUsage = nil
                claudeUsageError = (error as? ClaudeUsageError)?.message ?? L("Claude 사용량 조회 실패 — 네트워크를 확인하세요.")
            }
            isRefreshingClaudeUsage = false
            updateStatusButton()
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let codex = weeklyUsage.flatMap { $0.resetsAt > Date() ? $0 : nil }
        let claude = claudeWeeklyUsage.flatMap { $0.resetsAt > Date() ? $0 : nil }
        usageMenuItem.title = usageDescription("Codex", usage: codex, error: usageError)
        claudeUsageMenuItem.title = usageDescription("Claude", usage: claude, error: claudeUsageError)
        usageMenuItem.isHidden = !AppSettings.codexEnabled
        claudeUsageMenuItem.isHidden = !AppSettings.claudeEnabled
        var parts: [StatusPart] = []
        if AppSettings.codexEnabled { parts.append(StatusPart(text: codex.map { "\($0.remainingPercent)%" } ?? "—%", logo: chatGPTLogo, fallback: "Codex")) }
        if AppSettings.claudeEnabled { parts.append(StatusPart(text: claude.map { "\($0.remainingPercent)%" } ?? "—%", logo: claudeLogo, fallback: "Claude")) }
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = StatusImage.render(parts: parts, sleepEnabled: isSleepPreventionActive)
        let descriptions = [AppSettings.codexEnabled ? usageMenuItem.title : nil,
                            AppSettings.claudeEnabled ? claudeUsageMenuItem.title : nil,
                            L("잠자기 방지") + ": " + (isSleepPreventionActive ? "ON" : "OFF")].compactMap { $0 }
        button.toolTip = descriptions.joined(separator: "\n")
        button.setAccessibilityLabel(descriptions.joined(separator: ", "))
    }

    private func usageDescription(_ name: String, usage: WeeklyUsage?, error: String?) -> String {
        guard let usage else { return error ?? L("%@ 주간 잔액 조회 중…", name) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Localization.language)
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return L("%@ 주간 잔액 %@ · %@ 초기화", name, "\(usage.remainingPercent)%", formatter.string(from: usage.resetsAt))
    }

    private var settingsController: SettingsWindowController?

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController { [weak self] in self?.applySettings() }
        }
        settingsController?.show()
    }

    private func applySettings() {
        // Rebuild localized controls immediately without changing power settings.
        menu.removeAllItems()
        sleepToggleRow.setTitle(L("잠자기 방지"))
        sunshineToggleRow.setTitle(L("Sunshine 대응 모드"))
        lidBrightnessToggleRow.setTitle(L("닫힘 시 화면/키보드/음량 끄기"))
        refreshMenuItem.title = L("상태 새로고침")
        lastMessage = nil
        usageError = nil
        claudeUsageError = nil
        configureMenu()
        updateUI()
        refreshWeeklyUsage()
        refreshClaudeUsage()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class ToggleMenuRow: NSView {
    private let titleLabel: NSTextField
    private let detailLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "OFF")
    private let switchControl = NSSwitch()
    private var isProgrammaticChange = false

    var onToggle: ((Bool) -> Void)?

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 54))

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        stateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        stateLabel.alignment = .right

        switchControl.target = self
        switchControl.action = #selector(switchChanged)

        autoresizingMask = [.width]
        titleLabel.lineBreakMode = .byTruncatingTail
        for view in [titleLabel, detailLabel, stateLabel, switchControl] {
            addSubview(view)
        }
    }

    override func layout() {
        super.layout()
        let switchSize = switchControl.fittingSize
        let switchX = bounds.width - 14 - switchSize.width
        switchControl.frame = NSRect(x: switchX, y: (bounds.height - switchSize.height) / 2,
                                     width: switchSize.width, height: switchSize.height)
        stateLabel.frame = NSRect(x: switchX - 36, y: (bounds.height - 16) / 2, width: 28, height: 16)
        let labelWidth = max(0, switchX - 36 - 14 - 14)
        titleLabel.frame = NSRect(x: 14, y: 28, width: labelWidth, height: 18)
        detailLabel.frame = NSRect(x: 14, y: 10, width: labelWidth, height: 16)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setTitle(_ title: String) { titleLabel.stringValue = title }

    func setOn(_ on: Bool) {
        isProgrammaticChange = true
        switchControl.state = on ? .on : .off
        stateLabel.stringValue = on ? "ON" : "OFF"
        stateLabel.textColor = on ? .systemGreen : .secondaryLabelColor
        isProgrammaticChange = false
    }

    func setEnabled(_ enabled: Bool) {
        switchControl.isEnabled = enabled
        titleLabel.textColor = enabled ? .labelColor : .secondaryLabelColor
        if !enabled {
            stateLabel.textColor = .disabledControlTextColor
        }
    }

    func setDetail(_ detail: String) {
        detailLabel.stringValue = detail
    }

    @objc private func switchChanged() {
        guard !isProgrammaticChange else {
            return
        }

        onToggle?(switchControl.state == .on)
    }
}

final class DarwinNotificationObserver {
    private let name: CFString
    private let callback: () -> Void

    init(name: String, callback: @escaping () -> Void) {
        self.name = name as CFString
        self.callback = callback

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else {
                    return
                }

                let instance = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                instance.callback()
            },
            self.name,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            CFNotificationName(name),
            nil
        )
    }
}

final class SleepAssertionController {
    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0

    var isEnabled: Bool {
        systemAssertionID != 0
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Result<Void, SleepControlError> {
        enabled ? enable() : disable()
    }

    private func enable() -> Result<Void, SleepControlError> {
        if systemAssertionID == 0 {
            var newAssertionID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NoSleepMenu Sleep Prevention" as CFString,
                &newAssertionID
            )

            guard result == kIOReturnSuccess else {
                return .failure(.commandFailed(L("잠자기 방지 assertion 생성 실패: %@", "\(result)")))
            }

            systemAssertionID = newAssertionID
        }

        return .success(())
    }

    private func disable() -> Result<Void, SleepControlError> {
        guard systemAssertionID != 0 || displayAssertionID != 0 else {
            return .success(())
        }

        let systemResult = releaseAssertionIfNeeded(&systemAssertionID)
        let displayResult = releaseAssertionIfNeeded(&displayAssertionID)

        guard systemResult == kIOReturnSuccess, displayResult == kIOReturnSuccess else {
            return .failure(.commandFailed(L("잠자기 방지 assertion 해제 실패: system=%@, display=%@", "\(systemResult)", "\(displayResult)")))
        }

        return .success(())
    }

    @discardableResult
    func setDisplayStreamingEnabled(_ enabled: Bool) -> Result<Void, SleepControlError> {
        if enabled {
            return enableDisplayStreamingIfNeeded()
        }

        let result = releaseAssertionIfNeeded(&displayAssertionID)
        guard result == kIOReturnSuccess else {
            return .failure(.commandFailed(L("화면 스트리밍 assertion 해제 실패: %@", "\(result)")))
        }

        return .success(())
    }

    private func enableDisplayStreamingIfNeeded() -> Result<Void, SleepControlError> {
        guard displayAssertionID == 0 else {
            return .success(())
        }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NoSleepMenu Sunshine Streaming" as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            return .failure(.commandFailed(L("Sunshine 화면 유지 assertion 생성 실패: %@", "\(result)")))
        }

        displayAssertionID = newAssertionID
        return .success(())
    }

    private func releaseAssertionIfNeeded(_ assertionID: inout IOPMAssertionID) -> IOReturn {
        guard assertionID != 0 else {
            return kIOReturnSuccess
        }

        let result = IOPMAssertionRelease(assertionID)
        assertionID = 0
        return result
    }
}

struct SystemSleepService: Sendable {
    private let runner = ProcessRunner()

    func currentSystemSleepDisabled() -> Result<Bool, SleepControlError> {
        let result = runner.run(executable: "/usr/bin/pmset", arguments: ["-g", "live"])

        guard result.exitCode == 0 else {
            return .failure(.commandFailed(result.errorOutput.trimmedOrFallback(L("pmset 상태를 읽지 못했습니다."))))
        }

        let matches = result.standardOutput.matches(for: #"(?m)^\s*SleepDisabled\s+([01])\s*$"#)
        return .success(matches.contains("1"))
    }

    func setSystemSleepDisabled(_ disabled: Bool) -> Result<Void, SleepControlError> {
        let value = disabled ? "1" : "0"
        let script = #"do shell script "/usr/bin/pmset -a disablesleep \#(value)" with administrator privileges"#
        let result = runner.run(executable: "/usr/bin/osascript", arguments: ["-e", script])

        guard result.exitCode == 0 else {
            let message = result.errorOutput.trimmedOrFallback(result.standardOutput.trimmedOrFallback(L("설정을 변경하지 못했습니다.")))
            return .failure(.commandFailed(message))
        }

        return .success(())
    }
}

final class LidMonitor {
    func isClosed() -> Bool? {
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }

        defer {
            IOObjectRelease(service)
        }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return nil
        }

        return value
    }
}

final class LidBrightnessController {
    private let displayService: BuiltInDisplayService
    private let keyboardService: KeyboardBrightnessService
    private let audioService: AudioMediaService
    private var isBuiltInDisplayDimmed = false
    private var isBuiltInDisplayDisabled = false
    private var isKeyboardDimmed = false
    private var isAudioManaged = false

    init(defaults: UserDefaults) {
        displayService = BuiltInDisplayService(defaults: defaults)
        keyboardService = KeyboardBrightnessService(defaults: defaults)
        audioService = AudioMediaService(defaults: defaults)
    }

    func isExternalDisplayConnected() -> Bool {
        displayService.isExternalDisplayConnected()
    }

    func rememberOpenLidBrightness() {
        keyboardService.rememberOpenBrightness()
    }

    func applyClosedLidState(
        dimBuiltInDisplay: Bool,
        dimKeyboard: Bool,
        manageAudio: Bool,
        externalOnly: Bool
    ) {
        if !externalOnly, isBuiltInDisplayDisabled {
            _ = displayService.setBuiltInDisplayEnabled(true)
            isBuiltInDisplayDisabled = false
        }

        if dimBuiltInDisplay, !isBuiltInDisplayDimmed {
            isBuiltInDisplayDimmed = displayService.dimBuiltInDisplayToZero()
        } else if !dimBuiltInDisplay, isBuiltInDisplayDimmed, !isBuiltInDisplayDisabled {
            displayService.restoreBuiltInDisplayBrightness()
            isBuiltInDisplayDimmed = false
        }

        if externalOnly, !isBuiltInDisplayDisabled {
            let disabled = displayService.setBuiltInDisplayEnabled(false)
            isBuiltInDisplayDisabled = disabled
        }

        if dimKeyboard, !isKeyboardDimmed {
            keyboardService.dimToZero()
            isKeyboardDimmed = true
        } else if !dimKeyboard, isKeyboardDimmed {
            keyboardService.restore()
            isKeyboardDimmed = false
        }

        if manageAudio, !isAudioManaged {
            audioService.pausePlaybackAndMinimizeVolume()
            isAudioManaged = true
        } else if !manageAudio, isAudioManaged {
            audioService.restoreVolume()
            isAudioManaged = false
        }
    }

    func restoreAfterOpen() {
        if isBuiltInDisplayDisabled {
            _ = displayService.setBuiltInDisplayEnabled(true)
            isBuiltInDisplayDisabled = false
        }

        displayService.restoreBuiltInDisplayBrightness()
        isBuiltInDisplayDimmed = false

        keyboardService.restore()
        isKeyboardDimmed = false

        audioService.restoreVolume()
        isAudioManaged = false
    }
}

final class BuiltInDisplayService {
    private let defaults: UserDefaults
    private var savedBrightness: Double?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func isExternalDisplayConnected() -> Bool {
        NoSleepExternalDisplayIsConnected()
    }

    func setBuiltInDisplayEnabled(_ enabled: Bool) -> Bool {
        NoSleepBuiltInDisplaySetEnabled(enabled)
    }

    func dimBuiltInDisplayToZero() -> Bool {
        if savedBrightness == nil {
            if let storedBrightness = storedBrightness(forKey: savedBuiltInDisplayBrightnessKey) {
                savedBrightness = storedBrightness
            } else {
                let currentBrightness = NoSleepBuiltInDisplayBrightnessGet()
                if currentBrightness >= 0 {
                    savedBrightness = currentBrightness
                    defaults.set(currentBrightness, forKey: savedBuiltInDisplayBrightnessKey)
                }
            }
        }

        return NoSleepBuiltInDisplayBrightnessSet(0)
    }

    func restoreBuiltInDisplayBrightness() {
        guard let brightness = savedBrightness ?? storedBrightness(forKey: savedBuiltInDisplayBrightnessKey) else {
            return
        }

        _ = NoSleepBuiltInDisplayBrightnessSet(brightness)
        self.savedBrightness = nil
        defaults.removeObject(forKey: savedBuiltInDisplayBrightnessKey)
    }

    private func storedBrightness(forKey key: String) -> Double? {
        guard let value = defaults.object(forKey: key) as? Double, value >= 0 else {
            return nil
        }

        return min(1, value)
    }
}

final class KeyboardBrightnessService {
    private let defaults: UserDefaults
    private var savedBrightness: Double?
    private let visibleBrightnessThreshold = 0.01

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func rememberOpenBrightness() {
        guard savedBrightness == nil,
              defaults.object(forKey: savedKeyboardBrightnessKey) == nil else {
            return
        }

        let currentBrightness = NoSleepKeyboardBrightnessGet()
        guard currentBrightness > visibleBrightnessThreshold else {
            return
        }

        defaults.set(clamp(currentBrightness), forKey: lastOpenKeyboardBrightnessKey)
    }

    func dimToZero() {
        guard savedBrightness == nil else {
            return
        }

        if let storedBrightness = storedBrightness(forKey: savedKeyboardBrightnessKey) {
            savedBrightness = storedBrightness
        } else if let lastOpenBrightness = storedBrightness(forKey: lastOpenKeyboardBrightnessKey) {
            savedBrightness = lastOpenBrightness
            defaults.set(lastOpenBrightness, forKey: savedKeyboardBrightnessKey)
        } else {
            let currentBrightness = NoSleepKeyboardBrightnessGet()
            guard currentBrightness > visibleBrightnessThreshold else {
                _ = NoSleepKeyboardBrightnessSet(0)
                return
            }

            savedBrightness = currentBrightness
            defaults.set(currentBrightness, forKey: savedKeyboardBrightnessKey)
        }

        _ = NoSleepKeyboardBrightnessSet(0)
    }

    func restore() {
        guard let brightness = restoreBrightness() else {
            return
        }

        guard NoSleepKeyboardBrightnessSet(brightness) else {
            return
        }

        self.savedBrightness = nil
        defaults.removeObject(forKey: savedKeyboardBrightnessKey)
        defaults.set(clamp(brightness), forKey: lastOpenKeyboardBrightnessKey)
    }

    private func restoreBrightness() -> Double? {
        let storedSavedBrightness = storedBrightness(forKey: savedKeyboardBrightnessKey)
        let storedOpenBrightness = storedBrightness(forKey: lastOpenKeyboardBrightnessKey)
        let savedCandidate = savedBrightness ?? storedSavedBrightness

        if let savedCandidate, savedCandidate > visibleBrightnessThreshold {
            return savedCandidate
        }

        return storedOpenBrightness ?? savedCandidate
    }

    private func storedBrightness(forKey key: String) -> Double? {
        guard let value = defaults.object(forKey: key) as? Double, value >= 0 else {
            return nil
        }

        return clamp(value)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, value)
    }
}

final class AudioMediaService {
    private let defaults: UserDefaults
    private var savedVolume: Double?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func pausePlaybackAndMinimizeVolume() {
        _ = NoSleepPauseMediaPlayback()
        minimizeVolume()
    }

    func minimizeVolume() {
        if savedVolume == nil {
            if let storedVolume = storedVolume() {
                savedVolume = storedVolume
            } else {
                let currentVolume = NoSleepSystemOutputVolumeGet()
                if currentVolume >= 0 {
                    savedVolume = currentVolume
                    defaults.set(clamp(currentVolume), forKey: savedSystemOutputVolumeKey)
                }
            }
        }

        _ = NoSleepSystemOutputVolumeSet(0)
    }

    func restoreVolume() {
        guard let volume = savedVolume ?? storedVolume() else {
            return
        }

        guard NoSleepSystemOutputVolumeSet(volume) else {
            return
        }

        savedVolume = nil
        defaults.removeObject(forKey: savedSystemOutputVolumeKey)
    }

    private func storedVolume() -> Double? {
        guard let value = defaults.object(forKey: savedSystemOutputVolumeKey) as? Double, value >= 0 else {
            return nil
        }

        return clamp(value)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, value)
    }
}

struct ProcessRunner: Sendable {
    @discardableResult
    func run(executable: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let standardOutput = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = errorOutput

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: -1, standardOutput: "", errorOutput: error.localizedDescription)
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: standardOutput.readString(),
            errorOutput: errorOutput.readString()
        )
    }
}

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let errorOutput: String
}

enum SleepControlError: LocalizedError, Sendable {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

private extension Pipe {
    func readString() -> String {
        let data = fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: self) else {
                return nil
            }

            return String(self[captureRange])
        }
    }

    func trimmedOrFallback(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

@main
enum NoSleepMenuMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            _ = NSApplication.shared
            let language = AppSettings.language
            let image = StatusImage.render(parts: [StatusPart(text: "82%", logo: nil, fallback: "Codex"), StatusPart(text: "99%", logo: nil, fallback: "Claude")], sleepEnabled: false)
            guard image.tiffRepresentation != nil else { exit(1) }
            print("NoSleepMenu bundle self-check passed; language: \(language)")
            return
        }
        if CommandLine.arguments.contains("--check-weekly-usage") {
            do {
                let usage = try CodexWeeklyUsageReader.fetch(executablePath: AppSettings.codexExecutablePath)
                print("Weekly remaining: \(usage.remainingPercent)%; resets: \(usage.resetsAt)")
            } catch {
                fputs("Weekly usage unavailable: \(error)\n", stderr)
                exit(1)
            }
            return
        }
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            return
        }
        let appDelegate = AppDelegate()
        NSApplication.shared.delegate = appDelegate
        withExtendedLifetime(appDelegate) {
            NSApplication.shared.run()
        }
    }
}
