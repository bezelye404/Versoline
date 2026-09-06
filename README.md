# easyRSS

[English](#english) | [Türkçe](#türkçe)

---

<a name="english"></a>
## English

A desktop RSS/Atom reader for macOS, built with Swift and SwiftUI.

Uses a standard 3-column navigation layout (`NavigationSplitView`) and native system controls aligned with macOS Tahoe design conventions.

### Features

- **Folders:**
  - Create folders to group feeds.
  - Move feeds between folders or rename them via the right-click context menu.
- **OPML Import and Export:**
  - Import subscription lists from `.opml` files with folder hierarchy preserved.
  - Export current subscriptions to standard OPML format.
- **Bookmarks:**
  - Star articles to add them to bookmarks.
  - Filter bookmarked articles from the sidebar.
- **Search:**
  - Filter article lists by searching titles and summaries.
- **Read Status Management:**
  - Mark individual articles as read or unread.
  - Toggle all articles between read and unread states using the batch status button.
- **WebKit Article Viewer:**
  - Render article contents using native `WKWebView` with light and dark mode support.
  - Open external links in the system default browser.
- **Local Operation & Privacy:**
  - No analytics, telemetry, or proxy servers.
  - Requests are made directly to the feed URLs.
  - All data is stored locally on the device.

### Architecture & Technologies

- **Language & Runtime:** Swift 6.3+ (Strict Concurrency compliant)
- **UI Framework:** SwiftUI (macOS 15+, 3-column `NavigationSplitView`)
- **State Management:** `@Observable` macro and `@MainActor` isolated `FeedStore`
- **Parser:** Native `XMLParser` implementation (RSS 2.0, Atom, OPML 2.0)
- **Dependencies:** Apple system frameworks only (Foundation, SwiftUI, WebKit)

### Data Storage

- **Local Storage:** Feed subscriptions, folder hierarchies, bookmarks, and read states are saved in JSON format at:
  ```bash
  ~/Library/Application Support/EasyRSS/data.json
  ```
- **Network Requests:** The application performs direct HTTP GET requests to configured feed URLs.
- **Version Control:** The repository's `.gitignore` excludes local JSON data, OPML exports, and backups from version tracking.

### Requirements & Build Instructions

#### Requirements
- macOS 15.0 or newer
- Xcode 16.0 or newer

#### Build Steps
1. Clone or open the repository folder:
   ```bash
   cd easyRSS
   ```
2. Open the project in Xcode:
   ```bash
   open EasyRSS.xcodeproj
   ```
3. Select **My Mac** as the run destination.
4. Press **`Cmd + R`** to build and run.

---

<a name="türkçe"></a>
## Türkçe

macOS için Swift ve SwiftUI ile geliştirilmiş masaüstü RSS/Atom okuyucusu.

macOS Tahoe tasarım standartlarına uygun 3 sütunlu gezinti düzeni (`NavigationSplitView`) ve yerel sistem bileşenlerini kullanır.

### Özellikler

- **Klasörler:**
  - Akışları gruplandırmak için klasör oluşturma.
  - Sağ tık menüsü ile akışları klasörler arasında taşıma ve yeniden adlandırma.
- **OPML İçe ve Dışa Aktarma:**
  - Klasör hiyerarşisini koruyarak `.opml` dosyalarından içe aktarım.
  - Mevcut abonelikleri standart OPML biçiminde dışa aktarım.
- **Yer İmleri (Favoriler):**
  - Makaleleri yıldızlayarak yer imlerine ekleme.
  - Kenar çubuğundaki filtre üzerinden yer imlerini listeleme.
- **Arama:**
  - Makale listesinde başlık ve özet metinlerine göre filtreleme.
- **Okuma Durumu Yönetimi:**
  - Makaleleri tekil olarak okundu veya okunmadı olarak işaretleme.
  - Toplu işlem butonu üzerinden tüm makaleleri okundu veya okunmadı durumuna getirme.
- **WebKit Makale Görüntüleyici:**
  - Açık ve koyu mod destekli yerel `WKWebView` ile makale içeriği görüntüleme.
  - Makale içi harici bağlantıları varsayılan tarayıcıda açma.
- **Yerel Çalışma & Gizlilik:**
  - Analitik, telemetri veya ara sunucu bulunmaz.
  - Ağ istekleri doğrudan ilgili akış adreslerine gönderilir.
  - Tüm veriler yerel diskte saklanır.

### Mimari ve Teknolojiler

- **Dil ve Çalışma Zamanı:** Swift 6.3+ (Strict Concurrency uyumlu)
- **Arayüz:** SwiftUI (macOS 15+, 3 sütunlu `NavigationSplitView`)
- **Durum Yönetimi:** `@Observable` makrosu ve `@MainActor` yalıtımlı `FeedStore`
- **Ayrıştırıcı:** Harici bağımlılık içermeyen yerel `XMLParser` (RSS 2.0, Atom, OPML 2.0)
- **Bağımlılıklar:** Yalnızca Apple yerel çatıları (Foundation, SwiftUI, WebKit)

### Veri Depolama

- **Yerel Depolama:** Akış listesi, klasörler, yer imleri ve okuma durumları JSON biçiminde şu yolda saklanır:
  ```bash
  ~/Library/Application Support/EasyRSS/data.json
  ```
- **Ağ İstekleri:** Uygulama yalnızca eklenen akış adreslerine doğrudan HTTP GET isteği gönderir.
- **Sürüm Kontrolü:** Proje `.gitignore` dosyası yerel veri dosyalarını, OPML dışa aktarımlarını ve yedekleri takip dışı bırakacak şekilde yapılandırılmıştır.

### Gereksinimler ve Çalıştırma

#### Gereksinimler
- macOS 15.0 veya daha yenisi
- Xcode 16.0 veya daha yenisi

#### Çalıştırma Adımları
1. Proje dizinine geçin:
   ```bash
   cd easyRSS
   ```
2. Projeyi Xcode ile açın:
   ```bash
   open EasyRSS.xcodeproj
   ```
3. Hedef olarak **My Mac** seçin.
4. **`Cmd + R`** tuşlarına basarak derleyin ve çalıştırın.

---

## License / Lisans

Bu proje açık kaynak geliştirme ve kişisel kullanım amacıyla sunulmuştur. / This project is provided for personal use and open-source development.
