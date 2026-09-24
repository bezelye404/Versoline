# Faz 0: Ön Kontrol ve Envanter Raporu (Preflight)

Bu rapor, [VERSOLINE.md](../../VERSOLINE.md) Faz 0 yönergeleri uyarınca hiçbir dosya veya yapılandırma değiştirilmeden, salt-okunur (read-only) inceleme ve sorgulamalarla hazırlanmıştır.

---

## 1. Yetki Kontrolü

| Kontrol | Durum | Detay |
| :--- | :--- | :--- |
| **`gh` CLI Durumu** | ✅ Kurulu ve Giriş Yapılmış | GitHub CLI (`/opt/homebrew/bin/gh`) kuruldu ve `bezelye404` kullanıcısıyla SSH/OAuth üzerinden doğrulandı. |
| **Admin Yetki Durumu** | ✅ Doğrulandı (`viewerPermission: ADMIN`) | `gh repo view bezelye404/easyRSS --json viewerPermission` sorgusu ile depoda doğrudan yönetici (ADMIN) yetkisine sahip olunduğu teyit edildi. |
| **Eylem** | 🚀 CLI ile otomatik gerçekleştirilebilir | Faz 2'deki GitHub repo yeniden adlandırma (`gh repo rename`) ve metadata güncelleme işlemleri doğrudan CLI üzerinden çalıştırılabilir. |

---

## 2. İsim Müsaitliği ve Marka Çakışması

