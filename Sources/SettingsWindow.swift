import AppKit

/// Single settings window. Replaces the nested-submenu maze with one
/// scrollable view where every preference is visible and one click away.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    // Sections keep weak references to controls they need to refresh.
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = L("settings.title")
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        w.delegate = self
        w.contentView = makeContentView()

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

    @objc private func prefsChanged() {
        refreshAllControls()
    }

    // MARK: - Content view

    private func makeContentView() -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 660))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(titleSection())
        stack.addArrangedSubview(iconSection())
        stack.addArrangedSubview(refreshSection())
        stack.addArrangedSubview(notificationsSection())
        stack.addArrangedSubview(hotkeySection())
        stack.addArrangedSubview(browsersSection())
        stack.addArrangedSubview(networkSection())

        let flipped = FlippedView(frame: .zero)
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: flipped.topAnchor),
            stack.leftAnchor.constraint(equalTo: flipped.leftAnchor),
            stack.rightAnchor.constraint(equalTo: flipped.rightAnchor),
            flipped.widthAnchor.constraint(equalToConstant: 540),
        ])

        scroll.documentView = flipped
        return scroll
    }

    // MARK: - Sections

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func sectionBox(_ children: [NSView]) -> NSView {
        let s = NSStackView(views: children)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 10
        return s
    }

    private func sectionHeader(_ title: String) -> NSView {
        let label = sectionLabel(title)
        let rule = NSBox()
        rule.boxType = .separator
        let row = NSStackView(views: [label, rule])
        row.orientation = .vertical
        row.spacing = 6
        row.alignment = .leading
        return row
    }

    // §01 — Title content
    private func titleSection() -> NSView {
        titleRows.removeAll()
        let metrics: [(String, String)] = [
            ("weeklyPctMode",    L("label.all_models") + " · %"),
            ("weeklyTimeMode",   L("section.weekly") + " · ⏱"),
            ("fiveHourPctMode",  L("section.five_hour") + " · %"),
            ("fiveHourTimeMode", L("section.five_hour") + " · ⏱"),
        ]
        var children: [NSView] = [sectionHeader(L("menu.title_content"))]
        for (key, label) in metrics {
            let row = TitleRowView(metricKey: key, label: label)
            titleRows.append(row)
            children.append(row)
        }
        return sectionBox(children)
    }

    // §02 — Icon
    private func iconSection() -> NSView {
        iconButtons.removeAll()
        let presets = ["🤖", "🧠", "⚡", "✨", "◉", "●", "▲", "◐"]

        let grid = NSStackView()
        grid.orientation = .horizontal
        grid.spacing = 6
        for emoji in presets {
            let b = NSButton(title: emoji, target: self, action: #selector(pickEmoji(_:)))
            b.bezelStyle = .smallSquare
            b.setButtonType(.toggle)
            b.identifier = NSUserInterfaceItemIdentifier("emoji:\(emoji)")
            b.font = NSFont.systemFont(ofSize: 18)
            b.widthAnchor.constraint(equalToConstant: 42).isActive = true
            b.heightAnchor.constraint(equalToConstant: 38).isActive = true
            iconButtons.append(b)
            grid.addArrangedSubview(b)
        }

        let custom = NSButton(checkboxWithTitle: L("icon.custom"), target: self, action: #selector(toggleCustomIcon(_:)))
        custom.identifier = NSUserInterfaceItemIdentifier("icon:custom")
        iconButtons.append(custom)

        let customField = NSTextField(string: "")
        customField.placeholderString = "🪐"
        customField.target = self
        customField.action = #selector(updateCustomEmoji(_:))
        customField.font = NSFont.systemFont(ofSize: 16)
        customField.alignment = .center
        customField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        customEmojiField = customField

        let customRow = NSStackView(views: [custom, customField])
        customRow.orientation = .horizontal
        customRow.spacing = 8

        let donut = NSButton(radioButtonWithTitle: L("icon.donut"), target: self, action: #selector(pickIconDonut))
        donut.identifier = NSUserInterfaceItemIdentifier("icon:donut")
        iconButtons.append(donut)

        let none = NSButton(radioButtonWithTitle: L("icon.none"), target: self, action: #selector(pickIconNone))
        none.identifier = NSUserInterfaceItemIdentifier("icon:none")
        iconButtons.append(none)

        return sectionBox([sectionHeader(L("menu.icon")), grid, customRow, donut, none])
    }

    // §06 — Refresh interval
    private func refreshSection() -> NSView {
        refreshButtons.removeAll()
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let opts: [(Int, String)] = [
            (30,  L("refresh.30s")),
            (60,  L("refresh.1m")),
            (300, L("refresh.5m")),
            (600, L("refresh.10m")),
        ]
        for (sec, label) in opts {
            let b = NSButton(radioButtonWithTitle: label, target: self, action: #selector(pickRefresh(_:)))
            b.identifier = NSUserInterfaceItemIdentifier("refresh:\(sec)")
            b.tag = sec
            refreshButtons.append(b)
            row.addArrangedSubview(b)
        }
        return sectionBox([sectionHeader(L("menu.refresh_interval")), row])
    }

    // §05 — Notifications
    private func notificationsSection() -> NSView {
        let enable = NSButton(checkboxWithTitle: L("notifications.enable"),
                              target: self, action: #selector(toggleNotifications(_:)))
        notifEnabledCheckbox = enable

        func slider(_ name: String, action: Selector, min: Double, max: Double, accent: NSColor) -> (NSStackView, NSSlider, NSTextField) {
            let label = NSTextField(labelWithString: name)
            label.font = NSFont.systemFont(ofSize: 12)
            label.widthAnchor.constraint(equalToConstant: 80).isActive = true

            let s = NSSlider(value: 50, minValue: min, maxValue: max, target: self, action: action)
            s.controlSize = .small
            s.widthAnchor.constraint(equalToConstant: 280).isActive = true

            let val = NSTextField(labelWithString: "%50")
            val.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            val.widthAnchor.constraint(equalToConstant: 50).isActive = true

            let dot = NSTextField(labelWithString: "●")
            dot.textColor = accent

            let row = NSStackView(views: [dot, label, s, val])
            row.orientation = .horizontal
            row.spacing = 8
            return (row, s, val)
        }

        let (warnRow, warnS, warnV)             = slider(L("notifications.warn"),     action: #selector(setWarn(_:)),     min: 20, max: 80, accent: .systemYellow)
        let (alertRow, alertS, alertV)          = slider(L("notifications.alert"),    action: #selector(setAlert(_:)),    min: 50, max: 95, accent: .systemOrange)
        let (criticalRow, criticalS, criticalV) = slider(L("notifications.critical"), action: #selector(setCritical(_:)), min: 70, max: 99, accent: .systemRed)

        warnSlider = warnS; alertSlider = alertS; criticalSlider = criticalS
        warnValue = warnV; alertValue = alertV; criticalValue = criticalV

        let slidersStack = NSStackView(views: [warnRow, alertRow, criticalRow])
        slidersStack.orientation = .vertical
        slidersStack.spacing = 6
        slidersStack.alignment = NSLayoutConstraint.Attribute.leading

        return sectionBox([sectionHeader(L("menu.notifications")), enable, slidersStack])
    }

    // §07 — Hotkey
    private func hotkeySection() -> NSView {
        let enable = NSButton(checkboxWithTitle: L("hotkey.enable"),
                              target: self, action: #selector(toggleHotkey(_:)))
        hotkeyEnabledCheckbox = enable
        let p = PrefsStore.shared.prefs
        let label = HotKeyManager.label(keyCode: p.hotkeyKeyCode, modifiers: p.hotkeyModifiers)
        let current = NSTextField(labelWithString: L("hotkey.current", label as NSString))
        current.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        current.textColor = .secondaryLabelColor
        return sectionBox([sectionHeader(L("menu.hotkey")), enable, current])
    }

    // §08 — Browsers
    private func browsersSection() -> NSView {
        browserCheckboxes.removeAll()
        let items: [(String, String)] = [
            ("chrome", "🟢 " + L("browser.chrome")),
            ("brave",  "🦁 " + L("browser.brave")),
            ("edge",   "🟦 " + L("browser.edge")),
            ("arc",    "🏹 " + L("browser.arc")),
        ]
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 16
        for (id, label) in items {
            let b = NSButton(checkboxWithTitle: label, target: self, action: #selector(toggleBrowser(_:)))
            b.identifier = NSUserInterfaceItemIdentifier("browser:\(id)")
            browserCheckboxes.append(b)
            row.addArrangedSubview(b)
        }
        return sectionBox([sectionHeader(L("menu.browsers")), row])
    }

    // §09 — Network / Updates
    private func networkSection() -> NSView {
        let ver = NSButton(checkboxWithTitle: L("menu.version_check"),
                           target: self, action: #selector(toggleVersionCheck(_:)))
        versionCheckCheckbox = ver

        let api = NSButton(checkboxWithTitle: L("menu.local_http"),
                           target: self, action: #selector(toggleLocalHTTP(_:)))
        localApiCheckbox = api

        let mcpBtn = NSButton(title: L("menu.mcp_install"), target: self, action: #selector(showMCPInstall))
        mcpBtn.bezelStyle = .rounded

        return sectionBox([sectionHeader(L("menu.network")), ver, api, mcpBtn])
    }

    // MARK: - Refresh state from prefs

    private func refreshAllControls() {
        let p = PrefsStore.shared.prefs
        // Title rows
        for row in titleRows { row.refresh() }
        // Icon buttons
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
        // Refresh radio
        for b in refreshButtons { b.state = (b.tag == p.pollIntervalSec) ? .on : .off }
        // Notifications
        notifEnabledCheckbox?.state = p.notificationsEnabled ? .on : .off
        warnSlider?.doubleValue = Double(p.warnThreshold);         warnValue?.stringValue = "%\(p.warnThreshold)"
        alertSlider?.doubleValue = Double(p.alertThreshold);       alertValue?.stringValue = "%\(p.alertThreshold)"
        criticalSlider?.doubleValue = Double(p.criticalThreshold); criticalValue?.stringValue = "%\(p.criticalThreshold)"
        // Hotkey
        hotkeyEnabledCheckbox?.state = p.hotkeyEnabled ? .on : .off
        // Browsers
        for b in browserCheckboxes {
            guard let id = b.identifier?.rawValue else { continue }
            let key = String(id.dropFirst("browser:".count))
            switch key {
            case "chrome": b.state = p.browserChromeEnabled ? .on : .off
            case "brave":  b.state = p.browserBraveEnabled  ? .on : .off
            case "edge":   b.state = p.browserEdgeEnabled   ? .on : .off
            case "arc":    b.state = p.browserArcEnabled    ? .on : .off
            default: break
            }
        }
        // Network
        versionCheckCheckbox?.state = p.versionCheckEnabled ? .on : .off
        localApiCheckbox?.state     = p.localApiEnabled     ? .on : .off
    }

    // MARK: - Actions

    @objc func pickEmoji(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("emoji:") else { return }
        let e = String(id.dropFirst("emoji:".count))
        PrefsStore.shared.update { $0.iconType = .emoji; $0.iconValue = e }
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
        guard let id = sender.identifier?.rawValue else { return }
        let key = String(id.dropFirst("browser:".count))
        PrefsStore.shared.update { p in
            switch key {
            case "chrome": p.browserChromeEnabled = (sender.state == .on)
            case "brave":  p.browserBraveEnabled  = (sender.state == .on)
            case "edge":   p.browserEdgeEnabled   = (sender.state == .on)
            case "arc":    p.browserArcEnabled    = (sender.state == .on)
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
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Bundle.main.executablePath ?? "", forType: .string)
        }
    }
}

// Helper view that flips the coordinate system so NSStackView fills top-down
// when wrapped by an NSScrollView.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - TitleRowView: per-metric 3-mode picker + color swatch

final class TitleRowView: NSView {
    let metricKey: String
    let label: String
    private var segmented: NSSegmentedControl!
    private var colorButtons: [NSButton] = []

    init(metricKey: String, label: String) {
        self.metricKey = metricKey
        self.label = label
        super.init(frame: NSRect(x: 0, y: 0, width: 490, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = NSFont.systemFont(ofSize: 12)
        nameLabel.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let seg = NSSegmentedControl(labels: [L("mode.hidden"), L("mode.text"), L("mode.donut")],
                                     trackingMode: .selectOne,
                                     target: self, action: #selector(modeChanged(_:)))
        seg.controlSize = .small
        seg.widthAnchor.constraint(equalToConstant: 180).isActive = true
        segmented = seg

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(seg)

        let palette: [String] = ["#d68c45","#5dc97f","#d4c25a","#d6645a","#a87fd6","#7fb8b8","#f4eee3","#8a8378"]
        for hex in palette {
            let b = NSButton()
            b.title = ""
            b.bezelStyle = .smallSquare
            b.setButtonType(.toggle)
            b.identifier = NSUserInterfaceItemIdentifier("color:\(hex)")
            b.wantsLayer = true
            b.layer?.cornerRadius = 7
            b.layer?.backgroundColor = NSColor(hex: hex).cgColor
            b.layer?.borderColor = NSColor.clear.cgColor
            b.layer?.borderWidth = 0
            b.widthAnchor.constraint(equalToConstant: 16).isActive = true
            b.heightAnchor.constraint(equalToConstant: 16).isActive = true
            b.target = self
            b.action = #selector(colorChanged(_:))
            colorButtons.append(b)
            row.addArrangedSubview(b)
        }

        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        refresh()
    }

    func refresh() {
        let p = PrefsStore.shared.prefs
        let mode = mode(for: metricKey, from: p)
        switch mode {
        case .hidden: segmented?.selectedSegment = 0
        case .text:   segmented?.selectedSegment = 1
        case .donut:  segmented?.selectedSegment = 2
        }
        let currentColor = color(for: metricKey, from: p)
        for b in colorButtons {
            let hex = String((b.identifier?.rawValue ?? "").dropFirst("color:".count))
            let selected = (hex == currentColor)
            b.layer?.borderColor = selected ? NSColor.labelColor.cgColor : NSColor.clear.cgColor
            b.layer?.borderWidth = selected ? 2 : 0
            b.isHidden = (mode != .donut)
        }
    }

    @objc func modeChanged(_ sender: NSSegmentedControl) {
        let newMode: MetricMode = sender.selectedSegment == 0 ? .hidden
                               : sender.selectedSegment == 1 ? .text
                               :                               .donut
        PrefsStore.shared.update { setMode(newMode, for: metricKey, in: &$0) }
    }

    @objc func colorChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let hex = String(id.dropFirst("color:".count))
        PrefsStore.shared.update { setColor(hex, for: metricKey, in: &$0) }
    }

    // MARK: - per-key getters/setters

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
