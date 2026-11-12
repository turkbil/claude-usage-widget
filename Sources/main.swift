import Cocoa
import Carbon.HIToolbox

// MARK: - Localization helpers

@inline(__always)
func L(_ key: String) -> String {
    return NSLocalizedString(key, comment: "")
}

@inline(__always)
func L(_ key: String, _ args: CVarArg...) -> String {
    let fmt = NSLocalizedString(key, comment: "")
    return withVaList(args) { NSString(format: fmt, arguments: $0) as String }
}

// MARK: - App-wide constants

struct AppConfig {
    static let cachePath = NSString("~/.claude-usage-widget-cache.json").expandingTildeInPath
}

// MARK: - Errors

enum WidgetError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return "error"
    }
}

// MARK: - API model

struct UsageSnapshot {
    let weeklyUtilization: Double
    let weeklyResetsAt: Date
    let fiveHourUtilization: Double?
    let fiveHourResetsAt: Date?
    let sonnetUtilization: Double?
    let displayName: String?
    let planLabel: String?
    let fetchedAt: Date
    var email: String? = nil
    var scopedLimits: [ScopedLimit] = []      // per-model weekly limits, e.g. Fable
    var planEndsAt: Date? = nil               // end of the paid month
    var planRenews: Bool? = nil               // true = auto-renews that day, false = cancelled/ending
    var breakdown: [(name: String, pct: Double)] = []   // where the week went: Claude Code, Chat, …
    var scopedShare: Double? = nil            // max % of the weekly limit the first scoped model may use
    var grants: [ResetGrant] = []             // free limit resets on hand
}

/// "default_claude_max_20x" → "Max 20x"
func prettyPlanName(_ tier: String) -> String {
    var s = tier.lowercased()
    s = s.replacingOccurrences(of: "default_claude_", with: "")
    s = s.replacingOccurrences(of: "default_", with: "")
    let parts = s.split(separator: "_").map(String.init)
    let pretty = parts.map { p -> String in
        switch p {
        case "max", "pro", "team", "free", "enterprise": return p.capitalized
        default: return p
        }
    }
    return pretty.joined(separator: " ")
}

// MARK: - Claude API

struct ClaudeAPI {
    static func fetchSnapshot() throws -> UsageSnapshot {
        let cookie = try BrowserCookieReader.sessionKey(prefs: PrefsStore.shared.prefs)
        let orgId  = try findOrgId(cookie: cookie)

        let account = try? fetchAccount(cookie: cookie)
        let planLabel:   String? = try? fetchPlanLabel(cookie: cookie, orgId: orgId)
        let plan = try? fetchPlanEnd(cookie: cookie, orgId: orgId)
        let planEndsAt = plan?.date

        // cedar_ember=1 adds the free-reset grants (what claude.ai/settings/usage shows). Read-only.
        let json = try getJSON("/api/organizations/\(orgId)/usage?cedar_ember=1&skip_spend=1", cookie: cookie)

        guard let dict = json as? [String: Any],
              let seven = dict["seven_day"] as? [String: Any],
              let weeklyUtil = (seven["utilization"] as? NSNumber)?.doubleValue,
              let weeklyResetsStr = seven["resets_at"] as? String,
              let weeklyResets = parseISO(weeklyResetsStr) else {
            throw WidgetError.message(L("error.api_parse"))
        }

        var fiveUtil: Double? = nil
        var fiveResets: Date? = nil
        if let five = dict["five_hour"] as? [String: Any] {
            fiveUtil = (five["utilization"] as? NSNumber)?.doubleValue
            if let s = five["resets_at"] as? String { fiveResets = parseISO(s) }
        }

        var sonnetUtil: Double? = nil
        for key in ["seven_day_sonnet", "seven_day_sonnet_only", "seven_day_opus"] {
            if let block = dict[key] as? [String: Any],
               let u = (block["utilization"] as? NSNumber)?.doubleValue {
                sonnetUtil = u; break
            }
        }

        // Per-model weekly limits (e.g. "Fable") live in limits[] as kind "weekly_scoped".
        var scoped: [ScopedLimit] = []
        for item in (dict["limits"] as? [[String: Any]]) ?? [] where (item["kind"] as? String) == "weekly_scoped" {
            let scope = item["scope"] as? [String: Any]
            let name = ((scope?["model"] as? [String: Any])?["display_name"] as? String)
                ?? ((scope?["surface"] as? [String: Any])?["display_name"] as? String)
            guard let n = name, let pct = (item["percent"] as? NSNumber)?.doubleValue else { continue }
            scoped.append(ScopedLimit(name: n, pct: pct, resetsAt: (item["resets_at"] as? String).flatMap(parseISO)))
        }

        // seven_day_breakdown.rows: share of this week's usage per surface.
        let breakdown: [(name: String, pct: Double)] =
            (((dict["seven_day_breakdown"] as? [String: Any])?["rows"] as? [[String: Any]]) ?? []).compactMap { row in
                guard let n = row["display_name"] as? String,
                      let p = (row["percent"] as? NSNumber)?.doubleValue else { return nil }
                return (n, p)
            }
        var grants: [ResetGrant] = []
        for g in ((dict["cedar_ember"] as? [String: Any])?["grants"] as? [[String: Any]]) ?? [] where (g["paused"] as? Bool) != true {
            let clears = g["clears"] as? [String] ?? []
            let kind = (g["gives_back_weekly"] as? Bool) == true ? "fable"
                     : clears.contains("seven_day") ? "weekly"
                     : clears.contains("five_hour") ? "session" : "other"
            grants.append(ResetGrant(kind: kind,
                                     left: (g["resets_left"] as? NSNumber)?.intValue ?? 0,
                                     total: (g["resets_total"] as? NSNumber)?.intValue ?? 0,
                                     endsAt: (g["ends_at"] as? String).flatMap(parseISO)))
        }
        let share = ((dict["weekly_scoped_shares"] as? [[String: Any]])?.first?["allowance_percent_of_weekly"] as? NSNumber)?.doubleValue

        return UsageSnapshot(
            weeklyUtilization:   weeklyUtil,
            weeklyResetsAt:      weeklyResets,
            fiveHourUtilization: fiveUtil,
            fiveHourResetsAt:    fiveResets,
            sonnetUtilization:   sonnetUtil,
            displayName:         account?.name,
            planLabel:           planLabel,
            fetchedAt:           Date(),
            email:               account?.email,
            scopedLimits:        scoped,
            planEndsAt:          planEndsAt,
            planRenews:          plan?.renews,
            breakdown:           breakdown,
            scopedShare:         share,
            grants:              grants
        )
    }

