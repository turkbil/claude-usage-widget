import Cocoa
import SQLite3
import Security
import CommonCrypto

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

// MARK: - Config

struct AppConfig {
    static let pollIntervalSec: TimeInterval = 60
    static let chromeCookiesPath = NSString("~/Library/Application Support/Google/Chrome/Default/Cookies").expandingTildeInPath
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

// MARK: - Chrome Cookie Decryption

struct ChromeCookieReader {
    /// Returns the decrypted sessionKey cookie for .claude.ai
    static func sessionKey() throws -> String {
        let tmp = NSTemporaryDirectory() + "claude_widget_cookies_\(UUID().uuidString).db"
        try? FileManager.default.removeItem(atPath: tmp)
        do {
            try FileManager.default.copyItem(atPath: AppConfig.chromeCookiesPath, toPath: tmp)
        } catch {
            throw WidgetError.message(L("error.cookie_db"))
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open(tmp, &db) == SQLITE_OK else {
            throw WidgetError.message(L("error.cookie_db"))
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name='sessionKey' ORDER BY length(encrypted_value) DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw WidgetError.message(L("error.cookie_db"))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw WidgetError.message(L("error.no_session"))
        }
        guard let blobPtr = sqlite3_column_blob(stmt, 0) else {
            throw WidgetError.message(L("error.no_session"))
        }
        let blobLen = Int(sqlite3_column_bytes(stmt, 0))
        let encrypted = Data(bytes: blobPtr, count: blobLen)

        let password = try keychainPassword(service: "Chrome Safe Storage", account: "Chrome")
        let key = try pbkdf2(password: password, salt: "saltysalt", rounds: 1003, keyLen: 16)

        guard encrypted.count > 3 else { throw WidgetError.message(L("error.cookie_decrypt")) }
        let prefix = String(data: encrypted.prefix(3), encoding: .utf8) ?? ""
        guard prefix == "v10" || prefix == "v11" else {
            throw WidgetError.message(L("error.unknown_cookie_version", prefix as NSString))
        }
        let ct = encrypted.suffix(from: 3)
        let iv = Data(repeating: 0x20, count: 16)
        let plain = try aesCBCDecrypt(Data(ct), key: key, iv: iv)

        // Newer Chrome versions prepend a 32-byte SHA-256 hash to the plaintext.
        // Skip those leading bytes if they aren't printable ASCII, and trim any
        // trailing non-printable bytes (PKCS7 padding remnants).
        let bytes = [UInt8](plain)
        var start = 0
        if bytes.count > 32 {
            let head = bytes[0..<32]
            if head.contains(where: { $0 < 0x20 || $0 >= 0x7F }) { start = 32 }
        }
        var end = bytes.count
        while end > start && (bytes[end-1] < 0x20 || bytes[end-1] >= 0x7F) { end -= 1 }
        guard end > start else { throw WidgetError.message(L("error.cookie_empty")) }

        let printable = bytes[start..<end].filter { $0 >= 0x20 && $0 < 0x7F }
        let result = String(bytes: printable, encoding: .ascii) ?? ""
        guard !result.isEmpty else { throw WidgetError.message(L("error.cookie_empty")) }
        return result
    }

    static func keychainPassword(service: String, account: String) throws -> String {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw WidgetError.message(L("error.keychain_denied"))
        }
        guard status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            throw WidgetError.message(L("error.keychain_read", Int(status)))
        }
        return s
    }

