import Cocoa

/// One per-model weekly limit from `/usage` → `limits[]` (kind `weekly_scoped`), e.g. "Fable".
struct ScopedLimit: Codable {
    let name: String
    let pct: Double
    let resetsAt: Date?
}

/// A free limit reset claude.ai hands out (usage?cedar_ember=1 → grants[]),
/// e.g. "One full limit reset (November 2026)". Read-only: the widget never uses one.
struct ResetGrant: Codable {
    let kind: String        // "weekly" | "fable" | "session" | "other"
    let left: Int
    let total: Int
    let endsAt: Date?
}

/// One granted API credit (developer console → prepaid/credits → promo_tranches),
/// e.g. "API credit (Ultra)": $200 granted, $4.42 left, expires 16 Nov.
struct APICredit: Codable {
    let name: String
    let remaining: Double      // USD
    let granted: Double        // USD
    let expiresAt: Date?
}

/// Last-seen state of one claude.ai account. The widget can only read the account
/// that is currently signed in to the browser, so every other account keeps the
/// values from the last time it was signed in (shown as "may be out of date").
struct AccountRecord: Codable {
    var email: String
    var plan: String?
    var weeklyPct: Double?          // used %, nil = unknown
    var weeklyResetsAt: Date?
    var scoped: [ScopedLimit]
    var planEndsAt: Date?           // subscription_details.plan_ending_at
    var planRenews: Bool? = nil     // true = renews that day · false = cancelled · nil = unknown
    var seenAt: Date
    var source: String              // "live" (read by the widget) | "note" (entered by hand)
    var grants: [ResetGrant]? = nil // free resets on hand (nil = never read)
    var grantsSeenAt: Date? = nil   // when the resets above were read (can be older than seenAt)
    var apiTotal: Double? = nil     // developer-console credit balance, USD (nil = never read)
    var apiCredits: [APICredit]? = nil
    var apiSeenAt: Date? = nil      // console data is read only for the account signed in there
    var apiToday: Double? = nil     // API spend on apiTodayKey (UTC day), USD
    var apiTodayKey: String? = nil  // "2026-11-13" — the spend counts only on that day
}

/// What a record means *now*: weekly windows that have passed since the record
/// was taken are rolled forward (the limit must have reset in the meantime).
struct AccountState {
    let record: AccountRecord
    let nextReset: Date?
    let weeklyLeft: Double?         // remaining %, nil = unknown
    let scopedLeft: [(name: String, left: Double)]
    let rolled: Bool                // a reset happened since the record was taken
    let scopedRolled: Bool          // the first scoped (Fable) limit has reset since
    /// Never read by the widget (only typed in by hand): nothing about it is confirmed.
    var neverSignedIn: Bool { record.source == "note" }
    let weeklyResetsLeft: Int?      // weekly resets before the plan ends
    let scopedResetsLeft: Int?      // same for the first scoped (Fable) limit
    let grantsLeft: [ResetGrant]    // unused, unexpired free resets
    var grantCount: Int { grantsLeft.reduce(0) { $0 + $1.left } }
}

enum AccountMath {
    static let week: TimeInterval = 7 * 24 * 3600
    static let hintWindow: TimeInterval = 48 * 3600

    /// Moves `date` forward in whole weeks until it is in the future.
    static func roll(_ date: Date, now: Date) -> (Date, Bool) {
        guard date <= now else { return (date, false) }
        let weeks = floor(now.timeIntervalSince(date) / week) + 1
        return (date.addingTimeInterval(weeks * week), true)
    }

    /// Number of weekly resets from `next` up to and including `end`.
    static func resetsBefore(_ end: Date?, next: Date?) -> Int? {
        guard let end = end, let next = next else { return nil }
        guard next <= end else { return 0 }
        return Int(floor(end.timeIntervalSince(next) / week)) + 1
    }