    static func fetchAccount(cookie: String) throws -> (name: String?, email: String?) {
        let json = try getJSON("/api/account", cookie: cookie)
        guard let dict = json as? [String: Any] else { throw WidgetError.message(L("error.api_parse")) }
        let email = (dict["email_address"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = [dict["display_name"], dict["full_name"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? email
        return (name, email)
    }

    /// End of the current paid month and whether it renews then. Only these two are
    /// read from the billing reply (no card or payment fields).
    static func fetchPlanEnd(cookie: String, orgId: String) throws -> (date: Date?, renews: Bool) {
        let json = try getJSON("/api/organizations/\(orgId)/subscription_details", cookie: cookie)
        guard let dict = json as? [String: Any] else { return (nil, false) }
        let date = ((dict["plan_ending_at"] as? String) ?? (dict["next_charge_at"] as? String)).flatMap(parseISO)
        // Active with a next charge and nothing scheduled to stop it → it renews.
        let renews = (dict["status"] as? String) == "active"
            && dict["next_charge_at"] is String
            && !(dict["scheduled_downgrade"].map { !($0 is NSNull) } ?? false)
            && !(dict["manual_pause_scheduled_at"].map { !($0 is NSNull) } ?? false)
        return (date, renews)
    }

    static func fetchPlanLabel(cookie: String, orgId: String) throws -> String {
        let json = try getJSON("/api/organizations/\(orgId)/rate_limits", cookie: cookie)
        guard let dict = json as? [String: Any],
              let tier = dict["rate_limit_tier"] as? String else {
            throw WidgetError.message(L("error.api_parse"))
        }
        return prettyPlanName(tier)
    }

    static func findOrgId(cookie: String) throws -> String {
        let json = try getJSON("/api/organizations", cookie: cookie)
        if let arr = json as? [[String: Any]] {
            // An account can also hold an API-only (Console) org, which answers
            // /usage with 403 — prefer the org that has the chat capability.
            for o in arr {
                if let id = o["uuid"] as? String,
                   let caps = o["capabilities"] as? [String], caps.contains("chat") { return id }
            }
            for o in arr {
                if let id = o["uuid"] as? String { return id }
            }
        }
        throw WidgetError.message(L("error.org_not_found"))
    }

    static func getJSON(_ path: String, cookie: String) throws -> Any {
        guard let url = URL(string: "https://claude.ai\(path)") else {
            throw WidgetError.message(L("error.empty_response"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("sessionKey=\(cookie)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json",     forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 ClaudeUsageWidget", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultStatus = 0
        var resultErr: Error?
        URLSession.shared.dataTask(with: req) { data, resp, err in
            resultData = data; resultErr = err
            if let http = resp as? HTTPURLResponse { resultStatus = http.statusCode }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        if let err = resultErr { throw err }
        guard let d = resultData else { throw WidgetError.message(L("error.empty_response")) }
        guard (200..<300).contains(resultStatus) else {
            let body = String(data: d, encoding: .utf8) ?? ""
            throw WidgetError.message(L("error.http", resultStatus, body.prefix(120) as NSString))
        }
        return try JSONSerialization.jsonObject(with: d, options: [])
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Formatting helpers (used by both TitleRenderer and popup views)

func formatRemaining(_ until: Date) -> String {
    let now = Date()
    let total = max(0, Int(until.timeIntervalSince(now)))
    if total <= 0 { return L("time.reset") }
    let d = total / 86400
    let h = (total % 86400) / 3600
    let m = (total % 3600) / 60
    if d > 0 { return L("time.days_hours", d, h) }
    if h > 0 { return L("time.hours_minutes", h, m) }
    return L("time.minutes", m)
}

func remainingWithSuffix(_ until: Date) -> String {
    // Past reset time: "reset" alone — no "… left" suffix.
    if until.timeIntervalSinceNow <= 0 { return L("time.reset") }
    return L("remaining.suffix", formatRemaining(until) as NSString)
}

// MARK: - Custom popup views

enum Layout {
    static let hPad: CGFloat = 18
    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 30
    static let footerHeight: CGFloat = 26
    static let barHeight: CGFloat = 8
}

final class ProgressBarView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var fillColor: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = r.height / 2
        let track = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        track.fill()
        let p = max(0, min(1, progress))
        guard p > 0 else { return }
        let w = max(r.height, r.width * CGFloat(p))
        let fillRect = NSRect(x: 0, y: 0, width: w, height: r.height)
        let path = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        fillColor.setFill()
        path.fill()
    }
}

final class UsageRowView: NSView {
    let labelField = NSTextField(labelWithString: "")
    let valueField = NSTextField(labelWithString: "")
    let bar = ProgressBarView(frame: .zero)

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.rowHeight))
        autoresizingMask = [.width]

        labelField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        labelField.textColor = .labelColor
        labelField.frame = NSRect(x: Layout.hPad, y: Layout.rowHeight - 26, width: width - Layout.hPad*2 - 60, height: 18)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.autoresizingMask = [.width]
        addSubview(labelField)

        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueField.textColor = .secondaryLabelColor
        valueField.alignment = .right
        valueField.frame = NSRect(x: width - Layout.hPad - 60, y: Layout.rowHeight - 26, width: 60, height: 18)
        valueField.autoresizingMask = [.minXMargin]
        addSubview(valueField)

        bar.frame = NSRect(x: Layout.hPad, y: 10, width: width - Layout.hPad*2, height: Layout.barHeight)
        bar.autoresizingMask = [.width]
        addSubview(bar)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(label: String, percent: Double?) {
        labelField.stringValue = label
        if let p = percent {
            bar.progress = p / 100.0
            bar.fillColor = colorFor(percent: p)
            let raw = L("title.percent", Int(p.rounded()))
            valueField.stringValue = raw.replacingOccurrences(of: "🤖 ", with: "")
            valueField.textColor = colorFor(percent: p)
        } else {
            bar.progress = 0
            valueField.stringValue = "—"
            valueField.textColor = .tertiaryLabelColor
        }
    }

    private func colorFor(percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        if percent >= 50 { return .systemYellow }
        return .systemGreen
    }
}

final class SectionHeaderView: NSView {
    let titleField = NSTextField(labelWithString: "")
    let trailingField = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.headerHeight))
        autoresizingMask = [.width]

        titleField.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        titleField.textColor = .secondaryLabelColor
        titleField.frame = NSRect(x: Layout.hPad, y: 8, width: 180, height: 14)
        addSubview(titleField)

        trailingField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        trailingField.textColor = .tertiaryLabelColor
        trailingField.alignment = .right
        trailingField.frame = NSRect(x: width - Layout.hPad - 140, y: 8, width: 140, height: 14)
        trailingField.autoresizingMask = [.minXMargin]
        addSubview(trailingField)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ title: String, trailing: String) {
        titleField.stringValue = title
        trailingField.stringValue = trailing
    }
}

final class PillLabelView: NSView {
    let field = NSTextField(labelWithString: "")
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.14).cgColor
        field.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        field.textColor = .labelColor
        field.alignment = .center
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ s: String) {
        field.stringValue = s
        sizeToFitText()
    }

    func sizeToFitText() {
        field.sizeToFit()
        let h: CGFloat = 18
        let w = field.bounds.width + 14
        let parentRight = superview?.bounds.maxX ?? bounds.maxX
        let x = parentRight - Layout.hPad - w
        let y = frame.origin.y
        frame = NSRect(x: x, y: y, width: w, height: h)
        field.frame = NSRect(x: 7, y: 1, width: field.bounds.width, height: 16)
    }
}

final class AccountHeaderView: NSView {
    let nameField = NSTextField(labelWithString: "")
    let planPill = PillLabelView()

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 36))
        autoresizingMask = [.width]

        nameField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.frame = NSRect(x: Layout.hPad, y: 10, width: width - Layout.hPad*2 - 100, height: 16)
        nameField.autoresizingMask = [.width]
        addSubview(nameField)

        planPill.frame = NSRect(x: 0, y: 9, width: 0, height: 18)
        planPill.autoresizingMask = [.minXMargin]
        addSubview(planPill)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(name: String?, plan: String?) {
        nameField.stringValue = name ?? ""
        if let p = plan, !p.isEmpty {
            planPill.setText(p)
            planPill.isHidden = false
        } else {
            planPill.isHidden = true
        }
        isHidden = (name?.isEmpty ?? true) && (plan?.isEmpty ?? true)
    }
}

