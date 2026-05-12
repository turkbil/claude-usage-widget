import AppKit
import UserNotifications

/// Manages three-level threshold notifications (warn / alert / critical).
/// Uses edge-triggered firing — each level fires at most once until the
/// percentage drops below it again (e.g. after weekly reset).
final class NotificationManager {

    static let shared = NotificationManager()
    private var hasRequestedAuth = false

    private init() {}

    /// Lazy permission request, only when the user enables the feature.
    func ensureAuthorized() {
        guard !hasRequestedAuth else { return }
        hasRequestedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Inspect the latest snapshot and fire a notification if a threshold was crossed.
    func evaluate(snapshot: UsageSnapshot) {
        var prefs = PrefsStore.shared.prefs
        guard prefs.notificationsEnabled else { return }

        let pct = Int(snapshot.weeklyUtilization.rounded())
        let crossed = level(for: pct, prefs: prefs)

        // Reset state once we drop below warn — allows re-firing after reset.
        if pct < prefs.warnThreshold && !prefs.lastNotifiedLevel.isEmpty {
            PrefsStore.shared.update { $0.lastNotifiedLevel = "" }
            return
        }

        // No new level reached, or already notified about this or a higher level.
        guard let newLevel = crossed,
              isHigher(newLevel, than: prefs.lastNotifiedLevel) else { return }

        ensureAuthorized()
        post(level: newLevel, percent: pct, prefs: prefs)
        prefs.lastNotifiedLevel = newLevel
        PrefsStore.shared.update { $0.lastNotifiedLevel = newLevel }
    }

    // MARK: - private

    /// Return the highest threshold name that `pct` has crossed.
    private func level(for pct: Int, prefs: Preferences) -> String? {
        if pct >= prefs.criticalThreshold { return "critical" }
        if pct >= prefs.alertThreshold    { return "alert" }
        if pct >= prefs.warnThreshold     { return "warn" }
        return nil
    }

    private func isHigher(_ a: String, than b: String) -> Bool {
        let rank = ["": 0, "warn": 1, "alert": 2, "critical": 3]
        return (rank[a] ?? 0) > (rank[b] ?? 0)
    }

    private func post(level: String, percent: Int, prefs: Preferences) {
        let title = "Claude Usage Widget"
        let body: String
        switch level {
        case "warn":
            body = L("notification.warn", percent)
        case "alert":
            body = L("notification.alert", percent)
        case "critical":
            body = L("notification.critical", percent)
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "threshold-\(level)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
