import Foundation
import GestureCore

final class Preferences {
    private let defaults = UserDefaults.standard
    private let settingsKey = "gesture-mac.settings.v1"
    var cameraID: String? {
        get { defaults.string(forKey: "gesture-mac.camera") }
        set { defaults.set(newValue, forKey: "gesture-mac.camera") }
    }
    var displayID: UInt32? {
        get {
            guard defaults.object(forKey: "gesture-mac.display") != nil else { return nil }
            return UInt32(clamping: defaults.integer(forKey: "gesture-mac.display"))
        }
        set { defaults.set(newValue.map { Int($0) }, forKey: "gesture-mac.display") }
    }
    func load() -> Settings {
        guard let data = defaults.data(forKey: settingsKey),
              var settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        settings.sanitize()
        return settings
    }
    func save(_ settings: Settings) {
        var settings = settings; settings.sanitize()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }
}