final class SparklineView: NSView {
    var snapshot: UsageSnapshot? { didSet { needsDisplay = true } }
    var samples: [UsageHistory.Sample] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: Layout.hPad, dy: 6)
        guard r.width > 10, r.height > 10, let snap = snapshot else {
            // Empty state — no data yet
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.tertiaryLabelColor,
                .font: NSFont.systemFont(ofSize: 10),
            ]
            let hint = NSAttributedString(string: L("sparkline.empty"), attributes: attrs)
            let size = hint.size()
            hint.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            return
        }

        // Timeline spans the full weekly window: weekStart → weekEnd.
        let weekEndT   = snap.weeklyResetsAt.timeIntervalSince1970
        let weekStartT = weekEndT - 7 * 24 * 3600
        let nowT       = Date().timeIntervalSince1970
        let tRange = max(1, weekEndT - weekStartT)

        func point(t: Double, v: Double) -> NSPoint {
            let xFrac = max(0, min(1, (t - weekStartT) / tRange))
            let yFrac = max(0, min(1, v / 100))
            return NSPoint(
                x: r.minX + r.width * CGFloat(xFrac),
                y: r.minY + r.height * CGFloat(yFrac)
            )
        }

        // 1. Top baseline rule (the 100% mark).
        NSColor.tertiaryLabelColor.withAlphaComponent(0.18).setStroke()
        let baseline = NSBezierPath()
        baseline.lineWidth = 0.5
        baseline.move(to: NSPoint(x: r.minX, y: r.maxY))
        baseline.line(to: NSPoint(x: r.maxX, y: r.maxY))
        baseline.stroke()

        // 2. "Now" vertical guide (subtle).
        let nowX = point(t: nowT, v: 0).x
        NSColor.tertiaryLabelColor.withAlphaComponent(0.20).setStroke()
        let nowGuide = NSBezierPath()
        nowGuide.lineWidth = 0.5
        nowGuide.move(to: NSPoint(x: nowX, y: r.minY))
        nowGuide.line(to: NSPoint(x: nowX, y: r.maxY))
        nowGuide.stroke()

        // 3. Past path: weekStart (0%) → samples within range → now (current%).
        var past: [NSPoint] = []
        past.append(point(t: weekStartT, v: 0))
        for s in samples where s.t > weekStartT && s.t <= nowT {
            past.append(point(t: s.t, v: s.v))
        }
        past.append(point(t: nowT, v: snap.weeklyUtilization))

        let ember = NSColor(hex: "#d68c45")

        // Filled area under the past line
        let area = NSBezierPath()
        area.move(to: past[0])
        for p in past.dropFirst() { area.line(to: p) }
        area.line(to: NSPoint(x: past.last!.x, y: r.minY))
        area.line(to: NSPoint(x: past.first!.x, y: r.minY))
        area.close()
        if let grad = NSGradient(colors: [ember.withAlphaComponent(0.32),
                                         ember.withAlphaComponent(0.00)]) {
            grad.draw(in: area, angle: -90)   // top (line) strong → bottom clear
        }

        // Solid line for the past
        let pastPath = NSBezierPath()
        pastPath.move(to: past[0])
        for p in past.dropFirst() { pastPath.line(to: p) }
        pastPath.lineWidth = 1.5
        pastPath.lineCapStyle  = .round
        pastPath.lineJoinStyle = .round
        ember.setStroke()
        pastPath.stroke()

        // 4. Future path: now → weekEnd at projected % (dashed).
        let projected = projectedEndPct(for: snap)
        let futureEnd = point(t: weekEndT, v: projected)
        let future = NSBezierPath()
        future.move(to: past.last!)
        future.line(to: futureEnd)
        future.lineWidth = 1.2
        future.lineCapStyle = .round
        let dash: [CGFloat] = [3, 3]
        future.setLineDash(dash, count: 2, phase: 0)
        ember.withAlphaComponent(0.55).setStroke()
        future.stroke()

        // 5. Now dot (highlighted).
        let dotR: CGFloat = 2.8
        ember.setFill()
        let dot = NSBezierPath(ovalIn: NSRect(
            x: past.last!.x - dotR, y: past.last!.y - dotR,
            width: dotR * 2, height: dotR * 2))
        dot.fill()

        // 6. Tiny projected-end dot (ghost).
        ember.withAlphaComponent(0.55).setFill()
        let endDotR: CGFloat = 2.0
        let endDot = NSBezierPath(ovalIn: NSRect(
            x: futureEnd.x - endDotR, y: futureEnd.y - endDotR,
            width: endDotR * 2, height: endDotR * 2))
        endDot.fill()
    }

    /// Linear extrapolation to end of week, capped at 100%.
    private func projectedEndPct(for snap: UsageSnapshot) -> Double {
        let weekEndT   = snap.weeklyResetsAt.timeIntervalSince1970
        let weekStartT = weekEndT - 7 * 24 * 3600
        let nowT       = Date().timeIntervalSince1970
        let elapsed = max(60, nowT - weekStartT)
        let total   = max(60, weekEndT - weekStartT)
        let projected = snap.weeklyUtilization * (total / elapsed)
        return min(100, max(snap.weeklyUtilization, projected))
    }
}

final class ForecastView: NSView {
    let field = NSTextField(labelWithString: "")
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = [.width]
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.frame = NSRect(x: Layout.hPad, y: 4, width: width - Layout.hPad*2, height: 14)
        field.autoresizingMask = [.width]
        field.lineBreakMode = .byTruncatingTail
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ text: String?, isWarning: Bool = false) {
        if let t = text, !t.isEmpty {
            field.stringValue = t
            field.textColor = isWarning ? .systemOrange : .secondaryLabelColor
            isHidden = false
        } else {
            isHidden = true
        }
    }
}

/// "Güncelleme: 01:04 ········ ⟳ Şimdi yenile" — clicking refreshes at once and
/// keeps the menu open (the ⌘R menu item closes it).
final class FooterView: NSView {
    let field = NSTextField(labelWithString: "")
    private let action = NSTextField(labelWithString: "")
    var onRefresh: (() -> Void)?
    private(set) var busy = false
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.footerHeight))
        autoresizingMask = [.width]
        wantsLayer = true
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .tertiaryLabelColor
        field.frame = NSRect(x: Layout.hPad, y: 6, width: width - Layout.hPad*2 - 130, height: 14)
        field.autoresizingMask = [.width]
        field.lineBreakMode = .byTruncatingTail
        addSubview(field)
        action.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        action.textColor = .secondaryLabelColor
        action.alignment = .right
        action.frame = NSRect(x: width - Layout.hPad - 128, y: 6, width: 128, height: 14)
        action.autoresizingMask = [.minXMargin]
        addSubview(action)
        setBusy(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ s: String) { field.stringValue = s }
    func setBusy(_ b: Bool) {
        busy = b
        action.stringValue = b ? L("footer.refreshing") : "⟳ " + L("footer.refresh")
        action.textColor = b ? .tertiaryLabelColor : .secondaryLabelColor
    }
    override func mouseUp(with event: NSEvent) {
        guard !busy else { return }
        setBusy(true)
        onRefresh?()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor }
    override func mouseExited(with event: NSEvent)  { layer?.backgroundColor = nil }
}