    static func state(_ r: AccountRecord, now: Date = Date()) -> AccountState {
        // Hand-entered rows are not confirmed: show no numbers until the account signs in once.
        if r.source == "note" {
            return AccountState(record: r, nextReset: nil, weeklyLeft: nil, scopedLeft: [], rolled: false,
                                scopedRolled: false, weeklyResetsLeft: nil, scopedResetsLeft: nil, grantsLeft: [])
        }
        var next: Date? = nil
        var rolled = false
        if let reset = r.weeklyResetsAt { let x = roll(reset, now: now); next = x.0; rolled = x.1 }

        let weeklyLeft: Double? = rolled ? 100 : r.weeklyPct.map { max(0, 100 - $0) }

        var scopedLeft: [(String, Double)] = []
        var scopedNext: Date? = nil
        var scopedRolled = false
        for (i, s) in r.scoped.enumerated() {
            var left = max(0, 100 - s.pct)
            // Fable resets with the weekly window; use its own date when there is one.
            let (n, didRoll) = roll(s.resetsAt ?? r.weeklyResetsAt ?? now.addingTimeInterval(1), now: now)
            if didRoll { left = 100 }
            if i == 0 { scopedNext = n; scopedRolled = didRoll }
            scopedLeft.append((s.name, left))
        }

        return AccountState(
            record: r, nextReset: next, weeklyLeft: weeklyLeft,
            scopedLeft: scopedLeft, rolled: rolled, scopedRolled: scopedRolled,
            // Counting resets "before the end" only means something for a plan that ends.
            weeklyResetsLeft: r.planRenews == true ? nil : resetsBefore(r.planEndsAt, next: next),
            scopedResetsLeft: r.planRenews == true ? nil : resetsBefore(r.planEndsAt, next: scopedNext),
            grantsLeft: (r.grants ?? []).filter { $0.left > 0 && ($0.endsAt.map { $0 > now } ?? true) }
        )
    }

    /// The account whose unused weekly quota is about to be lost: reset within
    /// 48 h and at least 5 % left. Soonest reset wins; ties go to more quota.
    static func suggestion(_ states: [AccountState], now: Date = Date()) -> AccountState? {
        let candidates = states.filter { s in
            guard let next = s.nextReset, let left = s.weeklyLeft else { return false }
            let until = next.timeIntervalSince(now)
            return until > 0 && until <= hintWindow && left >= 5
        }
        return candidates.min { a, b in
            if a.nextReset! != b.nextReset! { return a.nextReset! < b.nextReset! }
            return (a.weeklyLeft ?? 0) > (b.weeklyLeft ?? 0)
        }
    }
}

/// Persists every account seen on this Mac in ~/.claude-usage-widget-accounts.json.
final class AccountStore {
    static let shared = AccountStore()
    static let path = NSString("~/.claude-usage-widget-accounts.json").expandingTildeInPath

    private(set) var records: [AccountRecord] = []

