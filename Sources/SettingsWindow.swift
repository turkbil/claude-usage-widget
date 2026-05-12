import AppKit

/// Single settings window. Vertical-scroll only, fixed width, grid-aligned rows.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    // Window/content size
    private let windowWidth: CGFloat  = 620
    private let windowHeight: CGFloat = 680
    private let hPad: CGFloat = 28

    // Tracked controls for refresh
    private var titleRows: [TitleRowView] = []
    private var iconButtons: [NSButton] = []
    private var customEmojiField: NSTextField?
    private var refreshButtons: [NSButton] = []
    private var notifEnabledCheckbox: NSButton?
    private var warnSlider, alertSlider, criticalSlider: NSSlider?
    private var warnValue, alertValue, criticalValue: NSTextField?
    private var hotkeyEnabledCheckbox: NSButton?
    private var browserCheckboxes: [NSButton] = []
    private var versionCheckCheckbox: NSButton?
    private var localApiCheckbox: NSButton?

    private init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = L("settings.title")
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        w.delegate = self
        w.contentView = makeRoot()

        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged),
            name: .preferencesChanged, object: nil
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refreshAllControls()
    }

    @objc private func prefsChanged() { refreshAllControls() }

    // MARK: - Root layout (scroll + stack)

    private func makeRoot() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        root.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: root.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 26
        stack.edgeInsets = NSEdgeInsets(top: 22, left: hPad, bottom: 28, right: hPad)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Add sections
        stack.addArrangedSubview(makeTitleContentSection())
        stack.addArrangedSubview(makeIconSection())
        stack.addArrangedSubview(makeRefreshSection())
        stack.addArrangedSubview(makeNotificationsSection())
        stack.addArrangedSubview(makeHotkeySection())
        stack.addArrangedSubview(makeBrowsersSection())
        stack.addArrangedSubview(makeNetworkSection())

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalToConstant: windowWidth),
        ])

        scroll.documentView = doc
        root.addSubview(scroll)
        return root
    }

    // MARK: - Section scaffolding

    private func makeSection(title: String, body: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .heavy)
        titleLabel.textColor = .secondaryLabelColor

        let rule = NSBox()
        rule.boxType = .separator

        let head = NSStackView(views: [titleLabel, rule])
        head.orientation = .vertical
        head.alignment = .leading
        head.spacing = 8
        head.distribution = .fill
        rule.widthAnchor.constraint(equalTo: head.widthAnchor).isActive = true

        let container = NSStackView(views: [head, body])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 14
        container.distribution = .fill
        return container
    }

    // MARK: §01 Title content

    private func makeTitleContentSection() -> NSView {
        titleRows.removeAll()
        let metrics: [(String, String)] = [
            ("weeklyPctMode",    L("metric.weekly_pct")),
            ("weeklyTimeMode",   L("metric.weekly_time")),
            ("fiveHourPctMode",  L("metric.five_pct")),
            ("fiveHourTimeMode", L("metric.five_time")),
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        for (key, label) in metrics {
            let row = TitleRowView(metricKey: key, label: label, contentWidth: windowWidth - 2 * hPad)
            titleRows.append(row)
            stack.addArrangedSubview(row)
        }
        return makeSection(title: L("menu.title_content"), body: stack)
    }

    // MARK: §02 Icon

    private func makeIconSection() -> NSView {
        iconButtons.removeAll()
        let presets = ["🤖", "🧠", "⚡", "✨", "◉", "●", "▲", "◐"]

        let grid = NSStackView()
        grid.orientation = .horizontal
        grid.spacing = 8
        for emoji in presets {
            let b = NSButton(title: emoji, target: self, action: #selector(pickEmoji(_:)))
            b.bezelStyle = .smallSquare
            b.setButtonType(.toggle)
            b.identifier = NSUserInterfaceItemIdentifier("emoji:\(emoji)")
            b.font = NSFont.systemFont(ofSize: 18)
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
            iconButtons.append(b)
            grid.addArrangedSubview(b)
        }

        // Custom emoji row
        let customRadio = NSButton(radioButtonWithTitle: L("icon.custom"),
                                   target: self, action: #selector(toggleCustomIcon(_:)))
        customRadio.identifier = NSUserInterfaceItemIdentifier("icon:custom")
        iconButtons.append(customRadio)

        let customField = NSTextField(string: "")
        customField.placeholderString = "🪐"
        customField.target = self
        customField.action = #selector(updateCustomEmoji(_:))
        customField.font = NSFont.systemFont(ofSize: 16)
        customField.alignment = .center
        customField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        customField.heightAnchor.constraint(equalToConstant: 24).isActive = true
        customEmojiField = customField

        let customRow = NSStackView(views: [customRadio, customField])
        customRow.orientation = .horizontal
        customRow.spacing = 10

        let donut = NSButton(radioButtonWithTitle: L("icon.donut"),
                             target: self, action: #selector(pickIconDonut))
        donut.identifier = NSUserInterfaceItemIdentifier("icon:donut")
        iconButtons.append(donut)

        let none = NSButton(radioButtonWithTitle: L("icon.none"),
                            target: self, action: #selector(pickIconNone))
        none.identifier = NSUserInterfaceItemIdentifier("icon:none")
        iconButtons.append(none)

        let body = NSStackView(views: [grid, customRow, donut, none])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        return makeSection(title: L("menu.icon"), body: body)
    }

    // MARK: §06 Refresh

    private func makeRefreshSection() -> NSView {
        refreshButtons.removeAll()
        let opts: [(Int, String)] = [
            (30,  L("refresh.30s")),
            (60,  L("refresh.1m")),
            (300, L("refresh.5m")),
            (600, L("refresh.10m")),
        ]
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 18
        for (sec, label) in opts {
            let b = NSButton(radioButtonWithTitle: label,
                             target: self, action: #selector(pickRefresh(_:)))
            b.tag = sec
            refreshButtons.append(b)
            row.addArrangedSubview(b)
        }
        return makeSection(title: L("menu.refresh_interval"), body: row)
    }

    // MARK: §05 Notifications

    private func makeNotificationsSection() -> NSView {
        let enable = NSButton(checkboxWithTitle: L("notifications.enable"),
                              target: self, action: #selector(toggleNotifications(_:)))
        notifEnabledCheckbox = enable

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 12
        body.addArrangedSubview(enable)

        let sliderContentWidth = windowWidth - 2 * hPad

        func sliderRow(name: String, action: Selector, dotColor: NSColor, min: Double, max: Double)
            -> (row: NSView, slider: NSSlider, value: NSTextField)
        {
            let dot = NSTextField(labelWithString: "●")
            dot.textColor = dotColor
            dot.font = NSFont.systemFont(ofSize: 10)
            dot.widthAnchor.constraint(equalToConstant: 12).isActive = true

            let label = NSTextField(labelWithString: name)
            label.font = NSFont.systemFont(ofSize: 12)
            label.widthAnchor.constraint(equalToConstant: 72).isActive = true

            let s = NSSlider(value: 50, minValue: min, maxValue: max,
                             target: self, action: action)
            s.controlSize = .small
            // Slider expands to fill remaining width

            let val = NSTextField(labelWithString: "%50")
            val.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            val.textColor = .labelColor
            val.alignment = .right
            val.widthAnchor.constraint(equalToConstant: 48).isActive = true

            let row = NSStackView(views: [dot, label, s, val])
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            row.distribution = .fill
            // Force slider to expand by giving the row a fixed total width
            row.widthAnchor.constraint(equalToConstant: sliderContentWidth).isActive = true
            // Slider takes flexible space
            s.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return (row, s, val)
        }

        let warn     = sliderRow(name: L("notifications.warn"),
                                 action: #selector(setWarn(_:)),
                                 dotColor: .systemYellow, min: 20, max: 80)
        let alert    = sliderRow(name: L("notifications.alert"),
                                 action: #selector(setAlert(_:)),
                                 dotColor: .systemOrange, min: 50, max: 95)
        let critical = sliderRow(name: L("notifications.critical"),
                                 action: #selector(setCritical(_:)),
                                 dotColor: .systemRed, min: 70, max: 99)

        warnSlider = warn.slider; alertSlider = alert.slider; criticalSlider = critical.slider
        warnValue = warn.value;   alertValue = alert.value;   criticalValue = critical.value

        body.addArrangedSubview(warn.row)
        body.addArrangedSubview(alert.row)
        body.addArrangedSubview(critical.row)

        return makeSection(title: L("menu.notifications"), body: body)
    }

    // MARK: §07 Hotkey

    private func makeHotkeySection() -> NSView {
        let enable = NSButton(checkboxWithTitle: L("hotkey.enable"),
                              target: self, action: #selector(toggleHotkey(_:)))
        hotkeyEnabledCheckbox = enable
        let p = PrefsStore.shared.prefs
        let labelText = HotKeyManager.label(keyCode: p.hotkeyKeyCode, modifiers: p.hotkeyModifiers)
        let current = NSTextField(labelWithString: L("hotkey.current", labelText as NSString))
        current.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        current.textColor = .secondaryLabelColor

        let body = NSStackView(views: [enable, current])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        return makeSection(title: L("menu.hotkey"), body: body)
    }

    // MARK: §08 Browsers

    private func makeBrowsersSection() -> NSView {
        browserCheckboxes.removeAll()
        let items: [(id: String, label: String)] = [
            ("chrome", "🟢 " + L("browser.chrome")),
            ("brave",  "🦁 " + L("browser.brave")),
            ("edge",   "🟦 " + L("browser.edge")),
            ("arc",    "🏹 " + L("browser.arc")),
        ]
        // Two-column grid
        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 24
        var rowViews: [NSView] = []
        for item in items {
            let b = NSButton(checkboxWithTitle: item.label,
                             target: self, action: #selector(toggleBrowser(_:)))
            b.identifier = NSUserInterfaceItemIdentifier("browser:\(item.id)")
            browserCheckboxes.append(b)
            rowViews.append(b)
        }
        // Layout 2 columns × 2 rows
        grid.addRow(with: [rowViews[0], rowViews[1]])
        grid.addRow(with: [rowViews[2], rowViews[3]])
        return makeSection(title: L("menu.browsers"), body: grid)
    }

    // MARK: §09 Network

    private func makeNetworkSection() -> NSView {
        let ver = NSButton(checkboxWithTitle: L("menu.version_check"),
                           target: self, action: #selector(toggleVersionCheck(_:)))
        versionCheckCheckbox = ver

        let api = NSButton(checkboxWithTitle: L("menu.local_http"),
                           target: self, action: #selector(toggleLocalHTTP(_:)))
        localApiCheckbox = api

        let mcpBtn = NSButton(title: L("menu.mcp_install"),
                              target: self, action: #selector(showMCPInstall))
        mcpBtn.bezelStyle = .rounded

        let body = NSStackView(views: [ver, api, mcpBtn])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        return makeSection(title: L("menu.network"), body: body)
    }

    // MARK: - Refresh state from prefs

    private func refreshAllControls() {
        let p = PrefsStore.shared.prefs
        for row in titleRows { row.refresh() }
        for b in iconButtons {
            guard let id = b.identifier?.rawValue else { continue }
            if id.hasPrefix("emoji:") {
                let e = String(id.dropFirst("emoji:".count))
                b.state = (p.iconType == .emoji && p.iconValue == e) ? .on : .off
            } else if id == "icon:custom" {
                b.state = (p.iconType == .custom) ? .on : .off
            } else if id == "icon:donut" {
                b.state = (p.iconType == .donut) ? .on : .off
            } else if id == "icon:none" {
                b.state = (p.iconType == .none) ? .on : .off
            }
        }
        if p.iconType == .custom { customEmojiField?.stringValue = p.iconValue }
        for b in refreshButtons { b.state = (b.tag == p.pollIntervalSec) ? .on : .off }
        notifEnabledCheckbox?.state = p.notificationsEnabled ? .on : .off
        warnSlider?.doubleValue = Double(p.warnThreshold)
        warnValue?.stringValue  = "%\(p.warnThreshold)"
        alertSlider?.doubleValue = Double(p.alertThreshold)
        alertValue?.stringValue  = "%\(p.alertThreshold)"
        criticalSlider?.doubleValue = Double(p.criticalThreshold)
        criticalValue?.stringValue  = "%\(p.criticalThreshold)"
        hotkeyEnabledCheckbox?.state = p.hotkeyEnabled ? .on : .off
        for b in browserCheckboxes {
            let key = String((b.identifier?.rawValue ?? "").dropFirst("browser:".count))
            switch key {
            case "chrome": b.state = p.browserChromeEnabled ? .on : .off
            case "brave":  b.state = p.browserBraveEnabled  ? .on : .off
            case "edge":   b.state = p.browserEdgeEnabled   ? .on : .off
            case "arc":    b.state = p.browserArcEnabled    ? .on : .off
            default: break
            }
        }
        versionCheckCheckbox?.state = p.versionCheckEnabled ? .on : .off
        localApiCheckbox?.state     = p.localApiEnabled     ? .on : .off
    }

    // MARK: - Actions

    @objc func pickEmoji(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("emoji:") else { return }
        PrefsStore.shared.update {
            $0.iconType  = .emoji
            $0.iconValue = String(id.dropFirst("emoji:".count))
        }
    }
    @objc func toggleCustomIcon(_ sender: NSButton) {
        if sender.state == .on {
            let v = customEmojiField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
            PrefsStore.shared.update { $0.iconType = .custom; $0.iconValue = v.isEmpty ? "🪐" : v }
        }
    }
    @objc func updateCustomEmoji(_ sender: NSTextField) {
        let v = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { PrefsStore.shared.update { $0.iconType = .custom; $0.iconValue = v } }
    }
    @objc func pickIconDonut() { PrefsStore.shared.update { $0.iconType = .donut; $0.iconValue = "" } }
    @objc func pickIconNone()  { PrefsStore.shared.update { $0.iconType = .none;  $0.iconValue = "" } }

    @objc func pickRefresh(_ sender: NSButton) {
        PrefsStore.shared.update { $0.pollIntervalSec = sender.tag }
    }
    @objc func toggleNotifications(_ sender: NSButton) {
        PrefsStore.shared.update { $0.notificationsEnabled = (sender.state == .on) }
        if sender.state == .on { NotificationManager.shared.ensureAuthorized() }
    }
    @objc func setWarn(_ s: NSSlider) {
        let v = Int(s.doubleValue.rounded())
        warnValue?.stringValue = "%\(v)"
        PrefsStore.shared.update { $0.warnThreshold = v }
    }
    @objc func setAlert(_ s: NSSlider) {
        let v = Int(s.doubleValue.rounded())
        alertValue?.stringValue = "%\(v)"
        PrefsStore.shared.update { $0.alertThreshold = v }
    }
    @objc func setCritical(_ s: NSSlider) {
        let v = Int(s.doubleValue.rounded())
        criticalValue?.stringValue = "%\(v)"
        PrefsStore.shared.update { $0.criticalThreshold = v }
    }
    @objc func toggleHotkey(_ sender: NSButton) {
        PrefsStore.shared.update { $0.hotkeyEnabled = (sender.state == .on) }
    }
    @objc func toggleBrowser(_ sender: NSButton) {
        let key = String((sender.identifier?.rawValue ?? "").dropFirst("browser:".count))
        let on = (sender.state == .on)
        PrefsStore.shared.update { p in
            switch key {
            case "chrome": p.browserChromeEnabled = on
            case "brave":  p.browserBraveEnabled  = on
            case "edge":   p.browserEdgeEnabled   = on
            case "arc":    p.browserArcEnabled    = on
            default: break
            }
        }
    }
    @objc func toggleVersionCheck(_ sender: NSButton) {
        PrefsStore.shared.update { $0.versionCheckEnabled = (sender.state == .on) }
    }
    @objc func toggleLocalHTTP(_ sender: NSButton) {
        PrefsStore.shared.update { $0.localApiEnabled = (sender.state == .on) }
    }
    @objc func showMCPInstall() {
        let alert = NSAlert()
        alert.messageText = L("mcp.install_title")
        alert.informativeText = L("mcp.install_body",
            (Bundle.main.executablePath ?? "/path/to/ClaudeUsageWidget") as NSString)
        alert.addButton(withTitle: L("button.copy_path"))
        alert.addButton(withTitle: L("button.ok"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Bundle.main.executablePath ?? "", forType: .string)
        }
    }
}

// Flipped helper so NSScrollView's document view fills top-down.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - TitleRowView (one row per metric)

final class TitleRowView: NSView {
    let metricKey: String
    let label: String
    private let contentWidth: CGFloat
    private var segmented: NSSegmentedControl!
    private var colorButtons: [NSButton] = []
    private var colorRowView: NSStackView!

    init(metricKey: String, label: String, contentWidth: CGFloat) {
        self.metricKey = metricKey
        self.label = label
        self.contentWidth = contentWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // Label (fixed width 200)
        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = NSFont.systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.widthAnchor.constraint(equalToConstant: 200).isActive = true

        // Segmented control
        let seg = NSSegmentedControl(labels: [L("mode.hidden"), L("mode.text"), L("mode.donut")],
                                     trackingMode: .selectOne,
                                     target: self, action: #selector(modeChanged(_:)))
        seg.controlSize = .small
        seg.segmentDistribution = .fillEqually
        seg.widthAnchor.constraint(equalToConstant: 180).isActive = true
        segmented = seg

        let topRow = NSStackView(views: [nameLabel, seg])
        topRow.orientation = .horizontal
        topRow.spacing = 14
        topRow.alignment = .centerY

        // Color picker row (only visible when donut mode)
        let palette = ["#d68c45","#5dc97f","#d4c25a","#d6645a","#a87fd6","#7fb8b8","#f4eee3","#8a8378"]
        colorRowView = NSStackView()
        colorRowView.orientation = .horizontal
        colorRowView.spacing = 8
        colorRowView.alignment = .centerY

        let colorLabel = NSTextField(labelWithString: L("mode.color"))
        colorLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        colorLabel.textColor = .secondaryLabelColor
        colorLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        colorRowView.addArrangedSubview(colorLabel)

        for hex in palette {
            let b = NSButton()
            b.title = ""
            b.bezelStyle = .smallSquare
            b.setButtonType(.toggle)
            b.identifier = NSUserInterfaceItemIdentifier("color:\(hex)")
            b.wantsLayer = true
            b.layer?.cornerRadius = 9
            b.layer?.backgroundColor = NSColor(hex: hex).cgColor
            b.layer?.borderColor = NSColor.clear.cgColor
            b.layer?.borderWidth = 0
            b.widthAnchor.constraint(equalToConstant: 18).isActive = true
            b.heightAnchor.constraint(equalToConstant: 18).isActive = true
            b.target = self
            b.action = #selector(colorChanged(_:))
            colorButtons.append(b)
            colorRowView.addArrangedSubview(b)
        }

        let outer = NSStackView(views: [topRow, colorRowView])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6

        addSubview(outer)
        outer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        refresh()
    }

    func refresh() {
        let p = PrefsStore.shared.prefs
        let mode = mode(for: metricKey, from: p)
        switch mode {
        case .hidden: segmented.selectedSegment = 0
        case .text:   segmented.selectedSegment = 1
        case .donut:  segmented.selectedSegment = 2
        }
        let currentColor = color(for: metricKey, from: p)
        for b in colorButtons {
            let hex = String((b.identifier?.rawValue ?? "").dropFirst("color:".count))
            let selected = (hex == currentColor)
            b.layer?.borderColor = selected ? NSColor.labelColor.cgColor : NSColor.clear.cgColor
            b.layer?.borderWidth = selected ? 2 : 0
        }
        colorRowView.isHidden = (mode != .donut)
    }

    @objc func modeChanged(_ sender: NSSegmentedControl) {
        let newMode: MetricMode = sender.selectedSegment == 0 ? .hidden
                               : sender.selectedSegment == 1 ? .text
                               :                               .donut
        PrefsStore.shared.update { setMode(newMode, for: metricKey, in: &$0) }
    }
    @objc func colorChanged(_ sender: NSButton) {
        let hex = String((sender.identifier?.rawValue ?? "").dropFirst("color:".count))
        PrefsStore.shared.update { setColor(hex, for: metricKey, in: &$0) }
    }

    private func mode(for key: String, from p: Preferences) -> MetricMode {
        switch key {
        case "weeklyPctMode":    return p.weeklyPctMode
        case "weeklyTimeMode":   return p.weeklyTimeMode
        case "fiveHourPctMode":  return p.fiveHourPctMode
        case "fiveHourTimeMode": return p.fiveHourTimeMode
        default: return .hidden
        }
    }
    private func setMode(_ m: MetricMode, for key: String, in p: inout Preferences) {
        switch key {
        case "weeklyPctMode":    p.weeklyPctMode    = m
        case "weeklyTimeMode":   p.weeklyTimeMode   = m
        case "fiveHourPctMode":  p.fiveHourPctMode  = m
        case "fiveHourTimeMode": p.fiveHourTimeMode = m
        default: break
        }
    }
    private func color(for key: String, from p: Preferences) -> String {
        switch key {
        case "weeklyPctMode":    return p.weeklyPctColor
        case "weeklyTimeMode":   return p.weeklyTimeColor
        case "fiveHourPctMode":  return p.fiveHourPctColor
        case "fiveHourTimeMode": return p.fiveHourTimeColor
        default: return "#d68c45"
        }
    }
    private func setColor(_ hex: String, for key: String, in p: inout Preferences) {
        switch key {
        case "weeklyPctMode":    p.weeklyPctColor    = hex
        case "weeklyTimeMode":   p.weeklyTimeColor   = hex
        case "fiveHourPctMode":  p.fiveHourPctColor  = hex
        case "fiveHourTimeMode": p.fiveHourTimeColor = hex
        default: break
        }
    }
}
