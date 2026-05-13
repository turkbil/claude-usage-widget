# Claude Kullanım Widget'ı

[![En son sürüm](https://img.shields.io/github/v/release/turkbil/claude-usage-widget?label=indir&logo=github&color=d68c45)](https://github.com/turkbil/claude-usage-widget/releases/latest)
[![Lisans: MIT](https://img.shields.io/badge/Lisans-MIT-d68c45.svg)](LICENSE)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-d68c45?logo=apple)](#gereksinimler)
[![İmzalı & notarize](https://img.shields.io/badge/imzal%C4%B1%20%26%20notarize-evet-5dc97f?logo=apple)](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

**macOS menü çubuğu widget'ı** — Claude haftalık kullanımını tek bakışta gösteriyor. [claude.ai/settings/usage](https://claude.ai/settings/usage)'daki verinin aynısı, canlı menü çubuğunda, üstüne zengin bir dropdown.

> 💻 **Bu macOS sürümü.** Windows'ta mısın? → [**claude-usage-widget-windows**](https://github.com/turkbil/claude-usage-widget-windows)
>
> 🌐 [**English README**](README.md)  ·  Ücretsiz, açık kaynak (MIT), Apple imzalı binary [Releases sayfasında](https://github.com/turkbil/claude-usage-widget/releases/latest)

```
…  ☀︎ 22°C  🤖 %32  🔊  12:46           ← hava durumunun yanına oturur

┌──────────────────────────────────────────┐
│  Nurullah                    [Max 20x]   │  ← isim + plan rozeti
│  ────────────────────────────────────    │
│  BU HAFTA                3g 18s kaldı    │
│   Tüm modeller ████████░░░░░░░░░ %32     │
│   Sonnet       █░░░░░░░░░░░░░░░░  %2     │
│   ↗ Hafta sonu tahmini: %64              │  ← burn-rate tahmini
│   ╭───────●─ ─ ─ ─ ─ ─ ─◌╮               │  ← 7 günlük trend + projeksiyon
│  ────────────────────────────────────    │
│  5 SAATLİK PENCERE       2s 38dk kaldı   │
│   Kullanım     ██░░░░░░░░░░░░░░░░  %7    │
│  ────────────────────────────────────    │
│           Güncelleme: 12:46              │
│  ────────────────────────────────────    │
│    Ayarlar…                        ⌘,    │
│    Şimdi yenile                    ⌘R    │
│    claude.ai/settings/usage'ı aç   ⌘U    │
│    Çıkış                           ⌘Q    │
│    nurullah.net ↗      @nurullah ↗       │
└──────────────────────────────────────────┘
```

---

## Bu widget'ı farklı kılan ne?

Bir menü çubuğu uygulamasında genellikle yan yana bulunmayan birkaç özellik:

- 🍩 **Menü çubuğu başlığına gömülü donut halkalar.** Her veri minik bir halka olarak çizilebilir (ayrı pencere değil, popup değil — gerçekten başlığın içinde), ve her birinin rengini bağımsız seçersin.
- 🔮 **Burn-rate tahmini.** Dropdown sana "↗ Hafta sonu tahmini: %64" der, hafta ortasındayken. Hızın 100'ü aşıyorsa "⚠ Bu hızla yaklaşık 1g 8s sonra limit" olur.
- 📈 **İlk gün bile anlamlı görünen sparkline.** Veri birikmesini beklemek yerine, ilk yenilemeden itibaren `haftaBaşı (%0) → bugün (gerçek) → haftaSonu (tahmin, kesik)` çizer.
- 🤝 **Aynı binary'nin içine gömülü MCP server.** Claude Code'un kendisi `get_usage`'ı çağırıp uzun bir görev öncesi haftalık limitini görebilir. Tek JSON parçası, Claude Code'a tek restart.
- 🌐 **Yerel HTTP + CLI modları** — Raycast, Alfred, tmux, shell script'ler için. Aynı veri, üç farklı okuma yolu.
- 🦊 **Çoklu tarayıcı failover.** Chrome, Brave, Edge, Arc — sadece kullandıklarını aç; widget sırayla dener, geçerli claude.ai oturumu bulan ilk tarayıcı kazanır.
- 🔔 **Edge-triggered eşik bildirimleri.** Üç ayarlanabilir seviye (uyarı / alarm / kritik) **haftada her seviye için bir kez** tetiklenir — eşik etrafında dolaşırsan spam yok. Haftalık reset sonrası otomatik hazır olur.
- 🎚 **Gerçek bir ayarlar penceresi, iç içe submenu değil.** Tüm seçenekler tek bakışta. Özel emoji alanına tıkla, macOS Emoji Picker otomatik açılır.
- 🔐 **İmzalı & notarize — `xattr` numarası yok.** /Applications'a sürükle, çift tıkla, bitti.
- 🪙 **Üçüncü taraf servis yok.** Sparkle yok, Sentry yok, analytics endpoint yok, telemetri SDK'sı yok. Tek dışarı trafik claude.ai (kullanım verisi) ve api.github.com (günlük sürüm kontrolü, kapatılabilir).

---

## Özellikler

### Menü çubuğu başlığı
- 🎯 **Gerçek haftalık limit %** — claude.ai'ın kendi kullandığı API'den
- 🍩 **Veri bazlı görüntüleme** — `Haftalık %`, `Haftalık kalan süre`, `5 saatlik %`, `5 saatlik kalan süre` — her biri bağımsız olarak **gizlenebilir**, **yazı** olarak gösterilebilir, ya da seçtiğin renkte küçük bir **inline donut halka** olarak gösterilebilir
- 🤖 **Simge seçimi** — 8 emoji hazır seçenek, kendi özel emojin, yüzdeyi dolduran donut özet, ya da hiç simge yok

### Zengin dropdown
- 📊 Hesap başlığı (isim + plan rozeti — `Max 20x`, `Pro`, vb.)
- 🟢 Renkli yuvarlatılmış bar'lar (limite yaklaştıkça yeşil → sarı → turuncu → kırmızı)
- 🔮 **Burn-rate tahmini** — "↗ Hafta sonu tahmini: %64" veya "⚠ Bu hızla yaklaşık 1g 8s sonra limit"
- 📈 **Trend grafiği** — geçmiş örnekler + 7 günlük zaman çizelgesinde projeksiyon
- 🪟 5 saatlik rolling pencere için ayrı bölüm
- 🌍 **Otomatik dil** — English, Türkçe, Deutsch, Español, Français

### Ayarlar penceresi (⌘,)
- Tüm tercihler tek bakışta, iç içe menü yok
- Eşik bildirimleri (uyarı / alarm / kritik) — slider'larla ayarlanır
- Yenileme aralığı (30sn · 1dk · 5dk · 10dk)
- **Genel klavye kısayolu** — dropdown'ı her yerden aç (varsayılan ⌥⌘U)
- **Çoklu tarayıcı cookie kaynağı** — Chrome · Brave · Edge · Arc (tüm Chromium kardeşleri)

### Entegrasyon
- 🤝 **MCP sunucu modu** — Claude Code'un kendisi `get_usage` aracı ile haftalık limitini görebilir
- 🌐 **Yerel HTTP endpoint** `127.0.0.1:9123` üzerinde — Raycast/Alfred/tmux entegrasyonları için
- 🖥 **CLI mod** — `ClaudeUsageWidget --print-usage` shell script'leri için JSON döker

### Detay
- ✅ **Apple Developer ID ile imzalı & notarize** — Gatekeeper uyarısı yok
- 🪶 Boştayken ~%0 CPU
- 🔒 **Hiçbir şifre saklamaz** — mevcut tarayıcı cookie'sini macOS Keychain üzerinden okur, tarayıcının kendi kullandığı yol
- 🔄 **Otomatik sürüm kontrolü** GitHub Releases üzerinden (Sparkle yok, üyelik yok, üçüncü taraf yok)

---

## Hızlı kurulum

1. [**Releases sayfasından**](https://github.com/turkbil/claude-usage-widget/releases/latest) en son `ClaudeUsageWidget.zip`'i indir
2. Aç → `ClaudeUsageWidget.app`'i `/Applications`'a sürükle
3. Çift tıkla. Binary imzalı ve notarize olduğu için macOS uyarısız açar.
4. (İsteğe bağlı) Menü çubuğu simgesi → Ayarlar → açılışta başlatmayı aç, **kısayolunu** ayarla, eşikleri yapılandır, vb.

### Açılışta otomatik başlatma

```bash
cp install/local.claude-usage-widget.plist ~/Library/LaunchAgents/
# .app'in yolu /Applications dışındaysa plist içinden düzenle
launchctl load -w ~/Library/LaunchAgents/local.claude-usage-widget.plist
```

### Kaldırma

```bash
launchctl unload ~/Library/LaunchAgents/local.claude-usage-widget.plist 2>/dev/null
rm -rf /Applications/ClaudeUsageWidget.app \
       ~/Library/LaunchAgents/local.claude-usage-widget.plist \
       ~/.claude-usage-widget-cache.json \
       ~/.claude-usage-widget-history.json
defaults delete app.claude-usage-widget 2>/dev/null
```

---

## Gereksinimler

| Bileşen | Neden |
|---|---|
| **macOS 12+** | Native Cocoa uygulaması |
| **Chromium tabanlı tarayıcı** + aktif claude.ai oturumu | Widget `sessionKey`'i tarayıcının cookie deposundan okur. Chrome, Brave, Edge ve Arc desteklenir — Ayarlar → Tarayıcılar'dan aç/kapat. |
| **Claude.ai hesabı** (Free, Pro, Max — herhangi bir plan) | Gösterilecek veri için |

> **Tarayıcı eklentisi yok, API key yok, masaüstü Claude uygulaması yok.** Sadece tarayıcı + claude.ai'da açık oturum.

İlk açılışta macOS, tarayıcı cookie anahtarını okumak için **Keychain izni** ister. **Always Allow / Her zaman izin ver** seç.

---

## Ayarlar özet

Dropdown'u aç → **Ayarlar…** (⌘,)

| Bölüm | İçerik |
|---|---|
| **Başlık içeriği** | `Haftalık %`, `Haftalık kalan süre`, `5 saatlik %`, `5 saatlik kalan süre` — her biri için: gizle / yazı / donut. Donut'ta 8 renkten seç. |
| **Simge** | Hazır emoji (🤖🧠⚡✨◉●▲◐), özel emoji (alana tıklayınca macOS Emoji Picker otomatik açılır), donut özet, ya da simge yok. |
| **Yenileme aralığı** | 30 sn · 1 dk · 5 dk · 10 dk |
| **Bildirimler** | Eşik bildirimlerini etkinleştir. Üç seviye macOS-native bildirim (uyarı / alarm / kritik). Her seviye haftada bir kez tetiklenir (reset sonrası yeniden hazır olur). |
| **Klavye kısayolu** | Genel kısayolu aç/kapat. Varsayılan ⌥⌘U dropdown'u her yerden açar. |
| **Tarayıcılar** | Chrome, Brave, Edge, Arc'ı aç/kapat. Widget etkin olanları sırayla dener; geçerli oturum bulan ilk tarayıcı kazanır. |
| **Ağ & entegrasyon** | Günlük güncelleme kontrolü · Yerel HTTP endpoint :9123 · MCP kurulum talimatları |

---

## Entegrasyon (diğer araçlar)

### MCP — Claude Code kendi limitini görür
Ayarlar → "MCP kurulum talimatları…" `~/.claude.json` dosyasına yapıştıracağın JSON parçasını verir:

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

Claude Code'u yeniden başlattıktan sonra Claude `get_usage`'ı çağırıp haftalık limitini görebilir — uzun bir görev öncesi faydalı.

### Yerel HTTP — Raycast/Alfred/tmux için
Ayarlar → **"Yerel HTTP endpoint (:9123)"**'i aç:

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

Sadece `127.0.0.1` üzerinde dinler. Dışarıya hiçbir zaman açılmaz.

### CLI — tek seferlik JSON
```bash
$ /Applications/ClaudeUsageWidget.app/Contents/MacOS/ClaudeUsageWidget --print-usage
```
Aynı JSON, hemen çıkar. Shell script'leri, statusline'lar için.

---

## Kaynaktan derleme

Xcode Command Line Tools gerekir.

```bash
git clone https://github.com/turkbil/claude-usage-widget.git
cd claude-usage-widget
./build.sh
open ClaudeUsageWidget.app
```

Build imzasız bir `.app` üretir. Resmi imzalı/notarize binary için Releases sayfasını kullan.

---

## Nasıl çalışıyor?

```
┌──────────────────┐    SQLite + AES-128-CBC      ┌─────────────────┐
│  Tarayıcı cookie │ ────────────────────────────▶│  sessionKey     │
│  (şifreli)       │  anahtar macOS Keychain'den  │  (çözülmüş)     │
└──────────────────┘                              └────────┬────────┘
                                                           │
                                          Cookie: sessionKey=...
                                                           ▼
                            ┌──────────────────────────────────────────┐
                            │ GET claude.ai/api/organizations/{id}/    │
                            │     usage  (seven_day.* + five_hour.*)   │
                            │ GET claude.ai/api/account     (isim)     │
                            │ GET claude.ai/api/.../rate_limits (plan) │
                            └────────────────┬─────────────────────────┘
                                             ▼
                              ┌──────────────────────────────┐
                              │  Menü çubuğu UI · 60s'de yen │
                              │  + 5dk'da bir history örneği │
                              │  + eşik bildirimleri         │
                              │  + sparkline trend           │
                              └──────────────────────────────┘
```

Widget şifreni asla görmez. Tarayıcının kendisinin kullandığı şifreli-cookie + Keychain mantığını kullanır — macOS'taki her tarayıcı saklanmış cookie'ler için aynı şeyi yapar.

---

## Gizlilik

- **Telemetri yok.** Analytics yok. Üçüncü taraf çökme raporu yok. Tek dışarı çıkan trafik claude.ai'a HTTPS (kullanım verisi) ve günde bir kez `api.github.com`'a (sürüm kontrolü, kapatılabilir).
- **Cookie diske yazılmaz.** Sadece bellekte.
- **Saklanan dosyalar** (toplam ~70 KB):
  - `~/.claude-usage-widget-cache.json` — son snapshot
  - `~/.claude-usage-widget-history.json` — 14 günlük sparkline örnekleri
- **Ayarlar** `defaults` (UserDefaults) içinde.

---

## Diller

Widget macOS tercih edilen dilini otomatik algılar, İngilizce'ye geri düşer.

| | |
|---|---|
| 🇬🇧 | English (varsayılan) |
| 🇹🇷 | Türkçe |
| 🇩🇪 | Deutsch |
| 🇪🇸 | Español |
| 🇫🇷 | Français |

Dil eklemek için `Resources/en.lproj/Localizable.strings`'i `Resources/<kod>.lproj/Localizable.strings` olarak kopyala, değerleri çevir, `build.sh` içindeki `CFBundleLocalizations`'a kodu ekle, PR aç.

---

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `🤖 ?` + "claude.ai oturumu yok" | Tarayıcını aç, claude.ai'a giriş yap. Giriş yaptığın tarayıcının Ayarlar → Tarayıcılar'da etkin olduğundan emin ol. |
| `🤖 ?` + "Keychain erişimi reddedildi" | İlk açılışta Keychain prompt'u çıkar — **Always Allow** de. Resetlemek için: Keychain Access → "Chrome Safe Storage" → Access Control → ClaudeUsageWidget'ı ekle. |
| `HTTP 401` | claude.ai oturumun süresi dolmuş. Tarayıcında yeniden giriş yap. |
| Eski yüzde | Dropdown → **Şimdi yenile** (⌘R) |
| Menü çubuğunda hiçbir şey yok | `/tmp/claude-usage-widget.err.log`'a bak. Uygulama çalışıyor mu (`pgrep ClaudeUsageWidget`). |
| Çökme | macOS otomatik olarak `~/Library/Logs/DiagnosticReports/`'a crash log yazar. GitHub'da issue aç, log'u yapıştır. |

---

## İpuçları & püf noktaları

- **Hızlı aç:** ⌥⌘U her yerden dropdown'u açar (Ayarlar'dan değiştirilebilir).
- **Donut + yazı gizli** = en temiz menü çubuğu görünümü. Her veriyi farklı renkte "Donut" yap → menü çubuğunda 4 ufak halka, sayı kalabalığı yok.
- **Polling'i yavaşlat:** pildeyken yenileme aralığını 10 dk yap — saatlik API çağrısı 6'ya düşer.
- **Terminal alias'ı:** `alias claude-status='ClaudeUsageWidget --print-usage | jq .weekly_utilization_pct'` ekle.
- **Tahmin %100'ü geçince:** dropdown kırmızı "bu hızla X süre sonra limit" mesajına döner — yavaşlama vakti.
- **Çoklu tarayıcı:** iş için bir tarayıcı, kişisel için başka kullanıyorsan ikisini de aç — widget hangisinde claude.ai oturumu varsa ondan okur.

---

## Proje yapısı (katkı sağlayanlar için)

```
.
├── Sources/                 13 Swift dosyası
│   ├── main.swift           # AppDelegate, popup, menu, refresh döngüsü
│   ├── Preferences.swift    # Codable ayarlar + UserDefaults store
│   ├── SettingsWindow.swift # Tüm tercihleri içeren NSWindow
│   ├── TitleRenderer.swift  # Menü çubuğu başlığı için NSAttributedString
│   ├── DonutImage.swift     # Inline donut NSImage çizer
│   ├── BrowserCookieReader.swift   # Chrome/Brave/Edge/Arc cookie decrypt
│   ├── ClaudeApi.swift      # claude.ai API client (şu an main.swift içinde)
│   ├── Forecast.swift       # Burn-rate projeksiyon mantığı
│   ├── UsageHistory.swift   # Sparkline örnek buffer'ı (14 günlük cap)
│   ├── NotificationManager.swift   # Eşik bildirimleri (UserNotifications)
│   ├── HotKeyManager.swift  # Carbon RegisterEventHotKey wrapper'ı
│   ├── VersionChecker.swift # Günlük GitHub Releases polling
│   ├── LocalHTTPServer.swift       # 127.0.0.1:9123 üzerinde NWListener
│   ├── MCPServer.swift      # JSON-RPC over stdio
│   └── CLIRunner.swift      # --print-usage one-shot modu
├── Resources/{en,tr,de,es,fr}.lproj/Localizable.strings
├── .github/workflows/release.yml   # Tag push'unda imzala + notarize + yayınla
├── build.sh                 # .app derler
├── install/local.claude-usage-widget.plist   # LaunchAgent template
└── docs/feature-preview.html       # Tasarım önizleme / katalog
```

---

## Yazar

**Nurullah Okatan** — [nurullah.net](https://www.nurullah.net) · [@nurullah](https://x.com/nurullah)

## Lisans

[MIT](LICENSE) © Nurullah Okatan

Anthropic ile bağlı değildir. "Claude", Anthropic'in markasıdır.