    /// Accounts the user removed from the list. Kept by e-mail so they stay hidden
    /// even after signing in to them again; "show hidden accounts" brings them back.
    private static let hiddenKey = "hiddenAccounts"
    var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.hiddenKey) }
    }
    func hide(_ email: String) { hidden.insert(email.lowercased()) }
    /// Deletes the stored record. Unlike hide, the account comes back on its next sign-in.
    func remove(_ email: String) {
        let e = email.lowercased()
        records.removeAll { $0.email == e }
        hidden.remove(e)
        save()
    }
    func unhideAll() { hidden = [] }

    private init() { load() }

    func upsert(_ snap: UsageSnapshot) {
        guard let email = snap.email?.lowercased(), !email.isEmpty else { return }
        let rec = AccountRecord(
            email: email, plan: snap.planLabel,
            weeklyPct: snap.weeklyUtilization, weeklyResetsAt: snap.weeklyResetsAt,
            scoped: snap.scopedLimits, planEndsAt: snap.planEndsAt ?? records.first { $0.email == email }?.planEndsAt,
            planRenews: snap.planRenews ?? records.first { $0.email == email }?.planRenews,
            seenAt: snap.fetchedAt, source: "live",
            // Not read this time → keep the last known resets and their date (never turn them into 0).
            grants: snap.grants ?? records.first { $0.email == email }?.grants,
            grantsSeenAt: snap.grants != nil ? snap.fetchedAt : records.first { $0.email == email }?.grantsSeenAt,
            apiTotal: records.first { $0.email == email }?.apiTotal,
            apiCredits: records.first { $0.email == email }?.apiCredits,
            apiSeenAt: records.first { $0.email == email }?.apiSeenAt,
            apiToday: records.first { $0.email == email }?.apiToday,
            apiTodayKey: records.first { $0.email == email }?.apiTodayKey
        )
        if let i = records.firstIndex(where: { $0.email == email }) { records[i] = rec }
        else { records.append(rec) }
        save()
    }

    /// Console credits of the account signed in at platform.claude.com (may be a
    /// different account than the one signed in at claude.ai).
    func upsertAPI(email: String, total: Double, credits: [APICredit], today: Double?, at: Date) {
        let e = email.lowercased()
        if records.firstIndex(where: { $0.email == e }) == nil {
            records.append(AccountRecord(email: e, plan: nil, weeklyPct: nil, weeklyResetsAt: nil, scoped: [],
                                         planEndsAt: nil, seenAt: at, source: "live"))
        }
        let i = records.firstIndex(where: { $0.email == e })!
        records[i].apiTotal = total; records[i].apiCredits = credits; records[i].apiSeenAt = at
        if let t = today { records[i].apiToday = t; records[i].apiTodayKey = utcDayKey(at) }
        save()
    }

    /// Today's API spend summed over every account whose spend was read today.
    func apiTodayTotal(now: Date = Date()) -> (sum: Double, accounts: Int) {
        let key = utcDayKey(now)
        let rs = records.filter { $0.apiTodayKey == key && !hidden.contains($0.email) }
        return (rs.reduce(0) { $0 + ($1.apiToday ?? 0) }, rs.count)
    }

    /// "Use next" order: accounts with quota left by soonest reset, then full ones,
    /// then accounts with no data.
    func states(now: Date = Date()) -> [AccountState] {
        func group(_ s: AccountState) -> Int {
            guard let l = s.weeklyLeft else { return 2 }
            return l >= 5 ? 0 : 1
        }
        let hiddenNow = hidden
        return records.filter { !hiddenNow.contains($0.email) }.map { AccountMath.state($0, now: now) }.sorted { a, b in
            if group(a) != group(b) { return group(a) < group(b) }
            return (a.nextReset ?? .distantFuture) < (b.nextReset ?? .distantFuture)
        }
    }

    /// Accounts are shown by their full e-mail: several share the part before @
    /// but live on different domains.
    func shortName(_ email: String) -> String { email }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        records = (try? dec.decode([AccountRecord].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(records) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.path))
    }
}

// MARK: - Text helpers

/// "Pzt 16:00" — weekday + time of the weekly reset, in the user's locale.
func weekdayTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE HH:mm")
    // resets_at can be …:59:59.9 — round to the nearest minute so it reads 14:00, not 13:59.
    return f.string(from: Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 60).rounded() * 60))
}

/// "2026-11-13" — the console's cost report uses UTC days.
func utcDayKey(_ d: Date) -> String {
    let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

/// "$4,42" in the user's locale.
func money(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = v >= 100 ? 0 : 2
    return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
}

/// "13 Kas 01:59"
func dayTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
    return f.string(from: d)
}

/// "13 Kas"
func shortDay(_ d: Date) -> String {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("d MMM")
    return f.string(from: d)
}

/// "şimdi" · "25dk önce" · "3s önce" · "2g önce"
func ageText(_ d: Date, now: Date = Date()) -> String {
    let s = max(0, now.timeIntervalSince(d))
    if s < 120 { return L("accounts.now") }
    if s < 3600 { return L("accounts.ago", L("time.minutes", Int(s / 60)) as NSString) }
    if s < 86400 { return L("accounts.ago", L("time.hours_short", Int(s / 3600)) as NSString) }
    return L("accounts.ago", L("time.days_short", Int(s / 86400)) as NSString)
}

