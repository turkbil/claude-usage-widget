import Foundation

/// Burn-rate forecast for the weekly window.
///
/// Given the current utilization and how much of the 7-day window has
/// already elapsed, predict either:
///   - the projected utilization at week end (if pace stays the same), or
///   - the moment at which the limit will be hit (if pace already exceeds it).
enum Forecast {

    private static let weeklyPeriodSec: Double = 7 * 24 * 3600

    enum Result {
        /// Pace is sustainable — projected end-of-week percentage.
        case underBudget(endPct: Int)
        /// Pace is unsustainable — when (relative to now) we'll hit 100%.
        case willHitLimit(in: TimeInterval)
        /// Already over limit (theoretically shouldn't happen, but be safe).
        case overLimit
    }

    /// Returns nil when the forecast is too noisy to be useful
    /// (e.g. first hour of the week, last 5% of the week, or zero usage).
    static func compute(snapshot: UsageSnapshot) -> Result? {
        let remainingSec = snapshot.weeklyResetsAt.timeIntervalSinceNow
        let elapsedSec   = weeklyPeriodSec - remainingSec
        let elapsedFrac  = elapsedSec / weeklyPeriodSec

        // Too early in the week or after reset.
        guard elapsedFrac > 0.05, elapsedFrac < 0.97 else { return nil }
        // Skip when usage hasn't started yet.
        guard snapshot.weeklyUtilization > 0.5 else { return nil }

        let pct = snapshot.weeklyUtilization

        if pct >= 100 { return .overLimit }

        let projectedEnd = pct / elapsedFrac
        if projectedEnd < 100 {
            return .underBudget(endPct: Int(projectedEnd.rounded()))
        }

        // We'll hit the limit before week end.
        let rate = pct / elapsedSec                 // % per second
        let secondsToLimit = (100 - pct) / rate     // > 0
        return .willHitLimit(in: secondsToLimit)
    }

    /// Localized human-friendly line, or nil if no useful forecast.
    static func line(for snapshot: UsageSnapshot) -> String? {
        guard let r = compute(snapshot: snapshot) else { return nil }
        switch r {
        case .underBudget(let endPct):
            return L("forecast.under", endPct)
        case .willHitLimit(let secs):
            return L("forecast.over", formatDuration(secs) as NSString)
        case .overLimit:
            return L("forecast.exceeded")
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return L("time.days_hours", d, h) }
        if h > 0 { return L("time.hours_minutes", h, m) }
        return L("time.minutes", m)
    }
}
