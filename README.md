# easyRSS

[English](#english) | [Türkçe](#türkçe)

---

<a name="english"></a>
## English

A lightweight, privacy-focused, and modern desktop RSS/Atom reader for macOS, built with Swift and SwiftUI.

The app is designed with macOS Tahoe aesthetics in mind, featuring Liquid Glass translucency and natural system tones, providing an elegant and native user experience without eye-straining neon gradients.

### Features

- **Folders and Organization:**
  - Group your feeds by creating custom folders.
  - Quickly move or rename feeds between folders using the right-click context menu.
- **OPML Import and Export:**
  - Import your `.opml` file with one click when migrating from another RSS reader (folder structure is preserved).
  - Export all your subscriptions in standard OPML format anytime.
- **Bookmarks & Favorites:**
  - Star articles you want to read later to add them to your bookmarks.
  - Instantly access your favorites using the smart filter in the sidebar.
- **Instant Search:**
  - Quickly filter through titles and summary texts in the article list.
- **Smart Read Status Management:**
  - Dynamically toggle between **Mark All as Read** and **Mark All as Unread** via a single button.
- **Seamless Reading Experience with WebKit:**
  - Built-in `WKWebView` reading view that automatically adapts to light/dark modes with great typography.
  - Safely opens external links within articles in your default browser.
- **Fully Local and Privacy-Focused:**
  - No external analytics, telemetry, or third-party proxy servers are used.
  - Your data is stored locally only on your own computer.

### Architecture & Technologies

- **Language & Runtime:** Swift 6.3+ (Strict Concurrency fully compliant)
- **UI:** SwiftUI (macOS 15+, 3-column `NavigationSplitView`)
- **State Management:** `@Observable` macro and `@MainActor` protected `FeedStore`
- **Parser:** Native `XMLParser` with zero external dependencies (RSS 2.0, Atom, and OPML 2.0 support)
- **Dependencies:** Zero external packages (Pure Apple native frameworks: Foundation, SwiftUI, WebKit)

### Privacy & Data Storage

easyRSS places the utmost importance on the privacy of your personal data:
- **Local Storage:** All your feed records, folders, bookmarks, and read statuses are stored locally on your system in JSON format at:
  ```bash
  ~/Library/Application Support/EasyRSS/data.json
  ```
- **Networking:** The app only sends direct GET requests to the RSS/Atom links you add. No user data or reading habits are exported.
- **Version Control:** The project's `.gitignore` file is configured to exclude your personal data backups, exported OPML files, local JSON databases, and sensitive user keys from Git history.

### Installation and Running

#### Requirements
- **macOS:** 15.0 or newer
- **Xcode:** 16.0 or newer

#### Steps
1. Clone the repository or open the project folder:
   ```bash
   cd easyRSS
   ```
2. Open the project with Xcode:
   ```bash
   open Package.swift
   ```
3. Set **My Mac** as the destination in the Xcode toolbar.
4. Press **`Cmd + R`** to build and run the project.

---

<a name="türkçe"></a>
## Türkçe

macOS için Swift ve SwiftUI ile geliştirilmiş, hafif, gizlilik odaklı ve modern bir masaüstü RSS/Atom okuyucu.

Uygulama, macOS Tahoe estetiğine uygun Liquid Glass yarı saydamlıkları ve sistem tonlarıyla tasarlanmış olup, göz yoran neon degrade renkler yerine zarif ve doğal bir kullanıcı deneyimi sunar.

### Özellikler

- **Klasörleme ve Organizasyon:**
  - Akışlarınızı özel klasörler oluşturarak gruplandırın.
  - Sağ tık bağlam menüsü ile akışları klasörler arasında hızlıca taşıyın veya yeniden adlandırın.
- **OPML İçe ve Dışa Aktarma:**
  - Başka bir RSS okuyucudan geçiş yaparken `.opml` dosyanızı tek tıkla içe aktarın (klasör yapısı korunur).
  - İstediğiniz zaman tüm aboneliklerinizi standart OPML formatında dışa aktarın.
- **Favoriler & Yer İmleri:**
  - Daha sonra okumak istediğiniz makaleleri yıldızlayarak yer imlerine ekleyin.
  - Sol kenar çubuğundaki akıllı filtre ile favorilerinize anında ulaşın.
- **Anlık Arama:**
  - Makale listesinde başlık ve özet metinleri içerisinde hızlı filtreleme yapın.
- **Akıllı Okuma Durumu Yönetimi:**
  - "Tümünü Okundu İşaretle" butonu üzerinden dinamik olarak **Tümü Okundu** veya **Tümü Okunmadı** durumuna geçiş yapın.
- **WebKit ile Kusursuz Okuma Deneyimi:**
  - Yerleşik `WKWebView` ile açık/koyu modla otomatik uyum sağlayan tipografik okuma görünümü.
  - Makale içindeki harici bağlantıları güvenli bir şekilde varsayılan tarayıcınızda açar.
- **Tamamen Yerel ve Gizlilik Odaklı:**
  - Harici hiçbir analitik, telemetri veya üçüncü taraf ara sunucu kullanılmaz.
  - Verileriniz yalnızca kendi bilgisayarınızda saklanır.

### Mimari & Teknolojiler

- **Dil & Çalışma Zamanı:** Swift 6.3+ (Strict Concurrency tam uyumlu)
- **Kullanıcı Arayüzü:** SwiftUI (macOS 15+, 3 sütunlu `NavigationSplitView`)
- **Durum Yönetimi:** `@Observable` makrosu ve `@MainActor` korumalı `FeedStore`
- **Ayrıştırma (Parser):** Harici kütüphane bağımlılığı olmaksızın yerel `XMLParser` (RSS 2.0, Atom ve OPML 2.0 desteği)
- **Bağımlılıklar:** Sıfır harici paket (Tamamen Apple yerel kütüphaneleri: Foundation, SwiftUI, WebKit)

### Gizlilik & Veri Depolama

easyRSS kişisel verilerinizin gizliliğine azami önem verir:
- **Yerel Depolama:** Tüm akış kayıtlarınız, klasörleriniz, favorileriniz ve okuma durumlarınız sisteminizde şu konumda yerel JSON formatında saklanır:
  ```bash
  ~/Library/Application Support/EasyRSS/data.json
  ```
- **Ağ İletişimi:** Uygulama yalnızca eklediğiniz RSS/Atom bağlantılarına doğrudan GET istekleri gönderir. Hiçbir kullanıcı verisi veya okuma alışkanlığı dışarı aktarılmaz.
- **Sürüm Kontrolü:** Proje `.gitignore` dosyası; kişisel veri yedeklerinizi, dışa aktarılan OPML dosyalarınızı, yerel JSON veritabanlarını ve hassas kullanıcı anahtarlarını Git geçmişine dahil etmeyecek şekilde yapılandırılmıştır.

### Kurulum ve Çalıştırma

#### Gereksinimler
- **macOS:** 15.0 veya daha yenisi
- **Xcode:** 16.0 veya daha yenisi

#### Adımlar
1. Depoyu klonlayın veya proje klasörünü açın:
   ```bash
   cd easyRSS
   ```
2. Projeyi Xcode ile açın:
   ```bash
   open Package.swift
   ```
3. Xcode araç çubuğunda hedef olarak **My Mac** seçeneğini belirleyin.
4. **`Cmd + R`** tuşlarına basarak projeyi derleyip çalıştırın.

---

## License / Lisans

Bu proje kişisel kullanım ve açık kaynak geliştirme amacıyla hazırlanmıştır. / This project is intended for personal use and open-source development.