/// "1 haftalık · son 11 Ara, 3 Fable · son 9 Mar" — grouped by kind, with the
/// earliest expiry of each kind (the one to use first).
func grantText(_ grants: [ResetGrant]) -> String {
    var order: [String] = []
    var count: [String: Int] = [:], first: [String: Date] = [:]
    for g in grants {
        if count[g.kind] == nil { order.append(g.kind) }
        count[g.kind, default: 0] += g.left
        if let e = g.endsAt, first[g.kind].map({ e < $0 }) ?? true { first[g.kind] = e }
    }
    return order.map { k in
        let kind = L("grant." + k, count[k] ?? 0)
        return first[k].map { kind + " · " + L("grant.until", shortDay($0) as NSString) } ?? kind
    }.joined(separator: ", ")
}

/// Same thresholds as the usage bars at the top (UsageRowView).
func usedColor(_ p: Double) -> NSColor {
    if p >= 90 { return .systemRed }
    if p >= 75 { return .systemOrange }
    if p >= 50 { return .systemYellow }
    return .systemGreen
}


// MARK: - Views

/// Column grid shared by the accounts header and every account row, so the
/// column titles sit exactly over their values.
struct AccountColumns {
    static let gap: CGFloat = 10
    /// Fixed slot for the "●" current-account mark, so every name starts at the same x.
    static let markW: CGFloat = 14
    static let barW: CGFloat = 48, pctW: CGFloat = 46, resetW: CGFloat = 70, planW: CGFloat = 52
    let name, bar, pct, fpct, reset, plan: (x: CGFloat, w: CGFloat)
    /// Expanded free-reset sub-row: weekly under bar+KALAN, Fable under SIFIRLAMA+AYLIK.
    let weekly, fable: (x: CGFloat, w: CGFloat)
    init(width: CGFloat) {
        let x0 = Layout.hPad, end = width - Layout.hPad, g = Self.gap
        plan  = (end - Self.planW, Self.planW)
        reset = (plan.x - g - Self.resetW, Self.resetW)
        fpct  = (reset.x - g - Self.pctW, Self.pctW)     // Fable % left, next to the weekly one
        pct   = (fpct.x - g - Self.pctW, Self.pctW)
        bar   = (pct.x - g - Self.barW, Self.barW)
        name  = (x0, bar.x - g - x0)
        weekly = (bar.x, pct.x + pct.w - bar.x)
        fable  = (reset.x, end - reset.x)
    }
}

/// Column titles: HESAPLAR · KALAN · SIFIRLAMA · BİTİŞ
final class AccountsHeaderView: NSView {
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.headerHeight))
        autoresizingMask = [.width]
        let c = AccountColumns(width: width)
        func title(_ key: String, _ col: (x: CGFloat, w: CGFloat), right: Bool, strong: Bool = false) {
            let f = NSTextField(labelWithString: L(key))
            f.font = .systemFont(ofSize: 10, weight: .heavy)
            f.textColor = strong ? .secondaryLabelColor : .tertiaryLabelColor
            f.alignment = right ? .right : .left
            f.lineBreakMode = .byClipping
            f.frame = NSRect(x: col.x, y: 8, width: col.w, height: 14)
            addSubview(f)
        }
        title("section.accounts", c.name, right: false, strong: true)
        title("col.left", c.pct, right: true)
        title("col.fable", c.fpct, right: true)
        title("col.reset", c.reset, right: true)
        title("col.plan", c.plan, right: true)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// One-line row: name · bar · % left · reset day/time · plan end. Details in the tooltip.
