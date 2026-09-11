import AppKit

struct AppIdentity {
    static let bundleID = "io.github.nosleepmenu.NoSleepMenu"
    static let preferencesDomain = bundleID
    static let version = "1.0.0"
}

struct AppSettings {
    static func preferences(for bundleIdentifier: String?) -> UserDefaults {
        // macOS rejects constructing a suite with the running app's own bundle ID.
        if bundleIdentifier == AppIdentity.preferencesDomain { return .standard }
        return UserDefaults(suiteName: AppIdentity.preferencesDomain) ?? .standard
    }
    static var defaults: UserDefaults { preferences(for: Bundle.main.bundleIdentifier) }
    static var language: String {
        get { defaults.string(forKey: "language") ?? "system" }
        set { defaults.set(newValue, forKey: "language") }
    }
    static var codexEnabled: Bool {
        get { defaults.object(forKey: "showCodex") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCodex") }
    }
    static var claudeEnabled: Bool {
        get { defaults.object(forKey: "showClaude") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showClaude") }
    }
    static var codexExecutablePath: String {
        get { defaults.string(forKey: "codexExecutablePath") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "codexExecutablePath") }
    }
    static func migrateLegacyPreferences() {
        guard !defaults.bool(forKey: "legacyPreferencesChecked") else { return }
        if let legacy = UserDefaults(suiteName: "local.formac.nosleepmenu") {
            for key in ["sleepPreventionEnabled", "sunshineResponseModeEnabled", "lidBrightnessManagementEnabled", "savedBuiltInDisplayBrightness", "savedKeyboardBrightness", "lastOpenKeyboardBrightness", "savedSystemOutputVolume"] {
                if defaults.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: "legacyPreferencesChecked")
    }
}

/// Generated on the current Mac; never ships an author's absolute path.
struct LoginItemManager {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/" + AppIdentity.bundleID + ".plist")
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: url.path) }
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard Bundle.main.bundleURL.pathExtension == "app" else { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "Label": AppIdentity.bundleID,
                "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
                "RunAtLoad": true
            ], format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: url)
        }
    }
}
