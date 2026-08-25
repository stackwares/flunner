import Foundation

enum PreferenceKeys {
    static let themeMode = "themeMode"
    static let appFontSize = "appFontSize"
    static let consoleFontSize = "fontSize"
    static let showTimestamps = "showTimestamps"
    static let followOutput = "followOutput"
    static let mcpEnabled = "mcpEnabled"
}

enum AppFontSizing {
    static let defaultSize = 13.0
    static let minimumSize = 11.0
    static let maximumSize = 18.0
    static let step = 1.0

    static func clamped(_ size: Double) -> Double {
        min(max(size, minimumSize), maximumSize)
    }

    static func increased(_ size: Double) -> Double {
        clamped(size + step)
    }

    static func decreased(_ size: Double) -> Double {
        clamped(size - step)
    }
}

@MainActor
class UserDefaultsStore {
    static let shared = UserDefaultsStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastProjectPath = "lastProjectPath"
        static let lastDeviceId = "lastDeviceId"
        static let lastLaunchConfigName = "lastLaunchConfigName"
        static let fontSize = "fontSize"
        static let themeMode = PreferenceKeys.themeMode
    }

    var themeMode: String {
        get { defaults.string(forKey: Keys.themeMode) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.themeMode) }
    }

    var lastProjectPath: String? {
        get { defaults.string(forKey: Keys.lastProjectPath) }
        set { defaults.set(newValue, forKey: Keys.lastProjectPath) }
    }

    var lastDeviceId: String? {
        get { defaults.string(forKey: Keys.lastDeviceId) }
        set { defaults.set(newValue, forKey: Keys.lastDeviceId) }
    }

    var lastLaunchConfigName: String? {
        get { defaults.string(forKey: Keys.lastLaunchConfigName) }
        set { defaults.set(newValue, forKey: Keys.lastLaunchConfigName) }
    }

    var fontSize: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.fontSize)
            return value > 0 ? value : 12
        }
        set { defaults.set(Double(newValue), forKey: Keys.fontSize) }
    }

    var showTimestamps: Bool {
        get { defaults.object(forKey: PreferenceKeys.showTimestamps) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKeys.showTimestamps) }
    }

    var followOutput: Bool {
        get { defaults.object(forKey: PreferenceKeys.followOutput) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKeys.followOutput) }
    }

    var mcpEnabled: Bool {
        get { defaults.object(forKey: PreferenceKeys.mcpEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKeys.mcpEnabled) }
    }
}