final class AccountRowView: NSView {
    static let height: CGFloat = 26
    private let name  = NSTextField(labelWithString: "")
    private let bar   = ProgressBarView(frame: .zero)
    private let left  = NSTextField(labelWithString: "")
    private let reset = NSTextField(labelWithString: "")
    private let plan  = NSTextField(labelWithString: "")   // end of the paid month
    private let mark  = NSTextField(labelWithString: "")   // "●" on the signed-in account, empty otherwise
    private let fable = NSTextField(labelWithString: "")   // Fable % left
    private var isCurrentRow = false
    var onClick: (() -> Void)?

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        let c = AccountColumns(width: width)

        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        mark.font = .systemFont(ofSize: 8)
        mark.textColor = .labelColor
        mark.frame = NSRect(x: c.name.x, y: 6, width: AccountColumns.markW, height: 14)
        addSubview(mark)
        name.frame = NSRect(x: c.name.x + AccountColumns.markW, y: 5,
                            width: c.name.w - AccountColumns.markW, height: 16)

        bar.frame = NSRect(x: c.bar.x, y: 10.5, width: c.bar.w, height: 5)

        left.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        left.alignment = .right
        left.frame = NSRect(x: c.pct.x, y: 5, width: c.pct.w, height: 16)

        reset.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        reset.alignment = .right
        reset.lineBreakMode = .byClipping
        reset.frame = NSRect(x: c.reset.x, y: 5, width: c.reset.w, height: 16)

        plan.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        plan.alignment = .right
        plan.lineBreakMode = .byClipping
        plan.frame = NSRect(x: c.plan.x, y: 5, width: c.plan.w, height: 16)

        fable.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        fable.alignment = .right
        fable.lineBreakMode = .byClipping
        fable.frame = NSRect(x: c.fpct.x, y: 5, width: c.fpct.w, height: 16)

