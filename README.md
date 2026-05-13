# Claude Usage Widget

[![Latest release](https://img.shields.io/github/v/release/turkbil/claude-usage-widget?label=download&logo=github&color=d68c45)](https://github.com/turkbil/claude-usage-widget/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-d68c45.svg)](LICENSE)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-d68c45?logo=apple)](#requirements)
[![Signed & notarized](https://img.shields.io/badge/signed%20%26%20notarized-yes-5dc97f?logo=apple)](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

**Native macOS menu-bar widget** that shows your Claude weekly usage at a glance — same data as [claude.ai/settings/usage](https://claude.ai/settings/usage), live in the menu bar, with a rich dropdown.

> 💻 **This is the macOS version.** On Windows? → [**claude-usage-widget-windows**](https://github.com/turkbil/claude-usage-widget-windows)
>
> 🌐 [**Türkçe README**](README.tr.md)  ·  Free, open source (MIT), Apple-signed binary on the [Releases page](https://github.com/turkbil/claude-usage-widget/releases/latest)

```
…  ☀︎ 22°C  🤖 32%  🔊  12:46            ← lives next to your weather icon

┌──────────────────────────────────────────┐
│  Nurullah                    [Max 20x]   │  ← account name + plan badge
│  ────────────────────────────────────    │
│  WEEKLY                  3d 18h left     │
│   All models   ████████░░░░░░░░░  32%    │
│   Sonnet       █░░░░░░░░░░░░░░░░   2%    │
│   ↗ Projected end-of-week: 64%           │  ← burn-rate forecast
│   ╭───────●─ ─ ─ ─ ─ ─ ─◌╮               │  ← 7-day sparkline + projection
│  ────────────────────────────────────    │
│  5-HOUR WINDOW           2h 38m left     │
│   Usage        ██░░░░░░░░░░░░░░░░  7%    │
│  ────────────────────────────────────    │
│           Updated: 12:46                 │
│  ────────────────────────────────────    │
│    Settings…                       ⌘,    │
│    Refresh now                     ⌘R    │
│    Open claude.ai/settings/usage   ⌘U    │
│    Quit                            ⌘Q    │
│    nurullah.net ↗      @nurullah ↗       │
└──────────────────────────────────────────┘
```

---

## What makes this widget different

A handful of features you don't usually find together in a menu-bar app:

- 🍩 **Inline donut rings in the menu bar title.** Each metric can render as a tiny ring (not a separate window, not a popup — actually inside the title string), and you pick the color for each one independently.
- 🔮 **Burn-rate forecast.** The dropdown tells you "↗ Projected end-of-week: 64 %" while you're still mid-week. If your pace exceeds 100 %, it flips to "⚠ At this pace, limit in ~1 d 8 h."
- 📈 **Sparkline that already looks meaningful on day one.** Instead of waiting for samples to accumulate, it plots `weekStart (0 %) → today (real) → weekEnd (projected, dashed)` from the very first refresh.
- 🤝 **MCP server built into the same binary.** Claude Code itself can call `get_usage` and read your weekly limit before starting a long task. One JSON snippet, one restart of Claude Code — done.
- 🌐 **Local HTTP & CLI modes** for Raycast, Alfred, tmux, shell scripts. Same data, three ways to read it.
- 🦊 **Multi-browser failover.** Chrome, Brave, Edge, Arc — toggle the ones you actually use; the widget tries them in order and the first valid claude.ai session wins. No vendor lock-in.
- 🔔 **Edge-triggered threshold notifications.** Three configurable levels (warn / alert / critical) fire **once per week per level** — no notification spam if you bounce around the threshold. Re-armed automatically after the weekly reset.
- 🎚 **Real preferences window, not nested submenus.** Every setting is visible at once. Click the custom emoji field and the macOS Emoji Picker pops automatically.
- 🔐 **Signed & notarized — no `xattr` workarounds.** Drag to `/Applications`, double-click, done.
- 🪙 **No third-party services.** No Sparkle, no Sentry, no analytics endpoint, no telemetry SDK. The only outbound traffic is `claude.ai` (usage data) and `api.github.com` (daily release check, can be disabled).

---

## Features

### Menu-bar title
- 🎯 **Real weekly limit %** from the same API claude.ai itself uses
- 🍩 **Per-metric display** — each of {weekly %, weekly time, 5-hour %, 5-hour time} can be **hidden**, shown as **text**, or shown as a tiny **inline donut ring** in any color
- 🤖 **Pick an icon** — 8 emoji presets, your own custom emoji, a percent-filling donut summary, or no icon at all

### Rich dropdown
- 📊 Account header (display name + plan badge — `Max 20x`, `Pro`, etc.)
- 🟢 Color-coded rounded progress bars (green → yellow → orange → red as you approach the limit)
- 🔮 **Burn-rate forecast** — "↗ Projected end-of-week: 64%" or "⚠ At this pace, limit in ~1d 8h"
- 📈 **Sparkline trend** — past samples + projected future on a 7-day timeline
- 🪟 Separate section for the 5-hour rolling window
- 🌍 **Auto-localized** — English, Türkçe, Deutsch, Español, Français

### Settings window (⌘,)
- All preferences visible at once, no nested menus
- Threshold notifications (warn / alert / critical) with sliders
- Refresh interval (30s · 1m · 5m · 10m)
- **Global hotkey** to pop the dropdown from anywhere (default ⌥⌘U)
- **Multi-browser cookie source** — Chrome · Brave · Edge · Arc (Chromium siblings all supported)

### Integration
- 🤝 **MCP server mode** — Claude Code itself can read your weekly limit via the bundled `get_usage` tool
- 🌐 **Local HTTP endpoint** on `127.0.0.1:9123` for Raycast/Alfred/tmux integrations
- 🖥 **CLI mode** — `ClaudeUsageWidget --print-usage` dumps JSON for shell scripts

### Polish
- ✅ **Signed & notarized** with Apple Developer ID — no Gatekeeper warning
- 🪶 ~0 % CPU at rest
- 🔒 **Zero credentials stored** — reads the existing Chrome cookie via macOS Keychain, same trust path Chrome itself uses
- 🔄 **Auto-update check** against GitHub Releases (no Sparkle, no signup, no third-party)

---

## Quick install

1. Download the latest `ClaudeUsageWidget.zip` from the [**Releases page**](https://github.com/turkbil/claude-usage-widget/releases/latest)
2. Unzip → drag `ClaudeUsageWidget.app` to `/Applications`
3. Double-click. Because the binary is signed & notarized, macOS opens it without warnings.
4. (Optional) Right-click the menu-bar icon → Settings → enable **Run at startup**, set your **hotkey**, configure thresholds, etc.

### Auto-start at login

```bash
cp install/local.claude-usage-widget.plist ~/Library/LaunchAgents/
# Edit the path inside if your .app isn't in /Applications
launchctl load -w ~/Library/LaunchAgents/local.claude-usage-widget.plist
```

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/local.claude-usage-widget.plist 2>/dev/null
rm -rf /Applications/ClaudeUsageWidget.app \
       ~/Library/LaunchAgents/local.claude-usage-widget.plist \
       ~/.claude-usage-widget-cache.json \
       ~/.claude-usage-widget-history.json
defaults delete app.claude-usage-widget 2>/dev/null
```

---

## Requirements

| Component | Why |
|---|---|
| **macOS 12+** | Native Cocoa app |
| **A Chromium-based browser** with an active claude.ai session | The widget reads `sessionKey` from the browser's cookie store. Chrome, Brave, Edge, and Arc are all supported — toggle them in Settings → Browsers. |
| A **Claude.ai account** (Free, Pro, Max — any tier) | To have usage data to display |

> **No browser extension, no API key, no desktop Claude app.** Just a browser + an active claude.ai login.

On first launch macOS will ask for **Keychain access** to read the browser cookie key. Click **Always Allow**.

---

## Settings overview

Open the dropdown → **Settings…** (⌘,)

| Section | What's there |
|---|---|
| **Title content** | For each of `Weekly %`, `Weekly remaining`, `5-hour %`, `5-hour remaining`: hide / show as text / show as a donut. When donut, pick from 8 swatch colors. |
| **Icon** | Emoji preset (🤖🧠⚡✨◉●▲◐), custom emoji (clicking the field opens macOS Emoji Picker automatically), donut summary, or no icon. |
| **Refresh interval** | 30 s · 1 min · 5 min · 10 min |
| **Notifications** | Enable threshold alerts. Three macOS-native notifications fire when you cross warn / alert / critical thresholds. Each level fires once per week (re-armed after reset). |
| **Hotkey** | Toggle global hotkey. Default ⌥⌘U opens the dropdown from anywhere. |
| **Browsers** | Toggle Chrome, Brave, Edge, Arc. The widget tries each enabled browser in order; the first one with a valid claude.ai session wins. |
| **Network & integration** | Daily update check · Local HTTP endpoint :9123 · MCP install instructions |

---

## Integration (other tools)

### MCP — Claude Code can see its own limit
Settings → "MCP install instructions…" gives you a JSON snippet to paste into `~/.claude.json`:

```json
{
  "mcpServers": {
    "claude-usage": {
      "command": "/Applications/ClaudeUsageWidget.app/Contents/MacOS/ClaudeUsageWidget",
      "args": ["--mcp-server"]
    }
  }
}
```

After restarting Claude Code, Claude can call `get_usage` to see your weekly limit — useful before a long task.

### Local HTTP — for Raycast/Alfred/tmux/etc.
Settings → enable **"Local HTTP endpoint (:9123)"**, then:

```bash
$ curl localhost:9123/usage
{
  "display_name": "Nurullah",
  "fetched_at": "2026-05-13T00:42:00Z",
  "five_hour_resets_at": "2026-05-13T03:10:00Z",
  "five_hour_utilization_pct": 7,
  "plan": "Max 20x",
  "weekly_resets_at": "2026-05-16T05:00:00Z",
  "weekly_utilization_pct": 32
}
```

Only listens on `127.0.0.1`. Never exposed externally.

### CLI — one-shot JSON
```bash
$ /Applications/ClaudeUsageWidget.app/Contents/MacOS/ClaudeUsageWidget --print-usage
```
Same JSON, exits immediately. For shell scripts, statuslines.

---

## Building from source

Requires Xcode Command Line Tools.

```bash
git clone https://github.com/turkbil/claude-usage-widget.git
cd claude-usage-widget
./build.sh
open ClaudeUsageWidget.app
```

The build produces an unsigned `.app`. For an officially signed/notarized binary, use the Releases page.

---

## How it works

```
┌──────────────────┐    SQLite + AES-128-CBC      ┌─────────────────┐
│  Browser cookies │ ────────────────────────────▶│  sessionKey     │
│  (encrypted)     │  key from macOS Keychain     │  (decrypted)    │
└──────────────────┘                              └────────┬────────┘
                                                           │
                                          Cookie: sessionKey=...
                                                           ▼
                            ┌──────────────────────────────────────────┐
                            │ GET claude.ai/api/organizations/{id}/    │
                            │     usage  (seven_day.* + five_hour.*)   │
                            │ GET claude.ai/api/account     (name)     │
                            │ GET claude.ai/api/.../rate_limits (plan) │
                            └────────────────┬─────────────────────────┘
                                             ▼
                              ┌──────────────────────────────┐
                              │  Menu bar UI · refreshes 60s │
                              │  + history sample / 5min     │
                              │  + threshold notifications   │
                              │  + sparkline trend           │
                              └──────────────────────────────┘
```

The widget never sees your password. It uses the same encrypted-cookie + Keychain trick the browser itself uses — every macOS browser does this for stored cookies on your own machine.

---

## Privacy

- **No telemetry.** No analytics. No crash reports to third parties. The only outbound traffic is HTTPS to `claude.ai` (usage data) and once a day to `api.github.com` (version check, can be disabled).
- **Cookie never written to disk.** Lives in memory only.
- **Persisted files** (~70 KB total):
  - `~/.claude-usage-widget-cache.json` — latest snapshot
  - `~/.claude-usage-widget-history.json` — 14-day sparkline samples
- **Settings stored** in `defaults` (UserDefaults).

---

## Languages

The widget auto-detects your macOS preferred language and falls back to English.

| | |
|---|---|
| 🇬🇧 | English (default) |
| 🇹🇷 | Türkçe |
| 🇩🇪 | Deutsch |
| 🇪🇸 | Español |
| 🇫🇷 | Français |

Want to add a language? Copy `Resources/en.lproj/Localizable.strings` to `Resources/<code>.lproj/Localizable.strings`, translate the values, add the code to `CFBundleLocalizations` in `build.sh`, and open a PR.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `🤖 ?` with "No claude.ai session" | Open your browser and log into claude.ai. Make sure the browser you're logged into is enabled in Settings → Browsers. |
| `🤖 ?` with "Keychain access denied" | The first launch shows a Keychain prompt — click **Always Allow**. To reset: Keychain Access → "Chrome Safe Storage" → Access Control → add ClaudeUsageWidget. |
| `HTTP 401` | Your claude.ai session expired. Re-login via your browser. |
| Stale percentage | Open the dropdown → **Refresh now** (⌘R) |
| Nothing in the menu bar | Check `/tmp/claude-usage-widget.err.log`. Make sure the app is running (`pgrep ClaudeUsageWidget`). |
| Crash | macOS auto-saves a crash log to `~/Library/Logs/DiagnosticReports/`. Open a GitHub issue and paste it. |

---

## Tips & tricks

- **Quick toggle:** ⌥⌘U from anywhere opens the dropdown (configurable in Settings).
- **Donut + hidden text** = the cleanest menu bar look. Set every metric to "Donut" with different colors; you get 4 tiny rings in your menu bar with no numeric clutter.
- **Pause polling** by setting Refresh interval to 10 min when on battery — drops API hits to 6/h.
- **One-shot status check:** add an alias `alias claude-status='ClaudeUsageWidget --print-usage | jq .weekly_utilization_pct'` to your shell.
- **Forecast over the line:** when "Projected end-of-week" goes above 100 %, the dropdown switches to a red "at this pace, limit in ~X" message — your cue to slow down.
- **Multi-browser tip:** if you use one browser for work and another for personal, enable both — the widget reads from whichever has the active claude.ai session.

---

## Project layout (for contributors)

```
.
├── Sources/                 13 Swift files
│   ├── main.swift           # AppDelegate, popup, menu, refresh loop
│   ├── Preferences.swift    # Codable settings + UserDefaults store
│   ├── SettingsWindow.swift # NSWindow with all preferences
│   ├── TitleRenderer.swift  # composes NSAttributedString for the menu-bar title
│   ├── DonutImage.swift     # inline donut NSImage renderer
│   ├── BrowserCookieReader.swift   # Chrome/Brave/Edge/Arc cookie decryption
│   ├── ClaudeApi.swift      # claude.ai API client (inside main.swift currently)
│   ├── Forecast.swift       # burn-rate projection logic
│   ├── UsageHistory.swift   # sparkline sample buffer (14-day cap)
│   ├── NotificationManager.swift   # threshold alerts (UserNotifications)
│   ├── HotKeyManager.swift  # Carbon RegisterEventHotKey wrapper
│   ├── VersionChecker.swift # daily GitHub Releases poll
│   ├── LocalHTTPServer.swift       # NWListener on 127.0.0.1:9123
│   ├── MCPServer.swift      # JSON-RPC over stdio
│   └── CLIRunner.swift      # --print-usage one-shot mode
├── Resources/{en,tr,de,es,fr}.lproj/Localizable.strings
├── .github/workflows/release.yml   # signs + notarizes + publishes on tag push
├── build.sh                 # builds the .app
├── install/local.claude-usage-widget.plist   # LaunchAgent template
└── docs/feature-preview.html       # design preview / catalog
```

---

## Author

Built by **Nurullah Okatan** — [nurullah.net](https://www.nurullah.net) · [@nurullah](https://x.com/nurullah)

## License

[MIT](LICENSE) © Nurullah Okatan

Not affiliated with Anthropic. "Claude" is a trademark of Anthropic.
