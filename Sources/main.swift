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

        let displayName: String? = try? fetchDisplayName(cookie: cookie)
        let planLabel:   String? = try? fetchPlanLabel(cookie: cookie, orgId: orgId)

        let json = try getJSON("/api/organizations/\(orgId)/usage", cookie: cookie)

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

        return UsageSnapshot(
            weeklyUtilization:   weeklyUtil,
            weeklyResetsAt:      weeklyResets,
            fiveHourUtilization: fiveUtil,
            fiveHourResetsAt:    fiveResets,
            sonnetUtilization:   sonnetUtil,
            displayName:         displayName,
            planLabel:           planLabel,
            fetchedAt:           Date()
        )
    }

    static func fetchDisplayName(cookie: String) throws -> String {
        let json = try getJSON("/api/account", cookie: cookie)
        guard let dict = json as? [String: Any] else { throw WidgetError.message(L("error.api_parse")) }
        if let n = dict["display_name"] as? String, !n.isEmpty { return n }
        if let n = dict["full_name"]    as? String, !n.isEmpty { return n }
        if let e = dict["email_address"] as? String, !e.isEmpty { return e }
        throw WidgetError.message(L("error.api_parse"))
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

final class FooterView: NSView {
    let field = NSTextField(labelWithString: "")
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.footerHeight))
        autoresizingMask = [.width]
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .tertiaryLabelColor
        field.alignment = .center
        field.frame = NSRect(x: Layout.hPad, y: 6, width: width - Layout.hPad*2, height: 14)
        field.autoresizingMask = [.width]
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ s: String) { field.stringValue = s }
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
    var fiveHourHeader: SectionHeaderView!
    var fiveHourRow: UsageRowView!
    var footer: FooterView!
    let menuWidth: CGFloat = 300

    // Menu items that need live updating
    var versionUpdateItem: NSMenuItem?
    var versionUpdateSeparator: NSMenuItem?

    static func main() {
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
        }

        // React to preference changes from any settings menu.
        NotificationCenter.default.addObserver(forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.handlePrefsChanged()
        }

        // Wire global hotkey.
        applyHotkey()

        // Version check on launch (fires only if due).
        VersionChecker.shared.checkIfDue()
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
            fetchedAt:           (dict["fetchedAt"] as? String).flatMap(ClaudeAPI.parseISO) ?? Date()
        )
        updateTitle()
        updateMenuLabels()
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
                    self.lastSnapshot = snap
                    self.lastError    = nil
                    self.lastUpdate   = Date()
                    self.saveCache(snap)
                    self.updateTitle()
                    self.updateMenuLabels()
                    NotificationManager.shared.evaluate(snapshot: snap)
                    VersionChecker.shared.checkIfDue()
                    self.refreshVersionBadge()
                }
            } catch {
                DispatchQueue.main.async {
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
        button.attributedTitle = attr
        if let s = lastSnapshot {
            let pct = Int(s.weeklyUtilization.rounded())
            button.toolTip = L("tooltip", pct, formatRemaining(s.weeklyResetsAt) as NSString)
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
        let sonnetItem = NSMenuItem(); sonnetItem.view = sonnetRow
        menu.addItem(sonnetItem)

        menu.addItem(NSMenuItem.separator())

        fiveHourHeader = SectionHeaderView(width: menuWidth)
        let fiveHourHeaderItem = NSMenuItem(); fiveHourHeaderItem.view = fiveHourHeader
        menu.addItem(fiveHourHeaderItem)

        fiveHourRow = UsageRowView(width: menuWidth)
        let fiveHourItem = NSMenuItem(); fiveHourItem.view = fiveHourRow
        menu.addItem(fiveHourItem)

        menu.addItem(NSMenuItem.separator())

        footer = FooterView(width: menuWidth)
        let footerItem = NSMenuItem(); footerItem.view = footer
        menu.addItem(footerItem)

        menu.addItem(NSMenuItem.separator())

        // Settings submenu hub
        let settingsItem = NSMenuItem(title: L("menu.settings"), action: nil, keyEquivalent: ",")
        settingsItem.submenu = buildSettingsMenu()
        menu.addItem(settingsItem)

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

        // Credit footer (§10)
        menu.addItem(NSMenuItem.separator())
        let creditAuthor = NSMenuItem(title: L("credit.author") + " ↗",
                                      action: #selector(menuOpenAuthorSite), keyEquivalent: "")
        creditAuthor.attributedTitle = creditAttributed(L("credit.author") + " ↗")
        menu.addItem(creditAuthor)

        let creditX = NSMenuItem(title: L("credit.handle") + " ↗",
                                 action: #selector(menuOpenAuthorX), keyEquivalent: "")
        creditX.attributedTitle = creditAttributed(L("credit.handle") + " ↗")
        menu.addItem(creditX)

        statusItem.menu = menu
    }

    private func creditAttributed(_ s: String) -> NSAttributedString {
        return NSAttributedString(string: s, attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .font: NSFont.systemFont(ofSize: 11),
        ])
    }

    func updateMenuLabels() {
        guard weeklyHeader != nil else { return }

        if let s = lastSnapshot, (s.displayName != nil || s.planLabel != nil) {
            accountHeader.update(name: s.displayName, plan: s.planLabel)
            accountHeader.isHidden = false
            accountSeparator?.isHidden = false
        } else {
            accountHeader.isHidden = true
            accountSeparator?.isHidden = true
        }

        if let s = lastSnapshot {
            weeklyHeader.update(L("section.weekly"), trailing: remainingWithSuffix(s.weeklyResetsAt))
            allModelsRow.update(label: L("label.all_models"), percent: s.weeklyUtilization)
            if let sonnet = s.sonnetUtilization {
                sonnetRow.update(label: L("label.sonnet"), percent: sonnet)
                sonnetRow.isHidden = false
            } else {
                sonnetRow.isHidden = true
            }

            if let u = s.fiveHourUtilization, let r = s.fiveHourResetsAt {
                fiveHourHeader.update(L("section.five_hour"), trailing: remainingWithSuffix(r))
                fiveHourRow.update(label: L("label.usage"), percent: u)
                fiveHourRow.isHidden = false
                fiveHourHeader.isHidden = false
            } else {
                fiveHourHeader.isHidden = true
                fiveHourRow.isHidden    = true
            }
        } else {
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

        return m
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