    static func pbkdf2(password: String, salt: String, rounds: Int, keyLen: Int) throws -> Data {
        let passData = password.data(using: .utf8)!
        let saltData = salt.data(using: .utf8)!
        var derived = Data(count: keyLen)
        let status = derived.withUnsafeMutableBytes { (db: UnsafeMutableRawBufferPointer) -> Int32 in
            passData.withUnsafeBytes { (pb: UnsafeRawBufferPointer) -> Int32 in
                saltData.withUnsafeBytes { (sb: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pb.bindMemory(to: Int8.self).baseAddress, passData.count,
                        sb.bindMemory(to: UInt8.self).baseAddress, saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(rounds),
                        db.bindMemory(to: UInt8.self).baseAddress, keyLen
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw WidgetError.message(L("error.cookie_decrypt")) }
        return derived
    }

    static func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        let outCapacity = data.count + kCCBlockSizeAES128
        var out = Data(count: outCapacity)
        var outLen = 0
        let status = out.withUnsafeMutableBytes { (ob: UnsafeMutableRawBufferPointer) -> Int32 in
            data.withUnsafeBytes { (ib: UnsafeRawBufferPointer) -> Int32 in
                key.withUnsafeBytes { (kb: UnsafeRawBufferPointer) -> Int32 in
                    iv.withUnsafeBytes { (vb: UnsafeRawBufferPointer) -> Int32 in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            kb.baseAddress, key.count,
                            vb.baseAddress,
                            ib.baseAddress, data.count,
                            ob.baseAddress, outCapacity,
                            &outLen
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw WidgetError.message(L("error.cookie_decrypt")) }
        out.count = outLen
        return out
    }
}

// MARK: - API

struct UsageSnapshot {
    let weeklyUtilization: Double      // 0..100
    let weeklyResetsAt: Date
    let fiveHourUtilization: Double?
    let fiveHourResetsAt: Date?
    let sonnetUtilization: Double?
    let displayName: String?
    let planLabel: String?
    let fetchedAt: Date
}

/// Maps Anthropic's internal plan tier IDs to friendly labels.
/// Examples:
///   "default_claude_max_20x" → "Max 20x"
///   "default_claude_max_5x"  → "Max 5x"
///   "default_claude_pro"     → "Pro"
///   "default_free"           → "Free"
func prettyPlanName(_ tier: String) -> String {
    var s = tier.lowercased()
    s = s.replacingOccurrences(of: "default_claude_", with: "")
    s = s.replacingOccurrences(of: "default_", with: "")
    let parts = s.split(separator: "_").map(String.init)
    let pretty = parts.map { p -> String in
        switch p {
        case "max", "pro", "team", "free", "enterprise": return p.capitalized
        default: return p  // keep e.g. "20x", "5x" as-is
        }
    }
    return pretty.joined(separator: " ")
}

struct ClaudeAPI {
    static func fetchSnapshot() throws -> UsageSnapshot {
        let cookie = try ChromeCookieReader.sessionKey()
        let orgId = try findOrgId(cookie: cookie)

        // Account & plan are non-fatal: snapshot still works if either fails.
        let displayName: String? = try? fetchDisplayName(cookie: cookie)
        let planLabel: String? = try? fetchPlanLabel(cookie: cookie, orgId: orgId)

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
            weeklyUtilization: weeklyUtil,
            weeklyResetsAt: weeklyResets,
            fiveHourUtilization: fiveUtil,
            fiveHourResetsAt: fiveResets,
            sonnetUtilization: sonnetUtil,
            displayName: displayName,
            planLabel: planLabel,
            fetchedAt: Date()
        )
    }

    static func fetchDisplayName(cookie: String) throws -> String {
        let json = try getJSON("/api/account", cookie: cookie)
        guard let dict = json as? [String: Any] else { throw WidgetError.message(L("error.api_parse")) }
        if let n = dict["display_name"] as? String, !n.isEmpty { return n }
        if let n = dict["full_name"] as? String, !n.isEmpty { return n }
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
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 ClaudeUsageWidget", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultStatus: Int = 0
        var resultErr: Error?
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            resultData = data
            resultErr = err
            if let http = resp as? HTTPURLResponse { resultStatus = http.statusCode }
            sem.signal()
        }
        task.resume()
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

// MARK: - Formatting

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

func formatPercent(_ pct: Int, withTime time: String?) -> String {
    if let t = time {
        return L("title.percent_with_time", pct, t as NSString)
    }
    return L("title.percent", pct)
}

// MARK: - Custom Views

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
            // Use the localized "percent only" title format to get the value text,
            // then strip the emoji prefix.
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
    var statusItem: NSStatusItem!
    var timer: Timer?
    var lastSnapshot: UsageSnapshot?
    var lastError: String?
    var lastUpdate: Date = Date(timeIntervalSince1970: 0)

    var accountHeader: AccountHeaderView!
    var accountSeparator: NSMenuItem?
    var weeklyHeader: SectionHeaderView!
    var allModelsRow: UsageRowView!
    var sonnetRow: UsageRowView!
    var fiveHourHeader: SectionHeaderView!
    var fiveHourRow: UsageRowView!
    var footer: FooterView!
    let menuWidth: CGFloat = 300

    var showRemainingInTitle: Bool {
        get { UserDefaults.standard.bool(forKey: "showRemainingInTitle") }
        set { UserDefaults.standard.set(newValue, forKey: "showRemainingInTitle") }
    }

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

        timer = Timer.scheduledTimer(withTimeInterval: AppConfig.pollIntervalSec, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateTitle()
            self?.updateMenuLabels()
        }
    }

    // MARK: Persistence

    func loadCache() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: AppConfig.cachePath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wu = dict["weeklyUtilization"] as? Double,
              let wr = dict["weeklyResetsAt"] as? String,
              let wrDate = ClaudeAPI.parseISO(wr) else { return }
        lastSnapshot = UsageSnapshot(
            weeklyUtilization: wu,
            weeklyResetsAt: wrDate,
            fiveHourUtilization: dict["fiveHourUtilization"] as? Double,
            fiveHourResetsAt: (dict["fiveHourResetsAt"] as? String).flatMap(ClaudeAPI.parseISO),
            sonnetUtilization: dict["sonnetUtilization"] as? Double,
            displayName: dict["displayName"] as? String,
            planLabel: dict["planLabel"] as? String,
            fetchedAt: (dict["fetchedAt"] as? String).flatMap(ClaudeAPI.parseISO) ?? Date()
        )
        updateTitle()
        updateMenuLabels()
    }

    func saveCache(_ s: UsageSnapshot) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var dict: [String: Any] = [
            "weeklyUtilization": s.weeklyUtilization,
            "weeklyResetsAt": iso.string(from: s.weeklyResetsAt),
            "fetchedAt": iso.string(from: s.fetchedAt),
        ]
        if let v = s.fiveHourUtilization { dict["fiveHourUtilization"] = v }
        if let d = s.fiveHourResetsAt { dict["fiveHourResetsAt"] = iso.string(from: d) }
        if let v = s.sonnetUtilization { dict["sonnetUtilization"] = v }
        if let n = s.displayName { dict["displayName"] = n }
        if let p = s.planLabel { dict["planLabel"] = p }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: AppConfig.cachePath))
        }
    }

    // MARK: Menu

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
        let toggle = NSMenuItem(title: L("menu.show_remaining_in_title"), action: #selector(menuToggleRemaining), keyEquivalent: "")
        toggle.tag = 104
        toggle.state = showRemainingInTitle ? .on : .off
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("menu.refresh"), action: #selector(menuRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: L("menu.open_usage"), action: #selector(menuOpenUsage), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func updateMenuLabels() {
        guard weeklyHeader != nil else { return }

        // Account header
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
                fiveHourRow.isHidden = true
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

    // MARK: Title

    func updateTitle() {
        guard let button = statusItem.button else { return }
        guard let s = lastSnapshot else {
            button.title = L("title.loading")
            return
        }
        let pct = Int(s.weeklyUtilization.rounded())
        let remaining = formatRemaining(s.weeklyResetsAt)
        let title = formatPercent(pct, withTime: showRemainingInTitle ? remaining : nil)
        let color: NSColor = pct >= 90 ? .systemRed : (pct >= 75 ? .systemOrange : .labelColor)
        button.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: color])
        button.toolTip = L("tooltip", pct, remaining as NSString)
    }

    // MARK: Actions

    @objc func menuRefresh() { refresh() }
    @objc func menuToggleRemaining() {
        showRemainingInTitle.toggle()
        if let item = statusItem.menu?.item(withTag: 104) {
            item.state = showRemainingInTitle ? .on : .off
        }
        updateTitle()
    }
    @objc func menuOpenUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Refresh

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let snap = try ClaudeAPI.fetchSnapshot()
                DispatchQueue.main.async {
                    self.lastSnapshot = snap
                    self.lastError = nil
                    self.lastUpdate = Date()
                    self.saveCache(snap)
                    self.updateTitle()
                    self.updateMenuLabels()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.updateMenuLabels()
                    if self.lastSnapshot == nil, let button = self.statusItem.button {
                        button.attributedTitle = NSAttributedString(string: L("title.error"), attributes: [.foregroundColor: NSColor.systemRed])
                    }
                }
            }
        }
    }
}