        [name, bar, left, fable, reset, plan].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ s: AccountState, isCurrent: Bool, shortName: String) {
        let r = s.record
        let ending = r.planRenews == false && (r.planEndsAt.map { $0 > Date() } ?? false)
        isCurrentRow = isCurrent
        // The signed-in account gets a soft band so it stands out in the list.
        wantsLayer = true
        setBand()
        let nameFont = NSFont.systemFont(ofSize: 12, weight: isCurrent ? .bold : .medium)
        name.font = nameFont
        // Signed-out accounts are dimmed: their numbers are from the last sign-in.
        // Truncate, never wrap: a wrapped name vanished below the row.
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        mark.stringValue = isCurrent ? "●" : ""
        name.attributedStringValue = NSAttributedString(string: shortName, attributes: [
            .font: nameFont, .paragraphStyle: para,
            .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor])

        // Fable % used; "*" = its window has reset since the last read (back to 0).
        if let f = s.scopedLeft.first {
            let used = 100 - f.left
            fable.stringValue = "%\(Int(used.rounded()))" + (s.scopedRolled ? "*" : "")
            fable.textColor = usedColor(used)
        } else {
            fable.stringValue = "—"; fable.textColor = .tertiaryLabelColor
        }

        // Monthly date: plain when it renews (or unknown), orange when the plan
        // is cancelled and really ends that day, faint once the date has passed.
        if s.neverSignedIn {
            plan.stringValue = "—"; plan.textColor = .tertiaryLabelColor
        } else if let end = r.planEndsAt {
            plan.stringValue = shortDay(end)
            plan.textColor = end < Date() ? .tertiaryLabelColor : (ending ? .systemOrange : .secondaryLabelColor)
        } else {
            plan.stringValue = "—"
            plan.textColor = .tertiaryLabelColor
        }

        // Used %, like the bars at the top (otherwise the same account read %3 above, %97 here).
        if let l = s.weeklyLeft {
            let used = 100 - l
            bar.progress = used / 100
            bar.fillColor = usedColor(used).withAlphaComponent(isCurrent ? 1 : 0.7)
            left.stringValue = "%\(Int(used.rounded()))" + (s.rolled ? "*" : "")
            left.textColor = usedColor(used)
        } else {
            bar.progress = 0
            left.stringValue = "—"
            left.textColor = .tertiaryLabelColor
        }

        if let n = s.nextReset {
            // Within two days the countdown matters more than the weekday.
            reset.stringValue = weekdayTime(n)
            reset.textColor = .secondaryLabelColor
        } else {
            // Never read: say so instead of guessing ("giriş yapılmadı").
            reset.stringValue = L("accounts.not_signed_in")
            reset.textColor = .tertiaryLabelColor
        }
        // "giriş yapılmadı" is longer than a day/time: let it use the AYLIK cell too.
        let c = AccountColumns(width: bounds.width)
        let wide = s.neverSignedIn || s.nextReset == nil
        reset.frame.size.width = wide ? (c.plan.x + c.plan.w - c.reset.x) : c.reset.w
        plan.isHidden = wide

        toolTip = Self.details(s, isCurrent: isCurrent)
    }

    private func setBand(hover: Bool = false) {
        let a: CGFloat = hover ? 0.12 : (isCurrentRow ? 0.07 : 0)
        layer?.backgroundColor = a > 0 ? NSColor.labelColor.withAlphaComponent(a).cgColor : nil
    }

    // Click → onClick (asks whether to remove the account from the list).
    override func mouseUp(with event: NSEvent) {
        guard let action = onClick else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: action)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { setBand(hover: true) }
    override func mouseExited(with event: NSEvent)  { setBand() }

    static func details(_ s: AccountState, isCurrent: Bool) -> String {
        let r = s.record
        var lines = [r.email]
        if let n = s.nextReset {
            let pct = s.weeklyLeft.map { "%\(Int($0.rounded()))" } ?? "—"
            lines.append(L("tip.weekly", pct as NSString, weekdayTime(n) as NSString, formatRemaining(n) as NSString))
        }
        for f in s.scopedLeft { lines.append(L("tip.scoped", f.name as NSString, Int(f.left.rounded()))) }
        if !s.grantsLeft.isEmpty { lines.append(L("detail.grants") + ": " + grantText(s.grantsLeft)) }
        if let end = r.planEndsAt, r.planRenews == true {
            lines.append(L("detail.renews") + " " + shortDay(end))
        } else if let end = r.planEndsAt {
            var bits = [L(r.planRenews == false ? "tip.plan_ends" : "accounts.plan_until", shortDay(end) as NSString)]
            if end < Date() { bits.append(L("accounts.plan_passed")) }
            else if let w = s.weeklyResetsLeft {
                if let f = s.scopedResetsLeft, f != w, let nm = s.scopedLeft.first?.name {
                    bits.append(L("accounts.resets_split", w, nm as NSString, f))
                } else { bits.append(L("accounts.resets", w)) }
            }
            lines.append(bits.joined(separator: " · "))
        }
        lines.append(L("tip.seen", (isCurrent ? L("accounts.now") : ageText(r.seenAt)) as NSString))
        if s.rolled { lines.append(L("tip.rolled")) }
        lines.append(L("tip.remove"))
        if r.source == "note" { lines.append(L("accounts.tip_note")) }
        else if !isCurrent { lines.append(L("tip.refresh")) }
        return lines.joined(separator: "\n")
    }
}

