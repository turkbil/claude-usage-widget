# Changelog

All notable changes to **Claude Usage Widget** are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [SemVer](https://semver.org/spec/v2.0.0.html).

## [1.4.1] — 2026-05-13

### Added
- Signed and notarized .app: every release is now stapled with Apple's Developer ID,
  so Gatekeeper opens it without warnings.
- `.github/workflows/release.yml` builds, signs, notarizes, staples, and publishes the
  ZIP to a GitHub Release on every `v*` tag.

## [1.4.0] — 2026-05-13

### Added
- **Settings window** replacing the nested-submenu maze. One scrollable view with
  all preferences visible: title content (per-metric mode + color), icon, refresh
  interval, notifications, hotkey, browsers, network. Opens with ⌘,
- **Sparkline trend** in the popup. The widget records its weekly% samples to
  `~/.claude-usage-widget-history.json` every 5 minutes; a gradient line chart
  shows up to 14 days of trajectory.

## [1.3.0] — 2026-05-12

### Added
- **MCP server mode** (`--mcp-server` flag). Exposes a `get_usage` tool over
  stdio JSON-RPC so Claude Code can read its own weekly limit before starting
  long tasks. Settings → MCP install instructions… copies the binary path.
- **Local HTTP endpoint** on `127.0.0.1:9123` (`GET /usage` returns JSON).
  For Raycast extensions, terminal statuslines, etc.
- **CLI mode** (`--print-usage` flag) prints current usage as JSON and exits.

## [1.2.0] — 2026-05-12

### Added
- **Burn-rate forecast** in the popup. Shows projected end-of-week % at the
  current pace, or "at this pace, limit in ~Xd Yh" when the projection exceeds 100%.

## [1.1.0] — 2026-05-12

### Added
- **§01** Title content: per-metric Hidden / Text / Donut + per-metric color swatch.
  Weekly%, weekly remaining, 5-hour%, 5-hour remaining — each independent.
- **§02** Icon picker: 8 emoji presets, custom emoji input, donut summary, or no icon.
- **§05** Threshold notifications via macOS Notification Center.
  Three edge-triggered levels (warn / alert / critical) with adjustable thresholds.
- **§06** Refresh interval selector: 30s / 1m / 5m / 10m.
- **§07** Global hotkey via Carbon's RegisterEventHotKey. Default ⌥⌘U opens the popup.
- **§08** Multi-browser cookie source: Chrome, Brave, Edge, Arc.
  All Chromium-family — same crypto, different paths and Keychain service names.
  Widget tries each enabled browser in order; first valid session wins.
- **§09** Lightweight version check via GitHub Releases API. No keys, no signing,
  no third-party service. Shows "New: vX.Y →" in the dropdown when available.
- **§10** Credit footer: minimal links at the bottom of the dropdown — `nurullah.net ↗`
  and `@nurullah ↗`.

### Changed
- Refactored into multiple `Sources/*.swift` files (Preferences, DonutImage,
  TitleRenderer, BrowserCookieReader, NotificationManager, HotKeyManager,
  VersionChecker). `build.sh` now compiles them all together.
- Dropped consideration of Sentry crash reports — macOS native crash logs are
  the fallback (`~/Library/Logs/DiagnosticReports/`).
- Dropped Sparkle in favor of the lightweight GitHub release-check.

## [1.0.0] — 2026-05-12

### Added
- Initial release. Native macOS menu bar widget showing Claude weekly
  utilization % and time until reset.
- Auto-localized: English, Türkçe, Deutsch, Español, Français.
- Pulls data from `claude.ai/api/organizations/{id}/usage` using the existing
  Chrome session cookie. No API key, no third-party service.
- Color-coded rounded progress bars (green / yellow / orange / red).
- Account header with display name + plan badge (e.g. "Max 20x").

[1.4.1]: https://github.com/turkbil/claude-usage-widget/releases/tag/v1.4.1
[1.4.0]: https://github.com/turkbil/claude-usage-widget/releases/tag/v1.4.0
[1.3.0]: https://github.com/turkbil/claude-usage-widget/releases/tag/v1.3.0
[1.2.0]: https://github.com/turkbil/claude-usage-widget/releases/tag/v1.2.0
[1.1.0]: https://github.com/turkbil/claude-usage-widget/releases/tag/v1.1.0
[1.0.0]: https://github.com/turkbil/claude-usage-widget/releases/tag/v1.0.0