| Kaynak / Alan | Sorgu / URL | Sonuç | Durum |
| :--- | :--- | :--- | :--- |
| **GitHub Kullanıcı Reposu** | `https://api.github.com/repos/bezelye404/versoline` | HTTP 404 (Not Found) | ✅ **Müsait** (Doğrudan yeniden adlandırılabilir) |
| **GitHub Genel Arama** | `https://api.github.com/search/repositories?q=versoline` | `total_count: 0` | ✅ **Tamamen Özgün** (Çakışan repo yok) |
| **Homebrew Cask / Formula** | `brew search versoline` | Formül veya Cask bulunamadı | ✅ **Müsait** |
| **Yazılım & Marka Çakışması** | Web & Ticari Marka Taraması | Yalnızca Multiform Lighting firmasının "VersoLine" isimli LED batten aydınlatma donanımı mevcuttur. Herhangi bir Mac yazılımı, RSS okuyucu veya genel tüketici uygulaması çakışması **yoktur**. | ✅ **Temiz** |
| **Alan Adı: `versoline.app`** | Google Registry RDAP (`pubapi.registry.google`) | `errorCode: 404, title: "Not Found"` | ✅ **Kayıt Edilebilir (Müsait)** |
| **Alan Adı: `versoline.dev`** | Google Registry RDAP (`pubapi.registry.google`) | `errorCode: 404, title: "Not Found"` | ✅ **Kayıt Edilebilir (Müsait)** |
| **Alan Adı: `versoline.com`** | VeriSign / GoDaddy WHOIS | 2017-09-14 tarihinde kaydedilmiş, GoDaddy Domains By Proxy ile gizlenmiş park sayfası. | ⚠️ **Dolu (Alternatif TLD'ler müsait)** |

---

## 3. Mevcut Adın Kod İçi Envanteri (`easyrss` / `easy rss`)

Kod tabanındaki tüm eşleşmeler kategorize edilmiştir:

### (a) Kullanıcıya Görünen Metinler (UI, Menü, Dialoglar)
- `Sources/EasyRSSApp.swift:117` — Menü çubuğu popover başlığı: `Text("easyRSS")` -> `Text("Versoline")`
- `Sources/EasyRSSApp.swift:140` — Menü çubuğu butonu: `Button("Open easyRSS")` -> `Button("Open Versoline")`
- `Sources/EasyRSSApp.swift:155` — Menü çubuğu butonu: `Button("Quit easyRSS")` -> `Button("Quit Versoline")`
- `Sources/Views/Settings/SettingsView.swift:155` — Ayarlar açıklaması: `"Keeps an easyRSS status icon in your macOS top menu bar..."` -> `"Keeps a Versoline status icon..."`
- `Sources/Views/ConsoleView.swift:316` — Kayıt dosya adı varsayılanı: `panel.nameFieldStringValue = "easyRSS_debug_logs.txt"` -> `"versoline_debug_logs.txt"`
- `Sources/Views/ContentView.swift:263` — OPML dışa aktarma adı varsayılanı: `panel.nameFieldStringValue = "easyRSS_subscriptions.opml"` -> `"versoline_subscriptions.opml"`
- `Sources/Views/ArticleDetailView.swift:1115, 1200` — Alıntı kartı feed başlığı fallback'i: `feedTitle ?? "easyRSS"` -> `feedTitle ?? "Versoline"`
- `Sources/Views/ArticleDetailView.swift:1261` — Alıntı kartı altbilgi metni: `Text("easyRSS")` -> `Text("Versoline")`
- `Sources/Services/OPMLManager.swift:36` — OPML XML başlığı: `<title>easyRSS Subscriptions</title>` -> `<title>Versoline Subscriptions</title>`
- `project.yml:40` — `INFOPLIST_KEY_CFBundleDisplayName: EasyRSS` -> `Versoline`

### (b) Bundle / Ürün / Scheme / Target Adı
- `project.yml:1` — Proje adı: `name: EasyRSS` -> `name: Versoline`
- `project.yml:25` — Target adı: `targets: EasyRSS:` -> `targets: Versoline:`
- `project.yml:36` — `PRODUCT_NAME: EasyRSS` -> `PRODUCT_NAME: Versoline`
- `project.yml:37` — `PRODUCT_BUNDLE_IDENTIFIER: com.bezelye.EasyRSS` (🛑 **GATE 0 kararı**)
- `project.yml:32, 46` — Entitlements dosya referansı: `Sources/Resources/EasyRSS.entitlements` -> `Sources/Resources/Versoline.entitlements`
- `Sources/EasyRSSApp.swift:6` — `@main` Struct adı: `struct EasyRSSApp: App` -> `struct VersolineApp: App`
- `EasyRSS.xcodeproj` — Xcode proje dizini adı (`xcodegen generate` sonrası `Versoline.xcodeproj` olarak üretilecek)
- `Sources/Resources/EasyRSS.entitlements` — Dosya adı yeniden adlandırılacak

### (c) Dosya Sistemi Yolları (Application Support, Önbellek, İndirilenler)
- `Sources/Services/FeedStore.swift:106` — `appSupport.appendingPathComponent("EasyRSS", isDirectory: true)` -> `Versoline`
- `Sources/Services/FaviconService.swift:26` — `appSupport.appendingPathComponent("EasyRSS/Favicons", isDirectory: true)` -> `Versoline/Favicons`
- `Sources/Services/FaviconService.swift:184` — `appSupport.appendingPathComponent("EasyRSS/ImageCache_v1", isDirectory: true)` -> `Versoline/ImageCache_v1`
- `Sources/Services/PodcastDownloadService.swift:24` — `appSupport.appendingPathComponent("EasyRSS/Downloads", isDirectory: true)` -> `Versoline/Downloads`
- `Sources/Services/ReaderModeExtractor.swift:22` — `appSupport.appendingPathComponent("EasyRSS/ReaderCache_v3", isDirectory: true)` -> `Versoline/ReaderCache_v3`
- `Sources/Services/CuratedFeedManager.swift:29` — `appSupport.appendingPathComponent("EasyRSS", isDirectory: true)` -> `Versoline`
- `Sources/Services/Sync/ICloudDriveSyncEngine.swift:43` — `appSupport.appendingPathComponent("EasyRSS/Sync", isDirectory: true)` -> `Versoline/Sync`
- `Sources/Services/Sync/ICloudDriveSyncEngine.swift:33` — `cloudDocsParent.appendingPathComponent("easyRSS", isDirectory: true)` -> `Versoline` (iCloud Drive dizini)

### (d) UserDefaults, UTI, URL Scheme, Notification & Sistem Tanımlayıcıları
- `Sources/EasyRSSApp.swift:56, 76` ve `Sources/Services/FeedStore.swift:120, 130` — Bildirim adları: `Notification.Name("EasyRSSCompactMemory")` & `Notification.Name("EasyRSSDeepCompactMemory")` -> `VersolineCompactMemory` / `VersolineDeepCompactMemory`
- `Sources/Services/ContentBlockerService.swift:10` — WebKit kural listesi ID: `ruleListIdentifier = "EasyRSSContentBlockerRules-v6"` -> `"VersolineContentBlockerRules-v1"`
- `Sources/Services/Sync/LocalPeerSyncEngine.swift:9` — Bonjour Multipeer servis tipi: `serviceType = "easyrss-sync"` -> `"versoline-sync"` (maksimum 15 karakter kuralına uygundur)
- `Sources/Services/Sync/ICloudDriveSyncEngine.swift:13` — Kuyruk etiketi: `q.name = "com.bezelye.easyRSS.iCloudSyncQueue"` -> `"com.bezelye.versoline.iCloudSyncQueue"`
- `Sources/Services/NetworkMonitor.swift:12` — Kuyruk etiketi: `DispatchQueue(label: "com.bezelye.EasyRSS.networkMonitor")` -> `com.bezelye.Versoline.networkMonitor`
- `Sources/Services/AppLogger.swift:72` — OSLog subsystem: `Logger(subsystem: "com.bezelye.EasyRSS", category: "App")` -> (Bundle ID ile eşleşir)
- `Sources/Services/RSSParser.swift:142` — Hata domain'i: `NSError(domain: "EasyRSSNetwork", ...)` -> `"VersolineNetwork"`
- `Sources/Services/RSSParser.swift:41, 103, 105` & `FaviconService.swift:106, 301` & `CuratedFeedManager.swift:81` — HTTP `User-Agent`: `"EasyRSS/1.0"` -> `"Versoline/1.0"` ve Reddit bot tanıtımı `VersolineApp`

### (e) Build / Release Betikleri, CDN & Konfigürasyon
- `Sources/Services/CuratedFeedManager.swift:25` — Manifest CDN adresi: `https://raw.githubusercontent.com/bezelye404/easyRSS/main/...` -> `bezelye404/versoline`
- `project.yml` içindeki tüm derleme ayarları

### (f) Dokümantasyon
- `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `guide.md`, `animguide.md`, `animlist.md`, `rss.md` dosyalarındaki proje adı, klonlama adresleri ve build komutları.

### (g) Tarihsel Referanslar (Korunacaklar)
- `Sources/Services/ReaderModeExtractor.swift:37, 41` — Eski `EasyRSS` önbelleklerini temizleyen geriye dönük uyumluluk kodu.
- `CHANGELOG.md` geçmiş sürümleri (`0.1`, `0.2`, `0.2.1`, `0.2.2`, `0.2.3`, `0.2.4`).
- Yeni yazılacak `LegacyMigration` servisindeki `EasyRSS` dosya yolu sabiti ve "formerly easyRSS" açıklamaları.

---

## 4. Build, Release ve İmza Durumu

| Bileşen | Bulgular |
| :--- | :--- |
| **Mevcut `.dmg` Üretim Yöntemi** | Depoda otomatik CI/CD workflow'u bulunmamaktadır. Release paketleri yerel ortamda (`xcodebuild` ile Release derlemesi sonrasında) Homebrew üzerinden kurulu `/opt/homebrew/bin/create-dmg` aracı veya `hdiutil` ile manuel üretilmektedir. |
| **DMG İncelemesi (`EasyRSS-0.2.4.dmg`)** | - Format: UDZO (zlib sıkıştırılmış, GUID partition, HFS+ dosya sistemi).<br>- İçerik: `EasyRSS.app`, `Applications -> /Applications` symlink, Finder pencere düzenini sağlayan `.DS_Store`. |
| **İmza Durumu (`codesign`)** | `Signature=adhoc` (`flags=0x10002(adhoc,runtime)`). `TeamIdentifier=not set`. Geliştirici kimliğiyle imzalanmamıştır. |
| **Gatekeeper Durumu (`spctl`)** | `spctl -a -vv EasyRSS.app`: **rejected** (Ad-hoc imzalı olduğu için Apple tarafından tanınan bir Developer ID içermez). |
| **Notarization Durumu (`stapler`)** | `xcrun stapler validate EasyRSS.app`: **Bilet (ticket) iliştirilmemiştir** (Notarize edilmemiştir). |
| **Mimari** | `Mach-O thin (arm64)` (veya derleme parametrelerine göre Apple Silicon / Universal). |

---

## 5. Bundle Identifier ve Depolama Mimarisi

- **Mevcut Bundle Identifier:** `com.bezelye.EasyRSS`
- **Sandbox Durumu:** **Aktif (`com.apple.security.app-sandbox = true`)**
  - Entitlements:
    - `com.apple.security.network.client: true` (RSS/Medya akışı için)
    - `com.apple.security.files.user-selected.read-write: true` (OPML import/export, debug log kaydetme için)
    - `com.apple.security.temporary-exception.files.home-relative-path.read-write: ["/Library/Mobile Documents/com~apple~CloudDocs/"]` (iCloud senkronizasyonu için)
- **Fiziksel Veri Depolama Konumu:**
  - Sandboxed uygulama olduğu için `urls(for: .applicationSupportDirectory, in: .userDomainMask)` çağrısı şu dizini döndürür:
    `~/Library/Containers/com.bezelye.EasyRSS/Data/Library/Application Support/`
  - Uygulama bunun altına `EasyRSS/` klasörünü açmaktadır.
  - **Kritik Mimari Not:** Sandbox nedeniyle, eğer Bundle ID `com.bezelye.Versoline` olarak değiştirilirse macOS uygulamayı **farklı bir sandbox konteynerine** (`~/Library/Containers/com.bezelye.Versoline/`) hapseder. Yeni sandbox konteyneri eski konteyneri okuma iznine sahip olmayabilir. Ancak Bundle ID **`com.bezelye.EasyRSS` olarak korunursa**, konteyner aynı kalır ve `Application Support` içerisindeki `EasyRSS` klasörü sorunsuzca `Versoline` klasörüne klonlanabilir/taşınabilir.
- **UserDefaults:** Tamamen `UserDefaults.standard` kullanılmaktadır. Bundle ID korunursa tüm kullanıcı tercihleri (temalar, okuma durumu, ayarlar) sıfırlanmadan aynen korunur.
- **Keychain / SMAppService / URL Scheme:** Kod tabanında Keychain, LoginItem veya özel URL Scheme kullanılmamaktadır.

---

## 6. GitHub Tarafı Envanteri

- **Workflows (`.github/workflows`):** Mevcut değil (tüm build ve release'ler yerel üretilmektedir).
- **GitHub Pages:** Kapalı (`has_pages: false`).
- **Discussions & Wiki:** Kapalı (`has_discussions: false`, `has_wiki: false`).
- **Issues:** Açık (`has_issues: true`, açık issue sayısı: 0).
- **Mevcut Release Listesi:**
  - `v0.1` -> `EasyRSS.dmg`
  - `v0.2` -> `EasyRSS.dmg`
  - `v0.2.x` -> `EasyRSS-0.2.2.dmg`
  - `v0.2.4` (yerel etiket ve DMG dosyası)
  *(Eski release'ler silinmeyecek veya değiştirilmeyecektir)*
- **Secrets:** CI workflow bulunmadığından GitHub Actions secret'ı kullanılmamaktadır.

---

## 7. Homebrew Cask Politikası Doğrulaması

Homebrew Cask deposunun güncel Gatekeeper ve imzalama politikası araştırılmıştır:

1. **Zorunlu Gatekeeper Uyumluluğu:** `homebrew/cask` resmi deposu, eklenen tüm uygulamaların macOS Gatekeeper kontrollerini doğrudan geçmesini şart koşmaktadır.
2. **Apple Developer ID & Notarization Şartı:** Resmi depoya kabul edilmek için uygulamanın geçerli bir Apple Developer ID sertifikası ile imzalanmış ve Apple Notary Service tarafından onaylanmış (notarized) olması **zorunludur**.
3. **İmzasız / Ad-hoc Uygulamalar:** Ad-hoc imzalı (`CODE_SIGN_IDENTITY: "-"`) uygulamalar resmi Homebrew Cask deposundan kesin olarak reddedilmektedir.
4. **Çözüm ve Dağıtım Yolu:**
   - **Kişisel Homebrew Tap:** `bezelye404/homebrew-tap` oluşturularak kullanıcıların `brew install --cask bezelye404/tap/versoline` ile yüklemesi sağlanabilir.
   - **Gatekeeper Aşma Talimatı:** İndirilen DMG veya Cask kurulumu sonrasında kullanıcılara tek seferlik `xattr -cr /Applications/Versoline.app` komutu veya *System Settings > Privacy & Security* üzerinden izin verme adımı README ve belgelerde sunulmalıdır.

---

## 8. İkon İncelemesi
- `Sources/Resources/Assets.xcassets/AppIcon.appiconset/` altındaki varlıklar incelenmiştir. İkon dosyalarında yazılı marka ibaresi bulunup bulunmadığı görsel olarak kullanıcı tarafından teyit edilmelidir. İkon değişikliği kurallar gereği kullanıcıya aittir.

---

## 🛑 GATE 0: Karar İstemi

Faz 0 başarıyla tamamlanmıştır. Faz 1'e geçmeden önce sizden şu **iki kritik kararın** teyidi beklenmektedir:

1. **Bundle Identifier Kararı:**
   - **Öneri (Tavsiye Edilen):** `PRODUCT_BUNDLE_IDENTIFIER: com.bezelye.EasyRSS` olarak **korunsun**.
     - *Neden:* macOS App Sandbox ve `UserDefaults.standard` doğrudan Bundle ID'ye bağlıdır. Bundle ID korunduğunda konteyner izolasyonu bozulmaz, mevcut kullanıcıların izinleri, bildirim yetkileri, pencere konumları ve ayarları sıfırlanmaz; veri migrasyonu pürüzsüz gerçekleşir. Yalnızca görünen ad, ürün adı, menüler ve veri klasörü `Versoline` olur.
     - *Alternatif:* `com.bezelye.Versoline` olarak değiştirilirse, UserDefaults aktarımı ve sandbox konteyner geçiş kodu eklenmesi gerekir.
2. **İlk Versoline Sürüm Numarası:**
   - Hedef sürüm numarası **`v0.3.0`** (`MARKETING_VERSION: 0.3.0`, `CURRENT_PROJECT_VERSION: 7`) olarak onaylanıyor mu?
