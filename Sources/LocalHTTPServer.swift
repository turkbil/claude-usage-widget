import Foundation
import Network

/// Tiny HTTP server bound to 127.0.0.1:9123 (localhost only — never exposed
/// to the network). Serves a single endpoint that returns the latest usage
/// snapshot as JSON. Used by other tools (Raycast extensions, terminal
/// statuslines, etc.) that want to read the widget's data without parsing
/// the cache file or running the binary.
///
///   $ curl localhost:9123/usage
///   {"plan":"Max 20x","weekly_utilization_pct":42,...}
final class LocalHTTPServer {

    static let shared = LocalHTTPServer()
    static let port: NWEndpoint.Port = 9123

    private var listener: NWListener?
    private var lastSnapshot: UsageSnapshot?

    private init() {}

    /// Cache the latest snapshot so requests don't trigger a fresh API call
    /// (which would burn a Keychain prompt etc.). The main refresh loop calls
    /// this each time it gets fresh data.
    func setSnapshot(_ s: UsageSnapshot?) { lastSnapshot = s }

    /// Idempotent — call whenever `prefs.localApiEnabled` changes.
    func apply(enabled: Bool) {
        if enabled, listener == nil { start() }
        else if !enabled, listener != nil { stop() }
    }

    // MARK: - lifecycle

    private func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: Self.port)
            // requiredLocalEndpoint already carries 127.0.0.1:9123; also passing the port is
            // rejected with EINVAL on recent macOS, so the listener never started.
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.stateUpdateHandler = { st in
                FileHandle.standardError.write("[http] listener \(st)\n".data(using: .utf8)!)
            }
            l.start(queue: .global(qos: .utility))
            listener = l
        } catch {
            // Port in use or other error — logged; user will retry by toggling.
            FileHandle.standardError.write("[http] start failed: \(error)\n".data(using: .utf8)!)
            listener = nil
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            // The connection is closed in respond()'s send completion; closing it here
            // (before the async send finished) made every reply empty.
            guard let self = self, let data = data,
                  let request = String(data: data, encoding: .utf8) else {
                self?.respond(conn: conn, status: 400, body: "bad request")
                return
            }
            // Parse the request line — first line, format: "GET /usage HTTP/1.1"
            let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? request
            let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
            let path = parts.count > 1 ? parts[1] : "/"
            self.route(path: path, conn: conn)
        }
    }

    private func route(path: String, conn: NWConnection) {
        switch path {
        case "/usage", "/usage/", "/":
            let body = encodeSnapshot(lastSnapshot)
            respond(conn: conn, status: 200, body: body, contentType: "application/json")
        case "/accounts", "/accounts/":
            // Last-seen account records (e-mail, %, resets, free resets, API credit, dates) so the
            // Chrome extension can restore them after a reinstall. No cookies or payment data are in
            // this file. No CORS header: web pages can't read it, only an extension with host permission.
            let body = (try? String(contentsOfFile: AccountStore.path, encoding: .utf8)) ?? "[]"
            respond(conn: conn, status: 200, body: body, contentType: "application/json")
        case "/healthz":
            respond(conn: conn, status: 200, body: "{\"ok\":true}", contentType: "application/json")
        default:
            respond(conn: conn, status: 404, body: "{\"error\":\"not found\"}", contentType: "application/json")
        }
    }

    private func respond(conn: NWConnection, status: Int, body: String, contentType: String = "text/plain; charset=utf-8") {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default:  reason = "Error"
        }
        let head = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r
        """
        // A multi-line literal drops the newline before its closing quotes, so the header block
        // ended in "\r\n\r" and clients ate the first bytes of the body. Finish it explicitly.
        let payload = head + "\n" + body
        conn.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private func encodeSnapshot(_ s: UsageSnapshot?) -> String {
        guard let s = s else { return "{\"error\":\"no snapshot yet\"}" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var dict: [String: Any] = [
            "weekly_utilization_pct": Int(s.weeklyUtilization.rounded()),
            "weekly_resets_at": iso.string(from: s.weeklyResetsAt),
            "fetched_at": iso.string(from: s.fetchedAt),
        ]
        if let v = s.fiveHourUtilization { dict["five_hour_utilization_pct"] = Int(v.rounded()) }
        if let d = s.fiveHourResetsAt    { dict["five_hour_resets_at"] = iso.string(from: d) }
        if let v = s.sonnetUtilization   { dict["sonnet_utilization_pct"] = Int(v.rounded()) }
        if let n = s.displayName         { dict["display_name"] = n }
        if let p = s.planLabel           { dict["plan"] = p }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
