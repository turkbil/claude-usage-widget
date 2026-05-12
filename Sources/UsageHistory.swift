import Foundation

/// Persistent circular buffer of weekly-utilization samples. Every refresh
/// adds one sample. The sparkline view reads from this to draw the trend.
final class UsageHistory {

    static let shared = UsageHistory()
    static let path   = NSString("~/.claude-usage-widget-history.json").expandingTildeInPath

    /// Cap the file. 7 days × 24h × 1 sample/min = 10,080 max. Use 1 sample
    /// per 5 min for ~2 weeks of history at 5MB worst case → very small.
    static let maxSamples = 4032          // 14 days at 5-min granularity
    static let minSpacingSec: TimeInterval = 5 * 60

    struct Sample: Codable {
        let t: TimeInterval   // unix epoch
        let v: Double         // weekly utilization %
    }

    private(set) var samples: [Sample] = []

    private init() { load() }

    /// Append a sample if at least `minSpacingSec` has passed since the last one.
    func record(weeklyPct: Double) {
        let now = Date().timeIntervalSince1970
        if let last = samples.last, now - last.t < Self.minSpacingSec { return }
        samples.append(Sample(t: now, v: weeklyPct))
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
        save()
    }

    /// Samples within the last `seconds` window.
    func recent(seconds: TimeInterval) -> [Sample] {
        let cutoff = Date().timeIntervalSince1970 - seconds
        return samples.filter { $0.t >= cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)),
              let arr = try? JSONDecoder().decode([Sample].self, from: data) else { return }
        samples = arr
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.path))
    }
}
