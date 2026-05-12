import Foundation

/// Tiny CLI mode for shell scripts that want the current usage as JSON
/// without speaking MCP or HTTP. Invoked with `--print-usage`.
///
///   $ ClaudeUsageWidget --print-usage
///   {"plan": "Max 20x", "weekly_utilization_pct": 42, ...}
enum CLIRunner {

    static func printUsageAndExit() -> Never {
        do {
            let snap = try ClaudeAPI.fetchSnapshot()
            let json = encodeSnapshot(snap)
            FileHandle.standardOutput.write((json + "\n").data(using: .utf8) ?? Data())
            exit(0)
        } catch {
            let msg = "error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(msg.data(using: .utf8) ?? Data())
            exit(1)
        }
    }

    private static func encodeSnapshot(_ s: UsageSnapshot) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var dict: [String: Any] = [
            "weekly_utilization_pct": Int(s.weeklyUtilization.rounded()),
            "weekly_resets_at": iso.string(from: s.weeklyResetsAt),
        ]
        if let v = s.fiveHourUtilization { dict["five_hour_utilization_pct"] = Int(v.rounded()) }
        if let d = s.fiveHourResetsAt    { dict["five_hour_resets_at"] = iso.string(from: d) }
        if let v = s.sonnetUtilization   { dict["sonnet_utilization_pct"] = Int(v.rounded()) }
        if let n = s.displayName         { dict["display_name"] = n }
        if let p = s.planLabel           { dict["plan"] = p }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