// MARK: - App

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Core
    var statusItem: NSStatusItem!
    var pollTimer: Timer?
    var titleTickTimer: Timer?
    var lastSnapshot: UsageSnapshot?
    var lastError: String?
    var lastUpdate: Date = Date(timeIntervalSince1970: 0)

    // Popup views
    var accountHeader: AccountHeaderView!
    var accountSeparator: NSMenuItem?
    var weeklyHeader: SectionHeaderView!
    var allModelsRow: UsageRowView!
    var sonnetRow: UsageRowView!
    // Menu items whose views can hide: a hidden *view* still takes its height in an
    // NSMenu, so the item itself must be hidden.
    var sonnetItem: NSMenuItem!
    var forecastItem: NSMenuItem!
    var detailsView: DetailsView!
    var detailsItem: NSMenuItem!
    var fiveHourHeaderItem: NSMenuItem!
    var fiveHourItem: NSMenuItem!
    var fiveHourSeparator: NSMenuItem!
    // Accounts section
    var accountsAnchor: NSMenuItem!
    var accountsHeader: AccountsHeaderView!
    var suggestionView: NoteView!
    var suggestionItem: NSMenuItem!
    var staleView: NoteView!
    var staleItem: NSMenuItem!
    var accountRowItems: [NSMenuItem] = []
    var grantDetailItems: [NSMenuItem] = []      // one per account, shown when expanded
    var grantHeaderItem: NSMenuItem!             // "↺ HAFTALIK HAK · ↺ FABLE HAKKI" when expanded
    var grantsToggle: ToggleRowView!
    var grantsToggleItem: NSMenuItem!
    var grantsExpanded: Bool {
        get { UserDefaults.standard.bool(forKey: "grantsExpanded") }
        set { UserDefaults.standard.set(newValue, forKey: "grantsExpanded") }
    }
    var showHiddenItem: NSMenuItem!
    var forecastView: ForecastView!
    var sparklineView: SparklineView!
    var fiveHourHeader: SectionHeaderView!
    var fiveHourRow: UsageRowView!
    var footer: FooterView!
    let menuWidth: CGFloat = 470

    // Menu items that need live updating
    var versionUpdateItem: NSMenuItem?
    var versionUpdateSeparator: NSMenuItem?

    static func main() {
        // CLI-mode subprocess flags must short-circuit before any AppKit setup.
        if CommandLine.arguments.contains("--mcp-server") {
            MCPServer.run()
        }
        if CommandLine.arguments.contains("--print-usage") {
            CLIRunner.printUsageAndExit()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = L("title.loading")

        buildMenu()
        loadCache()
        refresh()
        startPollTimer()

        // Tick title every 30s so countdowns stay fresh between full refreshes.
        titleTickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateTitle()
            self?.updateMenuLabels()
            self?.updateAccountsSection()
        }

        // React to preference changes from any settings menu.
        NotificationCenter.default.addObserver(forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.handlePrefsChanged()
        }

        // Wire global hotkey.
        applyHotkey()

        // Version check on launch (fires only if due).
        VersionChecker.shared.checkIfDue()

        // Local HTTP endpoint reflects the current preference.
        LocalHTTPServer.shared.apply(enabled: PrefsStore.shared.prefs.localApiEnabled)
    }

    // MARK: - Timers

    func startPollTimer() {
        pollTimer?.invalidate()
        let interval = TimeInterval(max(15, PrefsStore.shared.prefs.pollIntervalSec))
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func handlePrefsChanged() {
        startPollTimer()
        applyHotkey()
        updateTitle()
        updateMenuLabels()
        // Rebuild only the dynamic submenus that show state (e.g. checkmarks).
        rebuildSettingsMenus()
        // Reflect any new latestKnownVersion.
        refreshVersionBadge()
        // Start/stop local HTTP endpoint if its toggle changed.
        LocalHTTPServer.shared.apply(enabled: PrefsStore.shared.prefs.localApiEnabled)
    }

    // MARK: - Hotkey

    func applyHotkey() {
        HotKeyManager.shared.apply(prefs: PrefsStore.shared.prefs) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    // MARK: - Persistence

    func loadCache() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: AppConfig.cachePath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wu = dict["weeklyUtilization"] as? Double,
              let wr = dict["weeklyResetsAt"] as? String,
              let wrDate = ClaudeAPI.parseISO(wr) else { return }
        lastSnapshot = UsageSnapshot(
            weeklyUtilization:   wu,
            weeklyResetsAt:      wrDate,
            fiveHourUtilization: dict["fiveHourUtilization"] as? Double,
            fiveHourResetsAt:    (dict["fiveHourResetsAt"] as? String).flatMap(ClaudeAPI.parseISO),
            sonnetUtilization:   dict["sonnetUtilization"] as? Double,
            displayName:         dict["displayName"] as? String,
            planLabel:           dict["planLabel"] as? String,
            fetchedAt:           (dict["fetchedAt"] as? String).flatMap(ClaudeAPI.parseISO) ?? Date(),
            email:               dict["email"] as? String,
            scopedLimits:        ((dict["scoped"] as? [[String: Any]]) ?? []).compactMap { d in
                guard let n = d["name"] as? String, let p = d["pct"] as? Double else { return nil }
                return ScopedLimit(name: n, pct: p, resetsAt: (d["resetsAt"] as? String).flatMap(ClaudeAPI.parseISO))
            },
            planEndsAt:          (dict["planEndsAt"] as? String).flatMap(ClaudeAPI.parseISO),
            planRenews:          dict["planRenews"] as? Bool
        )
        updateTitle()
        updateMenuLabels()
        // Make sure the sparkline shows the cached snapshot on first open.
        sparklineView?.snapshot = lastSnapshot
        sparklineView?.samples  = UsageHistory.shared.recent(seconds: 7 * 24 * 3600, account: lastSnapshot?.email)
    }

    func saveCache(_ s: UsageSnapshot) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var dict: [String: Any] = [
            "weeklyUtilization": s.weeklyUtilization,
            "weeklyResetsAt":    iso.string(from: s.weeklyResetsAt),
            "fetchedAt":         iso.string(from: s.fetchedAt),
        ]
        if let v = s.fiveHourUtilization { dict["fiveHourUtilization"] = v }
        if let d = s.fiveHourResetsAt    { dict["fiveHourResetsAt"]    = iso.string(from: d) }
        if let v = s.sonnetUtilization   { dict["sonnetUtilization"]   = v }
        if let n = s.displayName         { dict["displayName"]         = n }
        if let p = s.planLabel           { dict["planLabel"]           = p }
        if let e = s.email               { dict["email"]               = e }
        if let d = s.planEndsAt          { dict["planEndsAt"]          = iso.string(from: d) }
        if let r = s.planRenews          { dict["planRenews"]          = r }
        dict["scoped"] = s.scopedLimits.map { l -> [String: Any] in
            var d: [String: Any] = ["name": l.name, "pct": l.pct]
            if let r = l.resetsAt { d["resetsAt"] = iso.string(from: r) }
            return d
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: AppConfig.cachePath))
        }
    }

    // MARK: - Refresh

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let snap = try ClaudeAPI.fetchSnapshot()
                DispatchQueue.main.async {
                    self.footer?.setBusy(false)
                    self.lastSnapshot = snap
                    self.lastError    = nil
                    self.lastUpdate   = Date()
                    self.saveCache(snap)
                    self.updateTitle()
                    self.updateMenuLabels()
                    NotificationManager.shared.evaluate(snapshot: snap)
                    VersionChecker.shared.checkIfDue()
                    self.refreshVersionBadge()
                    LocalHTTPServer.shared.setSnapshot(snap)
                    UsageHistory.shared.record(weeklyPct: snap.weeklyUtilization, account: snap.email)
                    AccountStore.shared.upsert(snap)
                    self.updateAccountsSection()
                    self.sparklineView?.snapshot = snap
                    self.sparklineView?.samples = UsageHistory.shared.recent(seconds: 7 * 24 * 3600, account: snap.email)
                }
            } catch {
                DispatchQueue.main.async {
                    self.footer?.setBusy(false)
                    self.lastError = error.localizedDescription
                    self.updateMenuLabels()
                    if self.lastSnapshot == nil, let button = self.statusItem.button {
                        button.attributedTitle = NSAttributedString(
                            string: L("title.error"),
                            attributes: [.foregroundColor: NSColor.systemRed]
                        )
                    }
                }
            }
        }
    }

    // MARK: - Title

    func updateTitle() {
        guard let button = statusItem.button else { return }
        let attr = TitleRenderer.compose(
            snapshot: lastSnapshot,
            prefs: PrefsStore.shared.prefs,
            error: (lastSnapshot == nil && lastError != nil)
        )
        // "⏳ claude1" — same mark as the popup hint: another account's unused quota
        // resets within 48 h, use it first. (An arrow read as "signed in as claude1".)
        let current = lastSnapshot?.email?.lowercased()
        var hintTip: String? = nil
        if PrefsStore.shared.prefs.menuBarHint == true,
           let sug = AccountMath.suggestion(AccountStore.shared.states()), sug.record.email != current {
            let short = AccountStore.shared.shortName(sug.record.email)
            if let next = sug.nextReset, let left = sug.weeklyLeft {
                hintTip = L("accounts.hint_other", short as NSString, Int(left.rounded()), formatRemaining(next) as NSString)
            }
            let title = NSMutableAttributedString(attributedString: attr)
            title.append(NSAttributedString(string: "  ⏳" + short,
                                            attributes: [.foregroundColor: NSColor.systemOrange,
                                                         .font: NSFont.menuBarFont(ofSize: 0)]))
            button.attributedTitle = title
        } else {
            button.attributedTitle = attr
        }
        if let s = lastSnapshot {
            let pct = Int(s.weeklyUtilization.rounded())
            button.toolTip = L("tooltip", pct, formatRemaining(s.weeklyResetsAt) as NSString)
                + (hintTip.map { "\n⏳ " + $0 } ?? "")
        }
    }

    // MARK: - Menu (popup)

    func buildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = menuWidth

        accountHeader = AccountHeaderView(width: menuWidth)
        let accountItem = NSMenuItem(); accountItem.view = accountHeader
        menu.addItem(accountItem)
        accountSeparator = NSMenuItem.separator()
        menu.addItem(accountSeparator!)

        weeklyHeader = SectionHeaderView(width: menuWidth)
        let weeklyHeaderItem = NSMenuItem(); weeklyHeaderItem.view = weeklyHeader
        menu.addItem(weeklyHeaderItem)

        allModelsRow = UsageRowView(width: menuWidth)
        let allModelsItem = NSMenuItem(); allModelsItem.view = allModelsRow
        menu.addItem(allModelsItem)

        sonnetRow = UsageRowView(width: menuWidth)
        sonnetItem = NSMenuItem(); sonnetItem.view = sonnetRow
        menu.addItem(sonnetItem)

        // 7-day sparkline trend, then its forecast line
        sparklineView = SparklineView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 44))
        sparklineView.autoresizingMask = [.width]
        let sparklineItem = NSMenuItem(); sparklineItem.view = sparklineView
        menu.addItem(sparklineItem)

        forecastView = ForecastView(width: menuWidth)
        forecastItem = NSMenuItem(); forecastItem.view = forecastView
        menu.addItem(forecastItem)

        // Current account details: reset · plan end · daily budget · where the week went
        menu.addItem(NSMenuItem.separator())
        detailsView = DetailsView(width: menuWidth)
        detailsItem = NSMenuItem(); detailsItem.view = detailsView
        menu.addItem(detailsItem)

        fiveHourSeparator = NSMenuItem.separator()
        menu.addItem(fiveHourSeparator)

        fiveHourHeader = SectionHeaderView(width: menuWidth)
        fiveHourHeaderItem = NSMenuItem(); fiveHourHeaderItem.view = fiveHourHeader
        menu.addItem(fiveHourHeaderItem)

        fiveHourRow = UsageRowView(width: menuWidth)
        fiveHourItem = NSMenuItem(); fiveHourItem.view = fiveHourRow
        menu.addItem(fiveHourItem)

        // Accounts seen on this Mac (last-seen values for the signed-out ones)
        menu.addItem(NSMenuItem.separator())
        accountsHeader = AccountsHeaderView(width: menuWidth)
        accountsAnchor = NSMenuItem(); accountsAnchor.view = accountsHeader
        menu.addItem(accountsAnchor)

        suggestionView = NoteView(width: menuWidth, height: 24)
        suggestionView.field.textColor = .systemOrange
        suggestionItem = NSMenuItem(); suggestionItem.view = suggestionView
        menu.addItem(suggestionItem)
        grantHeaderItem = NSMenuItem(); grantHeaderItem.view = GrantHeaderView(width: menuWidth)
        menu.addItem(grantHeaderItem)
        // account rows are inserted here by updateAccountsSection()
        staleView = NoteView(width: menuWidth, height: 28)
        staleView.field.textColor = .tertiaryLabelColor
        staleView.field.font = .systemFont(ofSize: 10)
        staleView.field.stringValue = L("accounts.stale_note")
        // "▸ Show free resets" — expands a line under every account without closing the menu.
        grantsToggle = ToggleRowView(width: menuWidth)
        grantsToggle.onToggle = { [weak self] in
            guard let self = self else { return }
            self.grantsExpanded.toggle()
            self.updateAccountsSection()
        }
        grantsToggleItem = NSMenuItem(); grantsToggleItem.view = grantsToggle
        menu.addItem(grantsToggleItem)

        staleItem = NSMenuItem(); staleItem.view = staleView
        menu.addItem(staleItem)
        showHiddenItem = NSMenuItem(title: "", action: #selector(showHiddenAccounts), keyEquivalent: "")
        showHiddenItem.target = self
        menu.addItem(showHiddenItem)

        menu.addItem(NSMenuItem.separator())

        footer = FooterView(width: menuWidth)
        footer.onRefresh = { [weak self] in self?.refresh() }
        let footerItem = NSMenuItem(); footerItem.view = footer
        menu.addItem(footerItem)

        menu.addItem(NSMenuItem.separator())

        // Single menu item that opens a real Settings window
        menu.addItem(NSMenuItem(title: L("menu.settings"),
                                action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("menu.refresh"),    action: #selector(menuRefresh),   keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: L("menu.open_usage"), action: #selector(menuOpenUsage), keyEquivalent: "u"))

        // Version-update item (hidden by default)
        let upd = NSMenuItem.separator(); upd.isHidden = true
        versionUpdateSeparator = upd
        menu.addItem(upd)
        let updItem = NSMenuItem(title: L("menu.version_new", "1.0.0"),
                                 action: #selector(menuOpenReleases), keyEquivalent: "")
        updItem.isHidden = true
        versionUpdateItem = updItem
        menu.addItem(updItem)

        // Quit
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("menu.quit"),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        // Credit footer (§10) — two clickable links
        menu.addItem(NSMenuItem.separator())
        let creditWeb = NSMenuItem(title: "nurullah.net ↗",
                                   action: #selector(menuOpenAuthorSite), keyEquivalent: "")
        creditWeb.attributedTitle = creditAttributed("nurullah.net ↗")
        menu.addItem(creditWeb)

        let creditX = NSMenuItem(title: "@nurullah ↗",
                                 action: #selector(menuOpenAuthorX), keyEquivalent: "")
        creditX.attributedTitle = creditAttributed("@nurullah ↗")
        menu.addItem(creditX)

        statusItem.menu = menu
        updateAccountsSection()
    }

    /// "What to do with claude3?" — Hide (kept, can be shown again) or Delete (record
    /// removed; it returns only when that account signs in again). The user chooses.
    func confirmHide(_ email: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("hide.title", AccountStore.shared.shortName(email) as NSString)
        alert.informativeText = L("hide.body", email as NSString)
        alert.addButton(withTitle: L("hide.confirm"))       // Gizle
        let del = alert.addButton(withTitle: L("hide.delete"))  // Sil
        del.hasDestructiveAction = true
        alert.addButton(withTitle: L("hide.cancel"))        // Vazgeç
        switch alert.runModal() {
        case .alertFirstButtonReturn:  AccountStore.shared.hide(email)
        case .alertSecondButtonReturn: AccountStore.shared.remove(email)
        default: return
        }
        updateAccountsSection()
        updateTitle()
    }

    @objc func showHiddenAccounts() {
        AccountStore.shared.unhideAll()
        updateAccountsSection()
        updateTitle()
    }

    /// Rebuilds the account rows and the 48-hour hint from AccountStore.
    func updateAccountsSection() {
        guard let menu = statusItem.menu, accountsAnchor != nil else { return }
        let current = lastSnapshot?.email?.lowercased()
        let store = AccountStore.shared
        let states = store.states()

        let hiddenCount = store.hidden.count
        showHiddenItem.isHidden = hiddenCount == 0
        showHiddenItem.attributedTitle = NSAttributedString(string: L("hide.show", hiddenCount), attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12)])
        let empty = states.isEmpty
        accountsAnchor.isHidden = empty
        staleItem.isHidden = empty || states.count < 2

        NotificationManager.shared.evaluateAccounts(states, suggestion: AccountMath.suggestion(states),
                                                    shortName: store.shortName)
        if let s = AccountMath.suggestion(states), let next = s.nextReset, let left = s.weeklyLeft {
            let pct = Int(left.rounded())
            let text = s.record.email == current
                ? L("accounts.hint_current", pct, formatRemaining(next) as NSString)
                : L("accounts.hint_other", store.shortName(s.record.email) as NSString, pct, formatRemaining(next) as NSString)
            suggestionView.field.stringValue = "⏳ " + text
            suggestionItem.isHidden = false
        } else {
            suggestionItem.isHidden = true
        }

        // Reuse rows when the count is unchanged (the menu may be open).
        if accountRowItems.count != states.count {
            for item in accountRowItems + grantDetailItems { menu.removeItem(item) }
            accountRowItems = states.map { _ in
                let item = NSMenuItem()
                item.view = AccountRowView(width: menuWidth)
                return item
            }
            grantDetailItems = states.map { _ in
                let item = NSMenuItem()
                item.view = GrantDetailView(width: menuWidth)
                return item
            }
            var at = menu.index(of: grantHeaderItem) + 1
            for (row, detail) in zip(accountRowItems, grantDetailItems) {
                menu.insertItem(row, at: at); menu.insertItem(detail, at: at + 1); at += 2
            }
        }
        grantsToggle.update(expanded: grantsExpanded)
        grantsToggleItem.isHidden = empty
        grantHeaderItem.isHidden = empty || !grantsExpanded
        for (item, s) in zip(grantDetailItems, states) {
            (item.view as? GrantDetailView)?.update(s)
            item.isHidden = !grantsExpanded
        }
        for (item, s) in zip(accountRowItems, states) {
            let row = item.view as? AccountRowView
            row?.update(s, isCurrent: s.record.email == current, shortName: store.shortName(s.record.email))
            let email = s.record.email
            row?.onClick = { [weak self] in self?.confirmHide(email) }
            item.toolTip = (item.view as? AccountRowView)?.toolTip
        }
    }

    private func creditAttributed(_ s: String) -> NSAttributedString {
        return NSAttributedString(string: s, attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .font: NSFont.systemFont(ofSize: 11),
        ])
    }

    /// "↻ Pzt 16:00 sıfırlanır · Abonelik 13 Kas · 0 sıfırlama kaldı" · daily budget · breakdown
    /// Label–value rows for the signed-in account: reset · plan end · daily budget · usage.
    func currentDetailRows(_ s: UsageSnapshot) -> [DetailRow] {
        var rows = [DetailRow(label: L("detail.reset"), value: weekdayTime(s.weeklyResetsAt))]
        if let end = s.planEndsAt, s.planRenews == true {
            rows.append(DetailRow(label: L("detail.renews"), value: shortDay(end)))
        } else if let end = s.planEndsAt {
            let n = AccountMath.resetsBefore(end, next: s.weeklyResetsAt)
            if end < Date() {
                rows.append(DetailRow(label: L("detail.plan"), value: shortDay(end) + " · " + L("accounts.plan_passed"), color: .tertiaryLabelColor))
            } else if n == 0 {
                rows.append(DetailRow(label: L("detail.plan"), value: shortDay(end) + " · " + L("detail.last_week"), color: .systemOrange))
            } else {
                rows.append(DetailRow(label: L("detail.plan"), value: shortDay(end) + (n.map { " · " + L("accounts.resets", $0) } ?? "")))
            }
        }

        let onHand = s.grants.filter { $0.left > 0 && ($0.endsAt.map { $0 > Date() } ?? true) }
        if !onHand.isEmpty {
            rows.append(DetailRow(label: L("detail.grants"), value: grantText(onHand), color: NSColor(hex: "#d68c45")))
        }

        // Daily budget: what is left spread over the days until the reset.
        let days = s.weeklyResetsAt.timeIntervalSinceNow / 86400
        if days > 0.25 {
            let left = max(0, 100 - s.weeklyUtilization)
            rows.append(DetailRow(label: L("detail.daily"), value: "~%\(Int((left / max(1, days)).rounded()))"))
        }

        let used = s.breakdown.filter { $0.pct >= 1 }.sorted { $0.pct > $1.pct }
        if !used.isEmpty {
            rows.append(DetailRow(label: L("detail.breakdown"),
                                  value: used.map { "\($0.name) %\(Int($0.pct.rounded()))" }.joined(separator: " · ")))
        }
        return rows
    }

    func updateMenuLabels() {
        guard weeklyHeader != nil else { return }

        if let s = lastSnapshot, (s.displayName != nil || s.planLabel != nil) {
            // The e-mail tells the accounts apart; display names are often the same.
            accountHeader.update(name: s.email.map { "● " + $0 } ?? s.displayName, plan: s.planLabel)
            accountHeader.isHidden = false
            accountSeparator?.isHidden = false
        } else {
            accountHeader.isHidden = true
            accountSeparator?.isHidden = true
        }

        if let s = lastSnapshot {
            weeklyHeader.update(L("section.weekly"), trailing: remainingWithSuffix(s.weeklyResetsAt))
            allModelsRow.update(label: L("label.all_models"), percent: s.weeklyUtilization)
            let rows = currentDetailRows(s)
            detailsView.update(rows)
            detailsItem.isHidden = rows.isEmpty

            if let f = s.scopedLimits.first {
                let label = s.scopedShare.map { L("label.scoped_cap", f.name as NSString, Int($0.rounded())) } ?? f.name
                sonnetRow.update(label: label, percent: f.pct)
                sonnetItem.isHidden = false
            } else if let sonnet = s.sonnetUtilization {
                sonnetRow.update(label: L("label.sonnet"), percent: sonnet)
                sonnetItem.isHidden = false
            } else {
                sonnetItem.isHidden = true
            }

            // §13 Forecast — show only when meaningful
            if let line = Forecast.line(for: s) {
                let isWarn: Bool = {
                    if case .willHitLimit = (Forecast.compute(snapshot: s) ?? .underBudget(endPct: 0)) { return true }
                    return false
                }()
                forecastView.update(line, isWarning: isWarn)
                forecastItem.isHidden = false
            } else {
                forecastView.update(nil)
                forecastItem.isHidden = true
            }

            if let u = s.fiveHourUtilization, let r = s.fiveHourResetsAt {
                fiveHourHeader.update(L("section.five_hour"), trailing: remainingWithSuffix(r))
                fiveHourRow.update(label: L("label.usage"), percent: u)
                fiveHourItem.isHidden = false
                fiveHourHeaderItem.isHidden = false
                fiveHourSeparator.isHidden = false
            } else {
                fiveHourHeaderItem.isHidden = true
                fiveHourItem.isHidden       = true
                fiveHourSeparator.isHidden  = true
            }
        } else {
            forecastView?.update(nil)
            weeklyHeader.update(L("section.weekly"), trailing: "—")
            allModelsRow.update(label: L("label.all_models"), percent: nil)
            sonnetRow.update(label: L("label.sonnet"), percent: nil)
            fiveHourHeader.update(L("section.five_hour"), trailing: "—")
            fiveHourRow.update(label: L("label.usage"), percent: nil)
        }

        let when = lastUpdate.timeIntervalSince1970 == 0
            ? "—"
            : DateFormatter.localizedString(from: lastUpdate, dateStyle: .none, timeStyle: .short)
        if let err = lastError {
            footer.update("⚠︎ \(err)")
            footer.field.textColor = .systemRed
        } else {
            footer.update(L("footer.updated", when as NSString))
            footer.field.textColor = .tertiaryLabelColor
        }
    }

    func refreshVersionBadge() {
        guard let item = versionUpdateItem, let sep = versionUpdateSeparator else { return }
        if VersionChecker.shared.updateAvailable {
            let v = PrefsStore.shared.prefs.latestKnownVersion
            item.title = L("menu.version_new", v as NSString)
            item.isHidden = false
            sep.isHidden  = false
        } else {
            item.isHidden = true
            sep.isHidden  = true
        }
    }

    // MARK: - Settings submenus

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    func buildSettingsMenu() -> NSMenu {
        let m = NSMenu()

        // §01 Title content per-metric
        let titleSub = NSMenuItem(title: L("menu.title_content"), action: nil, keyEquivalent: "")
        titleSub.submenu = buildTitleContentMenu()
        m.addItem(titleSub)

        // §02 Icon picker
        let iconSub = NSMenuItem(title: L("menu.icon"), action: nil, keyEquivalent: "")
        iconSub.submenu = buildIconMenu()
        m.addItem(iconSub)

        m.addItem(NSMenuItem.separator())

        // §06 Refresh interval
        let refreshSub = NSMenuItem(title: L("menu.refresh_interval"), action: nil, keyEquivalent: "")
        refreshSub.submenu = buildRefreshMenu()
        m.addItem(refreshSub)

        // §05 Notifications
        let notifSub = NSMenuItem(title: L("menu.notifications"), action: nil, keyEquivalent: "")
        notifSub.submenu = buildNotificationsMenu()
        m.addItem(notifSub)

        // §07 Hotkey
        let hotSub = NSMenuItem(title: L("menu.hotkey"), action: nil, keyEquivalent: "")
        hotSub.submenu = buildHotkeyMenu()
        m.addItem(hotSub)

        m.addItem(NSMenuItem.separator())

        // §08 Browsers
        let browserSub = NSMenuItem(title: L("menu.browsers"), action: nil, keyEquivalent: "")
        browserSub.submenu = buildBrowserMenu()
        m.addItem(browserSub)

        // §09 Version check toggle
        let updItem = NSMenuItem(title: L("menu.version_check"),
                                 action: #selector(toggleVersionCheck), keyEquivalent: "")
        updItem.state = PrefsStore.shared.prefs.versionCheckEnabled ? .on : .off
        m.addItem(updItem)

        // §09 Local HTTP endpoint
        let httpItem = NSMenuItem(title: L("menu.local_http"),
                                  action: #selector(toggleLocalHTTP), keyEquivalent: "")
        httpItem.state = PrefsStore.shared.prefs.localApiEnabled ? .on : .off
        m.addItem(httpItem)

        // §09 MCP install instructions
        let mcpItem = NSMenuItem(title: L("menu.mcp_install"),
                                 action: #selector(showMCPInstall), keyEquivalent: "")
        m.addItem(mcpItem)

        return m
    }

    @objc func toggleLocalHTTP() {
        PrefsStore.shared.update { $0.localApiEnabled.toggle() }
    }

    @objc func showMCPInstall() {
        let alert = NSAlert()
        alert.messageText = L("mcp.install_title")
        alert.informativeText = L("mcp.install_body",
            (Bundle.main.executablePath ?? "/path/to/ClaudeUsageWidget") as NSString)
        alert.addButton(withTitle: L("button.copy_path"))
        alert.addButton(withTitle: L("button.ok"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Bundle.main.executablePath ?? "", forType: .string)
        }
    }

    func rebuildSettingsMenus() {
        guard let main = statusItem.menu else { return }
        for item in main.items where item.submenu != nil {
            // The "Settings" hub item is the one whose tag we don't tag; identify by title.
            if item.title == L("menu.settings") {
                item.submenu = buildSettingsMenu()
            }
        }
    }

    // §01 — per-metric submenu
    private func buildTitleContentMenu() -> NSMenu {
        let m = NSMenu()
        let prefs = PrefsStore.shared.prefs
        let metrics: [(String, MetricMode, String, String)] = [
            ("weeklyPctMode",    prefs.weeklyPctMode,    L("label.all_models") + " · %",  prefs.weeklyPctColor),
            ("weeklyTimeMode",   prefs.weeklyTimeMode,   L("section.weekly") + " · " + L("label.usage").lowercased() + " ⏱", prefs.weeklyTimeColor),
            ("fiveHourPctMode",  prefs.fiveHourPctMode,  L("section.five_hour") + " · %", prefs.fiveHourPctColor),
            ("fiveHourTimeMode", prefs.fiveHourTimeMode, L("section.five_hour") + " ⏱",   prefs.fiveHourTimeColor),
        ]
        for (key, mode, displayName, color) in metrics {
            let sub = NSMenuItem(title: displayName, action: nil, keyEquivalent: "")
            sub.submenu = buildMetricSubmenu(key: key, current: mode, currentColor: color)
            m.addItem(sub)
        }
        return m
    }

    private func buildMetricSubmenu(key: String, current: MetricMode, currentColor: String) -> NSMenu {
        let m = NSMenu()
        let modes: [(MetricMode, String)] = [
            (.hidden, L("mode.hidden")),
            (.text,   L("mode.text")),
            (.donut,  L("mode.donut")),
        ]
        for (mode, label) in modes {
            let it = NSMenuItem(title: label, action: #selector(setMetricMode(_:)), keyEquivalent: "")
            it.representedObject = ["key": key, "mode": mode.rawValue]
            it.state = (mode == current) ? .on : .off
            m.addItem(it)
        }
        // Color submenu only when donut
        if current == .donut {
            m.addItem(NSMenuItem.separator())
            let colorSub = NSMenuItem(title: L("mode.color"), action: nil, keyEquivalent: "")
            colorSub.submenu = buildColorMenu(key: key, current: currentColor)
            m.addItem(colorSub)
        }
        return m
    }

    private func buildColorMenu(key: String, current: String) -> NSMenu {
        let m = NSMenu()
        let palette: [(String, String)] = [
            ("#d68c45", L("color.amber")),
            ("#5dc97f", L("color.green")),
            ("#d4c25a", L("color.yellow")),
            ("#d6645a", L("color.red")),
            ("#a87fd6", L("color.purple")),
            ("#7fb8b8", L("color.teal")),
            ("#f4eee3", L("color.white")),
            ("#8a8378", L("color.gray")),
        ]
        for (hex, name) in palette {
            let it = NSMenuItem(title: "● " + name, action: #selector(setMetricColor(_:)), keyEquivalent: "")
            it.representedObject = ["key": key, "color": hex]
            it.state = (hex == current) ? .on : .off
            // tint the bullet
            let attr = NSMutableAttributedString(string: "●  ", attributes: [.foregroundColor: NSColor(hex: hex)])
            attr.append(NSAttributedString(string: name))
            it.attributedTitle = attr
            m.addItem(it)
        }
        return m
    }

    @objc func setMetricMode(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let key = info["key"],
              let modeRaw = info["mode"],
              let mode = MetricMode(rawValue: modeRaw) else { return }
        PrefsStore.shared.update { p in
            switch key {
            case "weeklyPctMode":    p.weeklyPctMode    = mode
            case "weeklyTimeMode":   p.weeklyTimeMode   = mode
            case "fiveHourPctMode":  p.fiveHourPctMode  = mode
            case "fiveHourTimeMode": p.fiveHourTimeMode = mode
            default: break
            }
        }
    }

    @objc func setMetricColor(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let key = info["key"],
              let color = info["color"] else { return }
        PrefsStore.shared.update { p in
            switch key {
            case "weeklyPctMode":    p.weeklyPctColor    = color
            case "weeklyTimeMode":   p.weeklyTimeColor   = color
            case "fiveHourPctMode":  p.fiveHourPctColor  = color
            case "fiveHourTimeMode": p.fiveHourTimeColor = color
            default: break
            }
        }
    }

    // §02 — icon
    private func buildIconMenu() -> NSMenu {
        let m = NSMenu()
        let prefs = PrefsStore.shared.prefs
        let presets = ["🤖", "🧠", "⚡", "✨", "◉", "●", "▲", "◐"]
        for emoji in presets {
            let it = NSMenuItem(title: emoji, action: #selector(setIconEmoji(_:)), keyEquivalent: "")
            it.representedObject = emoji
            if prefs.iconType == .emoji && prefs.iconValue == emoji { it.state = .on }
            m.addItem(it)
        }
        m.addItem(NSMenuItem.separator())
        let custom = NSMenuItem(title: L("icon.custom"), action: #selector(promptCustomIcon), keyEquivalent: "")
        if prefs.iconType == .custom { custom.state = .on }
        m.addItem(custom)
        let donut = NSMenuItem(title: L("icon.donut"), action: #selector(setIconDonut), keyEquivalent: "")
        if prefs.iconType == .donut { donut.state = .on }
        m.addItem(donut)
        let none = NSMenuItem(title: L("icon.none"), action: #selector(setIconNone), keyEquivalent: "")
        if prefs.iconType == .none { none.state = .on }
        m.addItem(none)
        return m
    }

    @objc func setIconEmoji(_ sender: NSMenuItem) {
        guard let emoji = sender.representedObject as? String else { return }
        PrefsStore.shared.update { $0.iconType = .emoji; $0.iconValue = emoji }
    }
    @objc func promptCustomIcon() {
        let alert = NSAlert()
        alert.messageText = L("icon.custom_prompt")
        alert.addButton(withTitle: L("button.ok"))
        alert.addButton(withTitle: L("button.cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        input.font = NSFont.systemFont(ofSize: 20)
        input.alignment = .center
        input.stringValue = PrefsStore.shared.prefs.iconValue
        alert.accessoryView = input
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let v = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty {
                PrefsStore.shared.update { $0.iconType = .custom; $0.iconValue = v }
            }
        }
    }
    @objc func setIconDonut() {
        PrefsStore.shared.update { $0.iconType = .donut; $0.iconValue = "" }
    }
    @objc func setIconNone() {
        PrefsStore.shared.update { $0.iconType = .none; $0.iconValue = "" }
    }

    // §06 — refresh interval
    private func buildRefreshMenu() -> NSMenu {
        let m = NSMenu()
        let cur = PrefsStore.shared.prefs.pollIntervalSec
        let opts: [(Int, String)] = [
            (30,  L("refresh.30s")),
            (60,  L("refresh.1m")),
            (300, L("refresh.5m")),
            (600, L("refresh.10m")),
        ]
        for (sec, label) in opts {
            let it = NSMenuItem(title: label, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            it.representedObject = sec
            if sec == cur { it.state = .on }
            m.addItem(it)
        }
        return m
    }

    @objc func setRefreshInterval(_ sender: NSMenuItem) {
        guard let sec = sender.representedObject as? Int else { return }
        PrefsStore.shared.update { $0.pollIntervalSec = sec }
    }

    // §05 — notifications
    private func buildNotificationsMenu() -> NSMenu {
        let m = NSMenu()
        let p = PrefsStore.shared.prefs
        let enable = NSMenuItem(title: L("notifications.enable"),
                                action: #selector(toggleNotifications), keyEquivalent: "")
        enable.state = p.notificationsEnabled ? .on : .off
        m.addItem(enable)
        m.addItem(NSMenuItem.separator())

        // Threshold submenus
        for (label, current, key) in [
            (L("notifications.warn"),     p.warnThreshold,     "warn"),
            (L("notifications.alert"),    p.alertThreshold,    "alert"),
            (L("notifications.critical"), p.criticalThreshold, "critical"),
        ] {
            let sub = NSMenuItem(title: "\(label): %\(current)", action: nil, keyEquivalent: "")
            sub.submenu = buildThresholdMenu(key: key, current: current)
            m.addItem(sub)
        }
        return m
    }

    private func buildThresholdMenu(key: String, current: Int) -> NSMenu {
        let m = NSMenu()
        let values: [Int]
        switch key {
        case "warn":     values = [25, 33, 40, 50, 60, 70, 80]
        case "alert":    values = [50, 60, 70, 75, 80, 85, 90]
        case "critical": values = [80, 85, 90, 93, 95, 97, 99]
        default:         values = []
        }
        for v in values {
            let it = NSMenuItem(title: "%\(v)", action: #selector(setThreshold(_:)), keyEquivalent: "")
            it.representedObject = ["key": key, "value": v]
            if v == current { it.state = .on }
            m.addItem(it)
        }
        return m
    }

    @objc func toggleNotifications() {
        PrefsStore.shared.update { $0.notificationsEnabled.toggle() }
        if PrefsStore.shared.prefs.notificationsEnabled {
            NotificationManager.shared.ensureAuthorized()
        }
    }

    @objc func setThreshold(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let key = info["key"] as? String,
              let value = info["value"] as? Int else { return }
        PrefsStore.shared.update { p in
            switch key {
            case "warn":     p.warnThreshold     = value
            case "alert":    p.alertThreshold    = value
            case "critical": p.criticalThreshold = value
            default: break
            }
        }
    }

    // §07 — hotkey
    private func buildHotkeyMenu() -> NSMenu {
        let m = NSMenu()
        let p = PrefsStore.shared.prefs
        let toggle = NSMenuItem(title: L("hotkey.enable"),
                                action: #selector(toggleHotkey), keyEquivalent: "")
        toggle.state = p.hotkeyEnabled ? .on : .off
        m.addItem(toggle)
        m.addItem(NSMenuItem.separator())
        let label = HotKeyManager.label(keyCode: p.hotkeyKeyCode, modifiers: p.hotkeyModifiers)
        let info = NSMenuItem(title: L("hotkey.current", label as NSString), action: nil, keyEquivalent: "")
        info.isEnabled = false
        m.addItem(info)
        let hint = NSMenuItem(title: L("hotkey.hint"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        m.addItem(hint)
        return m
    }

    @objc func toggleHotkey() {
        PrefsStore.shared.update { $0.hotkeyEnabled.toggle() }
    }

    // §08 — browsers
    private func buildBrowserMenu() -> NSMenu {
        let m = NSMenu()
        let p = PrefsStore.shared.prefs
        let items: [(String, Bool, String)] = [
            ("🟢 " + L("browser.chrome"), p.browserChromeEnabled, "chrome"),
            ("🦁 " + L("browser.brave"),  p.browserBraveEnabled,  "brave"),
            ("🟦 " + L("browser.edge"),   p.browserEdgeEnabled,   "edge"),
            ("🏹 " + L("browser.arc"),    p.browserArcEnabled,    "arc"),
        ]
        for (label, enabled, id) in items {
            let it = NSMenuItem(title: label, action: #selector(toggleBrowser(_:)), keyEquivalent: "")
            it.representedObject = id
            it.state = enabled ? .on : .off
            m.addItem(it)
        }
        return m
    }

    @objc func toggleBrowser(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        PrefsStore.shared.update { p in
            switch id {
            case "chrome": p.browserChromeEnabled.toggle()
            case "brave":  p.browserBraveEnabled.toggle()
            case "edge":   p.browserEdgeEnabled.toggle()
            case "arc":    p.browserArcEnabled.toggle()
            default: break
            }
        }
    }

    // §09 — version
    @objc func toggleVersionCheck() {
        PrefsStore.shared.update { $0.versionCheckEnabled.toggle() }
    }

    // MARK: - Static menu actions

    @objc func menuRefresh()  { refresh() }
    @objc func menuOpenUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func menuOpenReleases() {
        if let url = URL(string: VersionChecker.releasesURL) {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func menuOpenAuthorSite() {
        if let url = URL(string: "https://www.nurullah.net") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func menuOpenAuthorX() {
        if let url = URL(string: "https://x.com/nurullah") {
            NSWorkspace.shared.open(url)
        }
    }
}
