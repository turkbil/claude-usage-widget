# Changelog

All notable changes to **Claude Usage Widget** are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [SemVer](https://semver.org/spec/v2.0.0.html).

## [1.5.8] — 2026-11-13

### Changed
- The accounts list shows **used %** for Weekly and Fable, the same as the bars at the top.
- Hide / delete opens only from the **eye icon** at the end of each row; clicking the row does nothing.
- Weekly and Fable free resets share **one row** in the expanded table
  ("Resets · Weekly ↺1 · until 11 Dec · Fable ↺3 · until 9 Mar").

### Fixed
- The local HTTP server (127.0.0.1:9123) never actually started; it now serves `/usage`,
  `/healthz` and the new read-only **`/accounts`** (used by the Chrome extension to restore data).

## [1.5.7] — 2026-11-13

### Added
- **API credits per account** (developer console, platform.claude.com): balance, granted
  credits ("API $4.42 / $200 granted · until 16 Nov") and **today's API spend** per account,
  plus today's total over all accounts in the expanded header. Read-only; read for the account
  signed in to the console, every 10 minutes or on "Refresh now" — others keep their last value.
- **Last read** under every account (resets and API separately), so old numbers never look live.
- The expanded part under each account is a small label | value table — Weekly resets ·
  Fable resets · API credit · Last read — using the empty space under the account name.
- One-time notification when a granted API credit expires within 3 days.
- **Weekly and Fable % left side by side** in the accounts list (`WEEK · FABLE`); both roll over
  on their own when their reset time passes (`*`).
- Accounts that were only typed in and never signed in show **"not signed in"** instead of
  unconfirmed numbers, and are left out of the "use this first" hint. Expired API credit counts as 0.

### Fixed
- If the free-reset request is refused, the widget falls back to plain `/usage` and keeps the
  last known resets instead of showing 0.

## [1.5.6] — 2026-11-13

### Changed
- Free resets are no longer a column: **"Show free resets"** opens a second line under
  every account (the signed-in one too) as a small table — `↺ WEEKLY RESETS` and
  `↺ FABLE RESETS` side by side (count · earliest expiry, 0, or unknown).
- Accounts are listed by their **full e-mail** (several share the part before @);
  popup 470 pt.

### Added
- **"↻ Refresh now"** in the popup footer refreshes immediately without closing the menu.

## [1.5.5] — 2026-11-13

### Changed
- The signed-in account's free resets are shown only in the details block, not
  repeated in the accounts list; the "Show free resets" toggle hides when there is
  no other account.

### Fixed
- Reset times like …13:59:59 now read 14:00 (rounded to the nearest minute).

## [1.5.4] — 2026-11-13

### Added
- **Free resets per account:** a `↺ FREE` column (↺N · 0 · — unknown) and a
  "Show free resets" toggle that opens a line under every account
  ("1 weekly · until 11 Dec, 3 Fable · until 9 Mar") without closing the menu.

### Fixed
- The signed-in account's name could vanish (it wrapped below the row).
- Free resets of the same kind are grouped with their earliest expiry.

### Changed
- Popup is 420 pt wide.

## [1.5.3] — 2026-11-13

### Added
- **"Ring with the number inside"** menu-bar style (Settings → Icon): just a ring filled to
  your weekly % with the number in it — which account it is shows in the popup.

### Changed
- The `⏳ claude1` next-account hint in the menu bar is now optional and **off by default**
  (Settings → Icon → "Show the next account in the menu bar").

## [1.5.2] — 2026-11-13

### Changed
- The menu-bar hint reads `⏳ claude1` (same mark as the popup hint) instead of `→ claude1`,
  which looked like the signed-in account; hovering the title explains it.

## [1.5.1] — 2026-11-13

### Added
- **Hide or delete an account.** Click an account row and choose:
  *Hide* — it disappears from the list, hints and notifications (data kept; "Show hidden
  accounts (N)" brings it back), or *Delete* — the record is removed and is added again
  only when you sign in to that account.
- **App icon:** a weekly cycle — ring, reset arrow and a bold 7.

## [1.5.0] — 2026-11-12

### Added
- **Accounts section.** Every claude.ai account you sign in to on this Mac is remembered
  (`~/.claude-usage-widget-accounts.json`, local only). One line per account: weekly % left,
  weekly reset day/time and the monthly date. Signed-out accounts are dimmed and show the
  values from their last sign-in; hover a row for Fable, plan and free-reset details.
  Order = which account to use first.
- **"Use this account first" hint** in the popup, in the menu bar (`→ claude1`) and as a
  one-time notification when an account's unused weekly quota resets within 48 hours.
- **Free limit resets** that claude.ai grants (e.g. "One full limit reset", Fable resets):
  count and expiry date (`↺1`), read-only — the widget never uses one.
- **Current account details:** e-mail in the header, reset day/time, renewal or plan-end
  date, daily budget (quota left ÷ days left), where the week went (Claude Code / Chat /
  Cowork), and the Fable row with its share of the weekly limit.
- **Notifications** (each sent once): a cancelled plan ending within 3 days, an unused free
  reset expiring within 3 days. Threshold notifications are now tracked per account, so
  switching accounts no longer fires a false "crossed 90 %".

### Changed
- Popup is 380 pt wide; account columns have aligned headers.

### Fixed
- The trend chart was drawn upside down.
- Hidden rows (5-hour window, forecast, Sonnet) left large empty gaps in the popup.
- History mixed every signed-in account; samples are now tagged per account and the chart
  shows only the current one.

## [1.4.5] — 2026-10-14

### Fixed
- **HTTP 403 "permission_error" on accounts that also have an API (Console)
  organization.** Usage was read from the first organization in the list; when that was
  an API-only org, `/usage` answered 403 and the widget stopped updating. It now prefers
  the organization with the chat capability.

## [1.4.4] — 2026-09-16

### Fixed
- **macOS 27: "Cannot read browser cookie database".** macOS 27 no longer lets apps read
  another app's data (your browser's cookie file) without **Full Disk Access**, so the widget
  stopped updating right after the OS update and kept showing stale numbers.
  **What you need to do once:** System Settings → Privacy & Security → Full Disk Access →
  **+** → choose `ClaudeUsageWidget.app` (listed as **Claude Usage**) → turn it on.
- The widget now says exactly that ("Full Disk Access needed…") instead of the vague
  cookie-database error, in all 5 languages.
- The app always reported version 1.0.0, so the update checker could misreport. The version
  now comes from the release tag.
- A reset time that has already passed showed "reset left"; it now shows just "reset".

### Changed
- `build.sh` signs local builds with your Developer ID (when available), so the Full Disk
  Access grant survives rebuilds (ad-hoc signatures change on every build).

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