/// Wrapping orange/grey note line used for the 48-hour hint and the staleness note.
final class NoteView: NSView {
    let field = NSTextField(wrappingLabelWithString: "")
    init(width: CGFloat, height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.frame = NSRect(x: Layout.hPad, y: 3, width: width - Layout.hPad * 2, height: height - 6)
        field.autoresizingMask = [.width]
        field.maximumNumberOfLines = 4
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// One label–value pair in the current-account details block.
struct DetailRow {
    let label: String
    let value: String
    var color: NSColor = .labelColor
}

/// "Sıfırlama ········ Pzt 16:00" rows: label on the left, value on the right,
/// the same alignment as the usage rows above.
final class DetailsView: NSView {
    static let rowHeight: CGFloat = 19
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        autoresizingMask = [.width]
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ rows: [DetailRow]) {
        subviews.forEach { $0.removeFromSuperview() }
        let h = CGFloat(rows.count) * Self.rowHeight + 8
        frame.size.height = h
        let w = bounds.width, inner = w - Layout.hPad * 2
        for (i, r) in rows.enumerated() {
            let y = h - 4 - CGFloat(i + 1) * Self.rowHeight + 2
            let label = NSTextField(labelWithString: r.label)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: Layout.hPad, y: y, width: 110, height: 15)
            let value = NSTextField(labelWithString: r.value)
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = r.color
            value.alignment = .right
            value.lineBreakMode = .byTruncatingTail
            value.frame = NSRect(x: Layout.hPad + 112, y: y, width: inner - 112, height: 15)
            value.autoresizingMask = [.width]
            addSubview(label); addSubview(value)
        }
    }
}

/// "▸ Sıfırlama haklarını göster" — clicking toggles without closing the menu.
final class ToggleRowView: NSView {
    private let field = NSTextField(labelWithString: "")
    var onToggle: (() -> Void)?
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        autoresizingMask = [.width]
        wantsLayer = true
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .secondaryLabelColor
        field.frame = NSRect(x: Layout.hPad, y: 4, width: width - Layout.hPad * 2, height: 16)
        field.autoresizingMask = [.width]
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(expanded: Bool) {
        field.stringValue = (expanded ? "▾ " : "▸ ") + L(expanded ? "grants.hide" : "grants.show")
    }
    override func mouseUp(with event: NSEvent) { onToggle?() }   // menu stays open
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor }
    override func mouseExited(with event: NSEvent)  { layer?.backgroundColor = nil }
}

/// Free resets of one kind: total on hand and the earliest expiry.
func grantSummary(_ grants: [ResetGrant], kind: String) -> (count: Int, first: Date?) {
    let g = grants.filter { $0.kind == kind }
    return (g.reduce(0) { $0 + $1.left }, g.compactMap { $0.endsAt }.min())
}

/// Shared look of the two sub-row cells ("↺ 1 · son 11 Ara").
private func grantCell() -> NSTextField {
    let f = NSTextField(labelWithString: "")
    f.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    f.lineBreakMode = .byTruncatingTail
    return f
}

