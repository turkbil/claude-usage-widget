import AppKit

/// Builds the menu bar title from the current UsageSnapshot + Preferences.
/// Returns an NSAttributedString that may contain inline donut images.
enum TitleRenderer {

    /// Map any UI percent into one of our threshold colors.
    static func defaultColorForPercent(_ p: Double) -> NSColor {
        if p >= 90 { return .systemRed }
        if p >= 75 { return .systemOrange }
        if p >= 50 { return .systemYellow }
        return .systemGreen
    }

    /// Compute "elapsed fraction of the period" for a reset date.
    /// We don't know the period start, so approximate from the period length.
    static func elapsedFraction(until resetsAt: Date, periodSeconds: Double) -> Double {
        let remaining = resetsAt.timeIntervalSinceNow
        let elapsed   = periodSeconds - remaining
        return max(0, min(1, elapsed / periodSeconds))
    }

    /// Compose the title attributed string. Returns nil if no snapshot / no content.
    static func compose(snapshot: UsageSnapshot?, prefs: Preferences, error: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()

        // No snapshot yet → loading or error placeholder
        guard let s = snapshot else {
            let text = error ? L("title.error") : L("title.loading")
            out.append(NSAttributedString(string: text))
            return out
        }

        let separator = NSAttributedString(string: " · ", attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor
        ])

        // 1) Icon prefix
        switch prefs.iconType {
        case .emoji, .custom:
            let v = prefs.iconValue.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { out.append(NSAttributedString(string: v)) }
        case .donut:
            let img = DonutImage.make(fill: s.weeklyUtilization / 100, color: NSColor(hex: prefs.weeklyPctColor))
            out.append(attachment(image: img))
        case .none:
            break
        }

        // 2) Each metric in order — hidden / text / donut.
        let weeklyTimeFill = elapsedFraction(until: s.weeklyResetsAt, periodSeconds: 7 * 24 * 3600)
        let fiveTimeFill   = s.fiveHourResetsAt.map { elapsedFraction(until: $0, periodSeconds: 5 * 3600) } ?? 0

        let items: [(mode: MetricMode, kind: ItemKind, color: NSColor)] = [
            (prefs.weeklyPctMode,    .pct(s.weeklyUtilization),                          NSColor(hex: prefs.weeklyPctColor)),
            (prefs.weeklyTimeMode,   .text(formatRemaining(s.weeklyResetsAt), weeklyTimeFill), NSColor(hex: prefs.weeklyTimeColor)),
            (prefs.fiveHourPctMode,  .pctOptional(s.fiveHourUtilization),                NSColor(hex: prefs.fiveHourPctColor)),
            (prefs.fiveHourTimeMode, .timeOptional(s.fiveHourResetsAt, fiveTimeFill),    NSColor(hex: prefs.fiveHourTimeColor)),
        ]

        for (mode, kind, color) in items {
            guard mode != .hidden else { continue }
            guard let fragment = render(kind: kind, mode: mode, color: color) else { continue }
            if out.length > 0 { out.append(separator) }
            out.append(fragment)
        }

        // Color the whole string by threshold of weekly% — but only if there's text,
        // otherwise leave the donut images to render with their own colors.
        let weekly = Int(s.weeklyUtilization.rounded())
        let textColor: NSColor = weekly >= 90 ? .systemRed
                              : weekly >= 75 ? .systemOrange
                              : .labelColor
        out.addAttribute(.foregroundColor, value: textColor,
                         range: NSRange(location: 0, length: out.length))

        // Ensure attachments don't inherit foreground tint.
        return out
    }

    // MARK: - private helpers

    private enum ItemKind {
        case pct(Double)
        case pctOptional(Double?)
        case text(String, Double)              // text + donut fill fraction
        case timeOptional(Date?, Double)
    }

    private static func render(kind: ItemKind, mode: MetricMode, color: NSColor) -> NSAttributedString? {
        switch kind {
        case .pct(let v):
            return rendered(text: formatPercent(Int(v.rounded())), fill: v / 100, mode: mode, color: color)
        case .pctOptional(let opt):
            guard let v = opt else { return nil }
            return rendered(text: formatPercent(Int(v.rounded())), fill: v / 100, mode: mode, color: color)
        case .text(let txt, let fill):
            return rendered(text: txt, fill: fill, mode: mode, color: color)
        case .timeOptional(let opt, let fill):
            guard let d = opt else { return nil }
            return rendered(text: formatRemaining(d), fill: fill, mode: mode, color: color)
        }
    }

    private static func rendered(text: String, fill: Double, mode: MetricMode, color: NSColor) -> NSAttributedString {
        switch mode {
        case .text:
            return NSAttributedString(string: text)
        case .donut:
            return attachment(image: DonutImage.make(fill: fill, color: color))
        case .hidden:
            return NSAttributedString()
        }
    }

    private static func attachment(image: NSImage) -> NSAttributedString {
        let a = NSTextAttachment()
        a.image = image
        // Vertically center against typical 13–14pt font.
        a.bounds = NSRect(x: 0, y: -2, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: a)
    }

    /// Format "%32" or "32%" depending on locale (mirrors Localizable.strings "title.percent").
    private static func formatPercent(_ p: Int) -> String {
        // Strip emoji from the localized format: "🤖 %%%d" or "🤖 %d%%"
        let raw = L("title.percent", p)
        return raw.replacingOccurrences(of: "🤖 ", with: "")
    }
}
