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
    var seenAt: Date
    var source: String              // "live" (read by the widget) | "note" (entered by hand)
    var grants: [ResetGrant]? = nil // free resets on hand (nil in records from before v1.5)
}

/// What a record means *now*: weekly windows that have passed since the record
/// was taken are rolled forward (the limit must have reset in the meantime).
struct AccountState {
    let record: AccountRecord
    let nextReset: Date?
    let weeklyLeft: Double?         // remaining %, nil = unknown
    let scopedLeft: [(name: String, left: Double)]
    let rolled: Bool                // a reset happened since the record was taken
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
        var next: Date? = nil
        var rolled = false
        if let reset = r.weeklyResetsAt { let x = roll(reset, now: now); next = x.0; rolled = x.1 }

        let weeklyLeft: Double? = rolled ? 100 : r.weeklyPct.map { max(0, 100 - $0) }

        var scopedLeft: [(String, Double)] = []
        var scopedNext: Date? = nil
        for (i, s) in r.scoped.enumerated() {
            var left = max(0, 100 - s.pct)
            if let ra = s.resetsAt {
                let (n, didRoll) = roll(ra, now: now)
                if didRoll { left = 100 }
                if i == 0 { scopedNext = n }
            }
            scopedLeft.append((s.name, left))
        }

        return AccountState(
            record: r, nextReset: next, weeklyLeft: weeklyLeft,
            scopedLeft: scopedLeft, rolled: rolled,
            weeklyResetsLeft: resetsBefore(r.planEndsAt, next: next),
            scopedResetsLeft: resetsBefore(r.planEndsAt, next: scopedNext),
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

    private init() { load() }

    func upsert(_ snap: UsageSnapshot) {
        guard let email = snap.email?.lowercased(), !email.isEmpty else { return }
        let rec = AccountRecord(
            email: email, plan: snap.planLabel,
            weeklyPct: snap.weeklyUtilization, weeklyResetsAt: snap.weeklyResetsAt,
            scoped: snap.scopedLimits, planEndsAt: snap.planEndsAt ?? records.first { $0.email == email }?.planEndsAt,
            seenAt: snap.fetchedAt, source: "live", grants: snap.grants
        )
        if let i = records.firstIndex(where: { $0.email == email }) { records[i] = rec }
        else { records.append(rec) }
        save()
    }

    /// "Use next" order: accounts with quota left by soonest reset, then full ones,
    /// then accounts with no data.
    func states(now: Date = Date()) -> [AccountState] {
        func group(_ s: AccountState) -> Int {
            guard let l = s.weeklyLeft else { return 2 }
            return l >= 5 ? 0 : 1
        }
        return records.map { AccountMath.state($0, now: now) }.sorted { a, b in
            if group(a) != group(b) { return group(a) < group(b) }
            return (a.nextReset ?? .distantFuture) < (b.nextReset ?? .distantFuture)
        }
    }

    /// "claude2" — the part before @, or the full address when two accounts share it.
    func shortName(_ email: String) -> String {
        let local = String(email.split(separator: "@").first ?? Substring(email))
        let clash = records.filter { $0.email.split(separator: "@").first.map(String.init) == local }.count > 1
        return clash ? email : local
    }

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

/// "1 haftalık · son 11 Ara" for each kind of free reset on hand.
func grantText(_ grants: [ResetGrant]) -> String {
    grants.map { g in
        let kind = L("grant." + g.kind, g.left)
        return g.endsAt.map { kind + " · " + L("grant.until", shortDay($0) as NSString) } ?? kind
    }.joined(separator: ", ")
}

func leftColor(_ left: Double) -> NSColor {
    if left <= 10 { return .systemRed }
    if left <= 25 { return .systemOrange }
    if left <= 50 { return .systemYellow }
    return .systemGreen
}

// MARK: - Views

/// Column grid shared by the accounts header and every account row, so the
/// column titles sit exactly over their values.
struct AccountColumns {
    static let gap: CGFloat = 10
    static let barW: CGFloat = 56, pctW: CGFloat = 46, resetW: CGFloat = 70, planW: CGFloat = 52
    let name, bar, pct, reset, plan: (x: CGFloat, w: CGFloat)
    init(width: CGFloat) {
        let x0 = Layout.hPad, end = width - Layout.hPad, g = Self.gap
        plan  = (end - Self.planW, Self.planW)
        reset = (plan.x - g - Self.resetW, Self.resetW)
        pct   = (reset.x - g - Self.pctW, Self.pctW)
        bar   = (pct.x - g - Self.barW, Self.barW)
        name  = (x0, bar.x - g - x0)
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
    private var isCurrentRow = false

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        let c = AccountColumns(width: width)

        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: c.name.x, y: 5, width: c.name.w, height: 16)

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

        [name, bar, left, reset, plan].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ s: AccountState, isCurrent: Bool, shortName: String) {
        let r = s.record
        let lastWeek = (s.weeklyResetsLeft == 0) && (r.planEndsAt.map { $0 > Date() } ?? false)
        isCurrentRow = isCurrent
        // The signed-in account gets a soft band so it stands out in the list.
        wantsLayer = true
        setBand()
        let nameFont = NSFont.systemFont(ofSize: 12, weight: isCurrent ? .bold : .medium)
        name.font = nameFont
        // Signed-out accounts are dimmed: their numbers are from the last sign-in.
        let label = NSMutableAttributedString(string: (isCurrent ? "● " : "") + shortName, attributes: [
            .font: nameFont, .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor])
        if s.grantCount > 0 {   // ↺1 = free resets on hand
            label.append(NSAttributedString(string: " ↺\(s.grantCount)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor(hex: "#d68c45")]))
        }
        name.attributedStringValue = label

        // Monthly date: orange when the plan ends before the next weekly reset
        // (last week of the subscription), faint when the date has passed.
        if let end = r.planEndsAt {
            plan.stringValue = shortDay(end)
            plan.textColor = end < Date() ? .tertiaryLabelColor : (lastWeek ? .systemOrange : .secondaryLabelColor)
        } else {
            plan.stringValue = "—"
            plan.textColor = .tertiaryLabelColor
        }

        if let l = s.weeklyLeft {
            bar.progress = l / 100
            bar.fillColor = leftColor(l).withAlphaComponent(isCurrent ? 1 : 0.7)
            left.stringValue = "%\(Int(l.rounded()))" + (s.rolled ? "*" : "")
            left.textColor = leftColor(l)
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
            reset.stringValue = L("accounts.sign_in")
            reset.textColor = .tertiaryLabelColor
        }

        toolTip = Self.details(s, isCurrent: isCurrent)
    }

    private func setBand() {
        layer?.backgroundColor = isCurrentRow ? NSColor.labelColor.withAlphaComponent(0.07).cgColor : nil
    }

    static func details(_ s: AccountState, isCurrent: Bool) -> String {
        let r = s.record
        var lines = [r.email]
        if let n = s.nextReset {
            let pct = s.weeklyLeft.map { "%\(Int($0.rounded()))" } ?? "—"
            lines.append(L("tip.weekly", pct as NSString, weekdayTime(n) as NSString, formatRemaining(n) as NSString))
        }
        for f in s.scopedLeft { lines.append(L("tip.scoped", f.name as NSString, Int(f.left.rounded()))) }
        if !s.grantsLeft.isEmpty { lines.append(L("detail.grants") + ": " + grantText(s.grantsLeft)) }
        if let end = r.planEndsAt {
            var bits = [L("accounts.plan_until", shortDay(end) as NSString)]
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
