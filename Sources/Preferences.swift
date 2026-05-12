import Foundation
import AppKit

// MARK: - Types

enum MetricMode: String, Codable {
    case hidden, text, donut
}

enum IconType: String, Codable {
    case emoji, custom, donut, none
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("local.claude-usage-widget.preferencesChanged")
    static let snapshotChanged    = Notification.Name("local.claude-usage-widget.snapshotChanged")
}

// MARK: - Preferences

struct Preferences: Codable {
    // §01 Title content — per-metric display modes
    var weeklyPctMode:    MetricMode = .text
    var weeklyTimeMode:   MetricMode = .text
    var fiveHourPctMode:  MetricMode = .hidden
    var fiveHourTimeMode: MetricMode = .hidden

    // §01 Donut colors (hex)
    var weeklyPctColor:    String = "#d68c45"  // ember
    var weeklyTimeColor:   String = "#d68c45"
    var fiveHourPctColor:  String = "#5dc97f"  // grass
    var fiveHourTimeColor: String = "#5dc97f"

    // §02 Icon
    var iconType:  IconType = .emoji
    var iconValue: String   = "🤖"

    // §06 Refresh
    var pollIntervalSec: Int = 60

    // §05 Notifications
    var notificationsEnabled: Bool = false
    var warnThreshold:     Int = 50
    var alertThreshold:    Int = 75
    var criticalThreshold: Int = 90
    var lastNotifiedLevel: String = ""   // "" | "warn" | "alert" | "critical"

    // §07 Global hotkey  (modifiers bitmask = cmd 256, opt 2048, ctrl 4096, shift 512 in Carbon)
    var hotkeyEnabled:   Bool   = false
    var hotkeyKeyCode:   UInt32 = 32     // 'U' in Carbon keyCode
    var hotkeyModifiers: UInt32 = 256 + 2048  // ⌘⌥

    // §08 Browsers
    var browserChromeEnabled: Bool = true
    var browserBraveEnabled:  Bool = false
    var browserEdgeEnabled:   Bool = false
    var browserArcEnabled:    Bool = false

    // §09 Version check
    var versionCheckEnabled:    Bool   = true
    var latestKnownVersion:     String = ""
    var lastVersionCheckEpoch:  TimeInterval = 0
}

// MARK: - Store

final class PrefsStore {
    static let shared = PrefsStore()
    private let key = "prefs.v1"
    private(set) var prefs: Preferences = .init()

    private init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else { return }
        prefs = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Mutate prefs, persist, notify observers.
    func update(_ mutator: (inout Preferences) -> Void) {
        mutator(&prefs)
        save()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
}

// MARK: - Hex color helper

extension NSColor {
    /// Parses "#rrggbb" or "rrggbb".
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xff) / 255
        let g = CGFloat((value >> 8)  & 0xff) / 255
        let b = CGFloat( value        & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
