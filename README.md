# Claude Usage Widget

A native macOS menu bar widget that shows your Claude weekly usage percentage and time until reset — at a glance, right next to your weather icon.

> On Windows? → [**claude-usage-widget-windows**](https://github.com/turkbil/claude-usage-widget-windows)

[**Türkçe README →**](README.tr.md)

```
┌──────────────────────────────────────────┐
│  Nurullah                    [Max 20x]   │
│  ────────────────────────────────────    │
│  WEEKLY                  3d 18h left     │
│   All models   ████████░░░░░░░░░  32%    │
│   Sonnet       █░░░░░░░░░░░░░░░░   2%    │
│  ────────────────────────────────────    │
│  5-HOUR WINDOW           2h 38m left     │
│   Usage        ██░░░░░░░░░░░░░░░░  7%    │
│  ────────────────────────────────────    │
│           Updated: 12:46 PM              │
│  ────────────────────────────────────    │
│  ☐ Show remaining time in title          │
│    Refresh now                    ⌘R     │
│    Open claude.ai/settings/usage  ⌘U     │
│    Quit                           ⌘Q     │
└──────────────────────────────────────────┘
```

## Features

- 🎯 **Real Claude weekly limit** — pulls the same `% used` number you see on [claude.ai/settings/usage](https://claude.ai/settings/usage)
- ⏱ **Countdown to reset** — "3d 18h left" in your menu bar (optional)
- 🪟 **5-hour window** — separate progress bar for the short-term limit
- 🎨 **Color-coded bars** — green → yellow → orange → red as you approach the limit
- 🌍 **Auto-localized** — English, Türkçe, Deutsch, Español, Français (follows your macOS language)
- 🪶 **~0% CPU at rest** — polls once a minute, watches `~/.claude/projects` for changes
- 🔒 **No credentials stored** — reads your existing Chrome session cookie via macOS Keychain
- 🚀 **Auto-starts at login** — installed as a LaunchAgent

## Requirements

| Component | Why |
|---|---|
| **macOS 12.0+** | Native Cocoa app |
| **Xcode Command Line Tools** | Provides Swift compiler |
| **Google Chrome** with an active claude.ai session | The widget reads `sessionKey` from Chrome's cookie store |
| A **Claude.ai account** (Free, Pro, Max — any tier) | To have weekly usage data to display |

> **No browser extension, no API key, no desktop Claude app.** Just Chrome + an active claude.ai login.

If you're not logged into claude.ai in Chrome, the widget will show `⚠︎ No claude.ai session — please log in via Chrome` until you do.

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/claude-usage-widget.git
cd claude-usage-widget
./build.sh
open ClaudeUsageWidget.app
```

On first launch macOS will ask for **Keychain access** to read the Chrome cookie encryption key. Click **Always Allow**. (This is the same key Chrome itself uses — the widget cannot read anything Chrome can't.)

### Auto-start at login

```bash
cp install/local.claude-usage-widget.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/local.claude-usage-widget.plist
```

> Edit the path inside the plist if you put the `.app` somewhere other than `~/ClaudeUsageWidget/`.

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/local.claude-usage-widget.plist
rm -rf ~/ClaudeUsageWidget ~/Library/LaunchAgents/local.claude-usage-widget.plist ~/.claude-usage-widget-cache.json
defaults delete app.claude-usage-widget 2>/dev/null
```

## How it works

```
┌──────────────────┐    SQLite + AES-128-CBC      ┌─────────────────┐
│  Chrome cookies  │ ────────────────────────────▶│  sessionKey     │
│  (encrypted)     │   key from macOS Keychain    │  (decrypted)    │
└──────────────────┘                              └────────┬────────┘
                                                           │
                                          Cookie: sessionKey=...
                                                           ▼
                              ┌────────────────────────────────────────┐
                              │ GET claude.ai/api/organizations/{id}/   │
                              │     usage                              │
                              │      → seven_day.utilization (32.0)    │
                              │      → seven_day.resets_at             │
                              │      → five_hour.utilization (7.0)     │
                              │      → five_hour.resets_at             │
                              └────────────────┬───────────────────────┘
                                               ▼
                                      ┌─────────────────┐
                                      │  Menu bar UI    │
                                      │  refreshes 60s  │
                                      └─────────────────┘
```

The widget never sees your password. It uses the same encrypted-cookie + Keychain trick that Chrome itself uses — every macOS browser does this for stored cookies.

## Configuration

| Setting | Where | Notes |
|---|---|---|
| Show countdown in menu bar title | Menu → "Show remaining time in title" | Off by default. Persisted to `defaults` (UserDefaults). |
| Color thresholds | `Sources/main.swift` → `UsageRowView.colorFor` | Default: green <50, yellow <75, orange <90, red ≥90 |
| Poll interval | `Sources/main.swift` → `AppConfig.pollIntervalSec` | Default: 60s |

## Languages

The widget auto-detects your macOS preferred language and falls back to English. Currently bundled:

- 🇬🇧 English (default)
- 🇹🇷 Türkçe
- 🇩🇪 Deutsch
- 🇪🇸 Español
- 🇫🇷 Français

Want to add a language? Copy `Resources/en.lproj/Localizable.strings` to `Resources/<code>.lproj/Localizable.strings`, translate the values, add the code to `CFBundleLocalizations` in `build.sh`, and open a PR.

## Privacy & security

- **No telemetry.** The widget makes exactly two outbound HTTPS calls per refresh, both to `claude.ai`. Nothing else leaves your machine.
- **No data sent to third parties.** Your session cookie is read locally and used only against `claude.ai` itself.
- **Cookie never written to disk.** It lives in memory only.
- **Cache contains only**: weekly/5-hour utilization percentages, reset timestamps, your display name, your plan label. Stored at `~/.claude-usage-widget-cache.json`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `🤖 ?` with "No claude.ai session" | Open Chrome and log into claude.ai |
| `🤖 ?` with "Keychain access denied" | The first launch shows a Keychain prompt — click **Always Allow**. To reset: open Keychain Access → "Chrome Safe Storage" → Access Control → add ClaudeUsageWidget |
| `HTTP 401` | Your claude.ai session expired. Re-login via Chrome. |
| Stale percentage | Click the menu and pick "Refresh now" |
| Nothing in menu bar | Check `/tmp/claude-usage-widget.err.log` |

## Author

Built by **Nurullah Okatan** — [nurullah.net](https://www.nurullah.net)

## License

[MIT](LICENSE) © Nurullah Okatan

Not affiliated with Anthropic. "Claude" is a trademark of Anthropic.
