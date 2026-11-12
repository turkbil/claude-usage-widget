import Cocoa

/// One per-model weekly limit from `/usage` → `limits[]` (kind `weekly_scoped`), e.g. "Fable".
struct ScopedLimit: Codable {
    let name: String
    let pct: Double
    let resetsAt: Date?
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
            scopedResetsLeft: resetsBefore(r.planEndsAt, next: scopedNext)
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
            seenAt: snap.fetchedAt, source: "live"
        )
        if let i = records.firstIndex(where: { $0.email == email }) { records[i] = rec }
        else { records.append(rec) }
        save()
    }

    /// Current account first, then the rest by soonest reset.
    func states(currentEmail: String?, now: Date = Date()) -> [AccountState] {
        let cur = currentEmail?.lowercased()
        return records.map { AccountMath.state($0, now: now) }.sorted { a, b in
            if a.record.email == cur { return true }
            if b.record.email == cur { return false }
            return (a.nextReset ?? .distantFuture) < (b.nextReset ?? .distantFuture)
        }
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

func leftColor(_ left: Double) -> NSColor {
    if left <= 10 { return .systemRed }
    if left <= 25 { return .systemOrange }
    if left <= 50 { return .systemYellow }
    return .systemGreen
}

// MARK: - Views

/// Three-line row for one account in the "Accounts" section.
final class AccountRowView: NSView {
    static let height: CGFloat = 54
    private let email = NSTextField(labelWithString: "")
    private let left  = NSTextField(labelWithString: "")
    private let reset = NSTextField(labelWithString: "")
    private let scoped = NSTextField(labelWithString: "")
    private let plan  = NSTextField(labelWithString: "")
    private let age   = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        let inner = width - Layout.hPad * 2
        func place(_ f: NSTextField, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
                   color: NSColor, right: Bool, mono: Bool = false) {
            f.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
                          : .systemFont(ofSize: size, weight: weight)
            f.textColor = color
            f.lineBreakMode = .byTruncatingTail
            f.alignment = right ? .right : .left
            // The bottom line (plan · resets) is long and its right-hand age is short.
            let rightW: CGFloat = y < 10 ? 58 : 110
            f.frame = right ? NSRect(x: width - Layout.hPad - rightW, y: y, width: rightW, height: 15)
                            : NSRect(x: Layout.hPad, y: y, width: inner - rightW - 4, height: 15)
            f.autoresizingMask = right ? [.minXMargin] : [.width]
            addSubview(f)
        }
        place(email,  y: 34, size: 12, weight: .semibold, color: .labelColor, right: false)
        place(left,   y: 34, size: 12, weight: .semibold, color: .secondaryLabelColor, right: true, mono: true)
        place(reset,  y: 19, size: 11, weight: .regular, color: .secondaryLabelColor, right: false, mono: true)
        place(scoped, y: 19, size: 11, weight: .regular, color: .secondaryLabelColor, right: true, mono: true)
        place(plan,   y: 4,  size: 10, weight: .regular, color: .tertiaryLabelColor, right: false)
        place(age,    y: 4,  size: 10, weight: .regular, color: .tertiaryLabelColor, right: true)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ s: AccountState, isCurrent: Bool) {
        let r = s.record
        email.stringValue = (isCurrent ? "● " : "") + r.email

        if let l = s.weeklyLeft {
            left.stringValue = L("accounts.left", Int(l.rounded())) + (s.rolled ? "*" : "")
            left.textColor = leftColor(l)
        } else {
            left.stringValue = "—"
            left.textColor = .tertiaryLabelColor
        }

        if let n = s.nextReset {
            reset.stringValue = "↻ " + weekdayTime(n) + " · " + formatRemaining(n)
        } else {
            reset.stringValue = L("accounts.no_data")
        }

        if let f = s.scopedLeft.first {
            scoped.stringValue = L("accounts.scoped_left", f.name as NSString, Int(f.left.rounded()))
        } else {
            scoped.stringValue = ""
        }

        var planBits: [String] = []
        if let end = r.planEndsAt {
            planBits.append(L("accounts.plan_until", shortDay(end) as NSString))
            if end < Date() {
                planBits.append(L("accounts.plan_passed"))
            } else if let w = s.weeklyResetsLeft {
                if let f = s.scopedResetsLeft, f != w, let name = s.scopedLeft.first?.name {
                    planBits.append(L("accounts.resets_split", w, name as NSString, f))
                } else {
                    planBits.append(L("accounts.resets", w))
                }
            }
        }
        plan.stringValue = planBits.joined(separator: " · ")
        age.stringValue = isCurrent ? L("accounts.now") : ageText(r.seenAt)
        toolTip = r.source == "note" ? L("accounts.tip_note") : nil
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
