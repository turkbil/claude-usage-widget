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

        // The last level is kept per account: switching to an account that is
        // already at 90 % must not look like "crossed 90 %" again, and vice versa.
        let account = snapshot.email?.lowercased()
        let key = account.map { "lastNotifiedLevel.\($0)" }
        let last = key.flatMap { UserDefaults.standard.string(forKey: $0) } ?? (account == nil ? prefs.lastNotifiedLevel : nil)
        func store(_ v: String) {
            if let k = key { UserDefaults.standard.set(v, forKey: k) }
            else { PrefsStore.shared.update { $0.lastNotifiedLevel = v } }
        }

        // First sight of an account: remember its level silently.
        guard let lastLevel = last else { store(crossed ?? ""); return }

        // Reset state once we drop below warn — allows re-firing after reset.
        if pct < prefs.warnThreshold && !lastLevel.isEmpty { store(""); return }

        // No new level reached, or already notified about this or a higher level.
        guard let newLevel = crossed, isHigher(newLevel, than: lastLevel) else { return }

        ensureAuthorized()
        post(level: newLevel, percent: pct, prefs: prefs, account: account)
        prefs.lastNotifiedLevel = newLevel
        store(newLevel)
    }

    /// Account-level reminders, each sent once:
    ///  • an account's unused quota resets within 48 h (the "use this first" hint)
    ///  • a subscription ends within 3 days
    ///  • a free reset grant expires within 3 days unused
    func evaluateAccounts(_ states: [AccountState], suggestion: AccountState?, shortName: (String) -> String) {
        guard PrefsStore.shared.prefs.notificationsEnabled else { return }
        let now = Date(), soon: TimeInterval = 3 * 86400
        func once(_ key: String, _ body: String) {
            let k = "notified.\(key)"
            guard !UserDefaults.standard.bool(forKey: k) else { return }
            UserDefaults.standard.set(true, forKey: k)
            ensureAuthorized()
            send(title: "Claude Usage Widget", body: body, id: k)
        }
        if let s = suggestion, let next = s.nextReset, let left = s.weeklyLeft {
            once("hint.\(s.record.email).\(Int(next.timeIntervalSince1970))",
                 L("accounts.hint_other", shortName(s.record.email) as NSString, Int(left.rounded()), formatRemaining(next) as NSString))
        }
        for s in states {
            let name = shortName(s.record.email)
            if let end = s.record.planEndsAt, end > now, end.timeIntervalSince(now) <= soon {
                once("plan.\(s.record.email).\(Int(end.timeIntervalSince1970))",
                     L("notification.plan_end", name as NSString, shortDay(end) as NSString))
            }
            for g in s.grantsLeft {
                if let end = g.endsAt, end.timeIntervalSince(now) <= soon {
                    once("grant.\(s.record.email).\(g.kind).\(Int(end.timeIntervalSince1970))",
                         L("notification.grant_end", name as NSString, grantText([g]) as NSString))
                }
            }
        }
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

    private func send(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil),
                                               withCompletionHandler: nil)
    }

    private func post(level: String, percent: Int, prefs: Preferences, account: String? = nil) {
        let title = account.map { "Claude · \($0)" } ?? "Claude Usage Widget"
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
