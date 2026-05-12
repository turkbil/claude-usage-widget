import Foundation

/// Minimal MCP (Model Context Protocol) server over stdio.
///
/// MCP is JSON-RPC 2.0 over newline-delimited JSON. When the main binary is
/// launched with `--mcp-server`, it runs this loop instead of NSApp. Claude
/// Code (or any MCP client) spawns it as a subprocess and talks via stdio.
///
/// Implements just enough of the protocol to expose one tool — `get_usage` —
/// which returns the current weekly + 5-hour utilization snapshot as JSON.
///
/// Install by adding to ~/.claude.json:
/// ```json
/// {
///   "mcpServers": {
///     "claude-usage": {
///       "command": "/Users/you/ClaudeUsageWidget/ClaudeUsageWidget.app/Contents/MacOS/ClaudeUsageWidget",
///       "args": ["--mcp-server"]
///     }
///   }
/// }
/// ```
enum MCPServer {

    /// Run the stdio JSON-RPC loop. Never returns.
    static func run() -> Never {
        let stdin = FileHandle.standardInput

        while true {
            guard let line = readLine(strippingNewline: true), !line.isEmpty else {
                // EOF — Claude Code closed the pipe.
                exit(0)
            }
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            handle(message: json)
        }
        _ = stdin // silence unused warning if loop never exits
    }

    // MARK: - dispatch

    private static func handle(message: [String: Any]) {
        let id = message["id"]
        guard let method = message["method"] as? String else { return }

        switch method {
        case "initialize":
            send(result: [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:],
                ],
                "serverInfo": [
                    "name": "claude-usage-widget",
                    "version": currentVersion,
                ],
            ], id: id)

        case "notifications/initialized":
            // No response expected for notifications.
            break

        case "tools/list":
            send(result: [
                "tools": [getUsageToolSpec],
            ], id: id)

        case "tools/call":
            handleToolCall(params: message["params"] as? [String: Any] ?? [:], id: id)

        case "ping":
            send(result: [:], id: id)

        default:
            send(error: -32601, message: "method not found: \(method)", id: id)
        }
    }

    private static func handleToolCall(params: [String: Any], id: Any?) {
        let name = (params["name"] as? String) ?? ""
        switch name {
        case "get_usage":
            do {
                let snap = try ClaudeAPI.fetchSnapshot()
                let payload = encodeSnapshot(snap)
                send(result: [
                    "content": [
                        ["type": "text", "text": payload],
                    ],
                ], id: id)
            } catch {
                send(result: [
                    "content": [
                        ["type": "text", "text": "error: \(error.localizedDescription)"],
                    ],
                    "isError": true,
                ], id: id)
            }
        default:
            send(error: -32602, message: "unknown tool: \(name)", id: id)
        }
    }

    // MARK: - tool spec

    private static let getUsageToolSpec: [String: Any] = [
        "name": "get_usage",
        "description":
            "Get the user's current Claude usage from claude.ai/settings/usage. Returns weekly utilization %, weekly reset date, 5-hour-window utilization %, plan label (e.g. 'Max 20x'), and account display name. Useful before starting a long task to gauge how much budget you have left.",
        "inputSchema": [
            "type": "object",
            "properties": [:],
            "required": [],
        ],
    ]

    // MARK: - encoding

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

    private static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    // MARK: - JSON-RPC IO

    private static func send(result: [String: Any], id: Any?) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id = id { msg["id"] = id }
        emit(msg)
    }

    private static func send(error code: Int, message text: String, id: Any?) {
        var msg: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": text],
        ]
        if let id = id { msg["id"] = id }
        emit(msg)
    }

    private static func emit(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []),
              var str = String(data: data, encoding: .utf8) else { return }
        str.append("\n")
        FileHandle.standardOutput.write(str.data(using: .utf8) ?? Data())
    }
}
