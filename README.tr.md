# Claude Kullanım Widget'ı

[![En son sürüm](https://img.shields.io/github/v/release/turkbil/claude-usage-widget?label=indir&logo=github&color=d68c45)](https://github.com/turkbil/claude-usage-widget/releases/latest)
[![Lisans: MIT](https://img.shields.io/badge/Lisans-MIT-d68c45.svg)](LICENSE)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-d68c45?logo=apple)](#gereksinimler)
[![İmzalı & notarize](https://img.shields.io/badge/imzal%C4%B1%20%26%20notarize-evet-5dc97f?logo=apple)](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

macOS menü çubuğunda Claude haftalık kullanım yüzdeni ve reset'e kalan süreyi gösteren native bir widget. Hava durumu simgesinin yanına oturur, tek bakışta görürsün.

> Windows'ta mısın? → [**claude-usage-widget-windows**](https://github.com/turkbil/claude-usage-widget-windows)

[**English README →**](README.md)

```
┌──────────────────────────────────────────┐
│  Nurullah                    [Max 20x]   │
│  ────────────────────────────────────    │
│  BU HAFTA                3g 18s kaldı    │
│   Tüm modeller ████████░░░░░░░░░ %32     │
│   Sonnet       █░░░░░░░░░░░░░░░░  %2     │
│  ────────────────────────────────────    │
│  5 SAATLİK PENCERE       2s 38dk kaldı   │
│   Kullanım     ██░░░░░░░░░░░░░░░░  %7    │
│  ────────────────────────────────────    │
│           Güncelleme: 12:46              │
│  ────────────────────────────────────    │
│  ☐ Kalan süreyi yanında göster           │
│    Şimdi yenile                   ⌘R     │
│    claude.ai/settings/usage'ı aç  ⌘U     │
│    Çıkış                          ⌘Q     │
└──────────────────────────────────────────┘
```

## Özellikler

- 🎯 **Gerçek Claude haftalık limit** — [claude.ai/settings/usage](https://claude.ai/settings/usage) sayfasında gördüğün `% used` rakamının aynısı
- ⏱ **Reset'e geri sayım** — Menü çubuğunda "3g 18s kaldı" (opsiyonel)
- 🪟 **5 saatlik pencere** — Kısa dönem limit için ayrı bar
- 🎨 **Renkli barlar** — Limite yaklaştıkça yeşil → sarı → turuncu → kırmızı
- 🌍 **Otomatik dil** — English, Türkçe, Deutsch, Español, Français (macOS dilini takip eder)
- 🪶 **Boştayken ~%0 CPU** — Dakikada bir poll, `~/.claude/projects` değişikliklerinde anlık
- 🔒 **Şifre saklamaz** — Chrome'un mevcut oturum cookie'sini macOS Keychain üzerinden okur
- 🚀 **Açılışta otomatik başlar** — LaunchAgent olarak yüklenir

## Gereksinimler

| Bileşen | Neden |
|---|---|
| **macOS 12.0+** | Native Cocoa uygulaması |
| **Xcode Command Line Tools** | Swift derleyici için |
| **Google Chrome** + aktif claude.ai oturumu | Widget `sessionKey`'i Chrome'un cookie deposundan okur |
| **Claude.ai hesabı** (Free, Pro, Max — herhangi bir plan) | Gösterilecek haftalık veri için |

> **Tarayıcı eklentisi gerekmez, API key gerekmez, masaüstü Claude uygulaması gerekmez.** Sadece Chrome + claude.ai'da açık oturum.

Chrome'da claude.ai'ya giriş yapmadıysan widget `⚠︎ claude.ai oturumu yok — Chrome'da giriş yap` gösterir.

## Kurulum

```bash
git clone https://github.com/YOUR_USERNAME/claude-usage-widget.git
cd claude-usage-widget
./build.sh
open ClaudeUsageWidget.app
```

İlk açılışta macOS Chrome'un cookie şifreleme anahtarını okumak için **Keychain erişim izni** isteyecek. **Always Allow / Her zaman izin ver** de. (Bu Chrome'un kendi kullandığı anahtarın aynısı — widget Chrome'un göremediği hiçbir şeyi göremez.)

### Açılışta otomatik başlat

```bash
cp install/local.claude-usage-widget.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/local.claude-usage-widget.plist
```

> `.app`'i `~/ClaudeUsageWidget/` dışında bir yere koyduysan plist içindeki yolu düzenle.

### Kaldırma

```bash
launchctl unload ~/Library/LaunchAgents/local.claude-usage-widget.plist
rm -rf ~/ClaudeUsageWidget ~/Library/LaunchAgents/local.claude-usage-widget.plist ~/.claude-usage-widget-cache.json
defaults delete app.claude-usage-widget 2>/dev/null
```

## Nasıl çalışıyor?

```
┌──────────────────┐    SQLite + AES-128-CBC      ┌─────────────────┐
│  Chrome cookie   │ ────────────────────────────▶│  sessionKey     │
│  (şifreli)       │   anahtar macOS Keychain'den │  (çözülmüş)     │
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
                                      │  Menü çubuğu UI │
                                      │  60s'de yenilir │
                                      └─────────────────┘
```

Widget şifreni asla görmez. Chrome'un kendi kullandığı şifreli-cookie + Keychain mantığını kullanır — macOS'taki her tarayıcı saklanmış cookie'ler için aynı şeyi yapar.

## Ayarlar

| Ayar | Yer | Notlar |
|---|---|---|
| Menü çubuğu başlığında geri sayım | Menü → "Kalan süreyi yanında göster" | Varsayılan kapalı. `defaults` (UserDefaults) içinde saklanır. |
| Renk eşikleri | `Sources/main.swift` → `UsageRowView.colorFor` | Varsayılan: yeşil <50, sarı <75, turuncu <90, kırmızı ≥90 |
| Yenileme aralığı | `Sources/main.swift` → `AppConfig.pollIntervalSec` | Varsayılan: 60s |

## Diller

Widget macOS tercih edilen dilini otomatik algılar ve İngilizce'ye geri düşer. Mevcut diller:

- 🇬🇧 English (varsayılan)
- 🇹🇷 Türkçe
- 🇩🇪 Deutsch
- 🇪🇸 Español
- 🇫🇷 Français

Dil eklemek için: `Resources/en.lproj/Localizable.strings`'i `Resources/<kod>.lproj/Localizable.strings` olarak kopyala, değerleri çevir, `build.sh` içindeki `CFBundleLocalizations`'a kodu ekle ve PR aç.

## Gizlilik & güvenlik

- **Telemetri yok.** Widget her yenilemede tam olarak iki HTTPS çağrısı yapar, ikisi de `claude.ai`'ya. Başka hiçbir şey makineden çıkmaz.
- **Üçüncü taraflara veri gönderilmez.** Oturum cookie'n yerel olarak okunur ve sadece `claude.ai`'a karşı kullanılır.
- **Cookie diske yazılmaz.** Sadece bellekte yaşar.
- **Cache şunları içerir**: haftalık/5-saatlik kullanım yüzdeleri, reset zaman damgaları, görünen adın, plan etiketin. `~/.claude-usage-widget-cache.json`'da.

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `🤖 ?` + "claude.ai oturumu yok" | Chrome'u aç, claude.ai'a giriş yap |
| `🤖 ?` + "Keychain erişimi reddedildi" | İlk açılışta Keychain prompt'u çıkar — **Always Allow** de. Resetlemek için: Keychain Access → "Chrome Safe Storage" → Access Control → ClaudeUsageWidget'ı ekle |
| `HTTP 401` | claude.ai oturumun süresi dolmuş. Chrome'da tekrar giriş yap. |
| Eski yüzde | Menüye tıkla, "Şimdi yenile" |
| Menü çubuğunda hiçbir şey yok | `/tmp/claude-usage-widget.err.log`'a bak |

## Yazar

**Nurullah Okatan** tarafından geliştirildi — [nurullah.net](https://www.nurullah.net)

## Lisans

[MIT](LICENSE) © Nurullah Okatan

Anthropic ile bağlı değildir. "Claude", Anthropic'in markasıdır.