/// "↺ HAFTALIK HAK · ↺ FABLE HAKKI" — titles of the expanded sub-rows, on the same grid.
final class GrantHeaderView: NSView {
    private let total = NSTextField(labelWithString: "")   // "BUGÜN API $1,20 · 2 hesap"
    func update() {
        let t = AccountStore.shared.apiTodayTotal()
        total.stringValue = t.accounts == 0 ? "" : L("api.today_total", money(t.sum) as NSString, t.accounts)
    }
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 18))
        autoresizingMask = [.width]
        let c = AccountColumns(width: width)
        // Today's API spend of all accounts. (Row labels live under each account now.)
        total.font = .systemFont(ofSize: 10, weight: .heavy)
        total.textColor = NSColor(hex: "#d68c45")
        total.lineBreakMode = .byTruncatingTail
        total.frame = NSRect(x: c.name.x + AccountColumns.markW, y: 2, width: width - Layout.hPad - c.name.x - AccountColumns.markW, height: 14)
        addSubview(total)
        update()
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The table line under an account when free resets are expanded:
/// weekly cell | Fable cell — "↺ 1 · son 11 Ara" · "0" · "bilinmiyor".
final class GrantDetailView: NSView {
    static let rowH: CGFloat = 16
    private var labels: [NSTextField] = []
    private var values: [NSTextField] = []
    private let width: CGFloat
    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 4 * Self.rowH + 8))
        autoresizingMask = [.width]
        let c = AccountColumns(width: width)
        // Labels in the empty space under the account name, values from the bar column on.
        for _ in 0..<4 {
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: 11)
            l.textColor = .tertiaryLabelColor
            l.lineBreakMode = .byTruncatingTail
            let v = grantCell()
            l.frame = NSRect(x: c.name.x + AccountColumns.markW, y: 0, width: c.name.w - AccountColumns.markW, height: 14)
            v.frame = NSRect(x: c.bar.x, y: 0, width: width - Layout.hPad - c.bar.x, height: 14)
            addSubview(l); addSubview(v)
            labels.append(l); values.append(v)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func set(_ i: Int, _ label: String, _ value: String, _ color: NSColor) {
        // Rows from the top; the space below separates the next account.
        let y = frame.height - CGFloat(i + 1) * Self.rowH
        labels[i].frame.origin.y = y; values[i].frame.origin.y = y
        labels[i].stringValue = label; values[i].stringValue = value; values[i].textColor = color
    }

    /// " · bugün $1,20" — only when the spend was read today.
    private func todayText(_ r: AccountRecord) -> String {
        guard r.apiTodayKey == utcDayKey(Date()), let t = r.apiToday else { return "" }
        return " · " + L("api.today", money(t) as NSString)
    }

    func update(_ s: AccountState, isCurrent: Bool) {
        let r = s.record
        let orange = NSColor(hex: "#d68c45")
        for (i, kind, key) in [(0, "weekly", "grants.row_weekly"), (1, "fable", "grants.row_fable")] {
            guard r.grants != nil else { set(i, L(key), L("grants.unknown_short"), .tertiaryLabelColor); continue }
            let (n, first) = grantSummary(s.grantsLeft, kind: kind)
            if n == 0 { set(i, L(key), "0", .tertiaryLabelColor) }
            else { set(i, L(key), "↺ \(n)" + (first.map { " · " + L("grant.until", shortDay($0) as NSString) } ?? ""), orange) }
        }

        if r.apiTotal == nil {
            set(2, L("grants.row_api"), L("api.unknown"), .tertiaryLabelColor)
        } else if let cr = r.apiCredits?.filter({ $0.expiresAt.map { $0 > Date() } ?? true }), !cr.isEmpty {
            let left = cr.reduce(0) { $0 + $1.remaining }, granted = cr.reduce(0) { $0 + $1.granted }
            let first = cr.compactMap { $0.expiresAt }.min()
            let soon = first.map { $0.timeIntervalSinceNow < 3 * 86400 } ?? false
            set(2, L("grants.row_api"),
                L("api.credit", money(left) as NSString, money(granted) as NSString)
                    + (first.map { " · " + L("grant.until", shortDay($0) as NSString) } ?? "") + todayText(r),
                soon ? .systemRed : orange)
        } else {
            set(2, L("grants.row_api"), L("api.balance", money(r.apiTotal ?? 0) as NSString) + todayText(r),
                (r.apiTotal ?? 0) > 0 ? .labelColor : .tertiaryLabelColor)
        }

        // Last read, separately: resets come from claude.ai, credits from the console.
        func when(_ d: Date) -> String { Date().timeIntervalSince(d) < 180 ? L("accounts.now") : dayTime(d) }
        if s.neverSignedIn && r.apiSeenAt == nil {
            set(3, L("grants.row_seen"), L("accounts.never_read"), .tertiaryLabelColor)
        } else {
            var bits: [String] = []
            if !s.neverSignedIn { bits.append(L("grants.seen_resets", when(r.grantsSeenAt ?? r.seenAt) as NSString)) }
            if let a = r.apiSeenAt { bits.append(L("grants.seen_api", when(a) as NSString)) }
            set(3, L("grants.row_seen"), bits.joined(separator: " · "), .tertiaryLabelColor)
        }

        toolTip = s.grantsLeft.isEmpty ? nil : s.grantsLeft.map { g in
            L("grant." + g.kind, g.left) + (g.endsAt.map { " · " + L("grant.until", shortDay($0) as NSString) } ?? "")
        }.joined(separator: "\n")
    }
}
