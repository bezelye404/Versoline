import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case sepia
    case dark
    case oled
    case solarized
    case nordic
    case matcha
    case espresso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .sepia: return String(localized: "Sepia")
        case .dark: return String(localized: "Dark")
        case .oled: return String(localized: "OLED Black")
        case .solarized: return String(localized: "Solarized Paper")
        case .nordic: return String(localized: "Nordic Frost")
        case .matcha: return String(localized: "Matcha Tea")
        case .espresso: return String(localized: "Espresso Cream")
        }
    }

    var backgroundColorCSS: String {
        switch self {
        case .system: return "transparent"
        case .light: return "#ffffff"
        case .sepia: return "#f8f1e3"
        case .dark: return "#1c1c1e"
        case .oled: return "#000000"
        case .solarized: return "#fdf6e3"
        case .nordic: return "#f4f6f8"
        case .matcha: return "#f4f7f4"
        case .espresso: return "#faf6f0"
        }
    }

    var textColorCSS: String {
        switch self {
        case .system: return "var(--text-color)"
        case .light: return "#1d1d1f"
        case .sepia: return "#433422"
        case .dark: return "#e5e5e7"
        case .oled: return "#d1d1d6"
        case .solarized: return "#586e75"
        case .nordic: return "#2e3440"
        case .matcha: return "#2d3830"
        case .espresso: return "#382d24"
        }
    }

    var linkColorCSS: String {
        switch self {
        case .system: return "var(--link-color)"
        case .light: return "#0066cc"
        case .sepia: return "#9b4d0e"
        case .dark: return "#6cb4ee"
        case .oled: return "#5ea4ea"
        case .solarized: return "#268bd2"
        case .nordic: return "#5e81ac"
        case .matcha: return "#577a5c"
        case .espresso: return "#ad753d"
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable {
    case system
    case serif
    case sansSerif
    case monospace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .serif: return String(localized: "Serif (New York)")
        case .sansSerif: return String(localized: "Sans-Serif (SF Pro)")
        case .monospace: return String(localized: "Monospace (SF Mono)")
        }
    }

    var cssFontFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        case .serif:
            return "'New York', Georgia, Cambria, Times, serif"
        case .sansSerif:
            return "'SF Pro Text', -apple-system, Helvetica, Arial, sans-serif"
        case .monospace:
            return "'SF Mono', Menlo, Monaco, Consolas, monospace"
        }
    }
}

enum ReaderLineHeight: String, CaseIterable, Identifiable {
    case compact = "1.5"
    case normal = "1.8"
    case relaxed = "2.1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .normal: return String(localized: "Normal")
        case .relaxed: return String(localized: "Relaxed")
        }
    }
}

enum ReadingViewMode: String, CaseIterable, Identifiable {
    case reader
    case inAppBrowser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reader: return String(localized: "Reader")
        case .inAppBrowser: return String(localized: "Web")
        }
    }

    var systemImage: String {
        switch self {
        case .reader: return "sparkles"
        case .inAppBrowser: return "globe"
        }
    }
}

enum ExternalBrowserOption: String, CaseIterable, Identifiable {
    case systemDefault
    case safari
    case chrome
    case arc
    case brave
    case firefox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault: return String(localized: "System Default")
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave"
        case .firefox: return "Firefox"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .systemDefault: return nil
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .arc: return "company.thebrowser.Browser"
        case .brave: return "com.brave.Browser"
        case .firefox: return "org.mozilla.firefox"
        }
    }

    func open(url: URL) {
        if let bundleId = bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - App Color Themes & Surfaces

enum AppColorPalette: String, CaseIterable, Identifiable {
    case slate
    case sepia
    case sage
    case dusk
    case monochrome
    case nordic
    case espresso
    case matcha
    case bordeaux
    case solarized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slate: return String(localized: "Slate")
        case .sepia: return String(localized: "Sepia")
        case .sage: return String(localized: "Sage")
        case .dusk: return String(localized: "Dusk")
        case .monochrome: return String(localized: "Monochrome")
        case .nordic: return String(localized: "Nordic Frost")
        case .espresso: return String(localized: "Espresso Amber")
        case .matcha: return String(localized: "Matcha & Moss")
        case .bordeaux: return String(localized: "Bordeaux Plum")
        case .solarized: return String(localized: "Solarized Paper")
        }
    }

    var subtitle: String {
        switch self {
        case .slate: return String(localized: "Nordic Steel")
        case .sepia: return String(localized: "Warm Editorial Paper")
        case .sage: return String(localized: "Natural Herb & Stone")
        case .dusk: return String(localized: "Muted Evening Violet")
        case .monochrome: return String(localized: "Minimal High-Contrast")
        case .nordic: return String(localized: "Muted Polar Slate")
        case .espresso: return String(localized: "Roasted Bean & Warm Leather")
        case .matcha: return String(localized: "Dry Green Tea & Stone Garden")
        case .bordeaux: return String(localized: "Antique Velvet & Library Leather")
        case .solarized: return String(localized: "Mathematical Contrast Matrix")
        }
    }

    // Accent Color (Flat, matte, desaturated)
    var accentColor: Color {
        switch self {
        case .slate: return Color(red: 0.30, green: 0.46, blue: 0.62)
        case .sepia: return Color(red: 0.66, green: 0.40, blue: 0.24)
        case .sage: return Color(red: 0.32, green: 0.50, blue: 0.40)
        case .dusk: return Color(red: 0.48, green: 0.40, blue: 0.62)
        case .monochrome: return Color.primary.opacity(0.85)
        case .nordic: return Color(red: 0.36, green: 0.48, blue: 0.60)
        case .espresso: return Color(red: 0.68, green: 0.46, blue: 0.24)
        case .matcha: return Color(red: 0.34, green: 0.48, blue: 0.36)
        case .bordeaux: return Color(red: 0.62, green: 0.32, blue: 0.38)
        case .solarized: return Color(red: 0.18, green: 0.50, blue: 0.56)
        }
    }

    // Bookmark / Star
    var bookmarkColor: Color {
        switch self {
        case .slate: return Color(red: 0.80, green: 0.58, blue: 0.26)
        case .sepia: return Color(red: 0.72, green: 0.45, blue: 0.20)
        case .sage: return Color(red: 0.68, green: 0.55, blue: 0.28)
        case .dusk: return Color(red: 0.74, green: 0.52, blue: 0.38)
        case .monochrome: return Color.primary.opacity(0.85)
        case .nordic: return Color(red: 0.78, green: 0.62, blue: 0.38)
        case .espresso: return Color(red: 0.72, green: 0.40, blue: 0.22)
        case .matcha: return Color(red: 0.74, green: 0.60, blue: 0.32)
        case .bordeaux: return Color(red: 0.76, green: 0.58, blue: 0.34)
        case .solarized: return Color(red: 0.68, green: 0.52, blue: 0.16)
        }
    }

    var unreadDotColor: Color {
        accentColor
    }

    // Window & Sidebar Base Background
    var windowBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch self {
            case .slate:
                return isDark ? NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
                              : NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1.0)
            case .sepia:
                return isDark ? NSColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1.0)
            case .sage:
                return isDark ? NSColor(red: 0.11, green: 0.13, blue: 0.12, alpha: 1.0)
                              : NSColor(red: 0.94, green: 0.96, blue: 0.94, alpha: 1.0)
            case .dusk:
                return isDark ? NSColor(red: 0.13, green: 0.12, blue: 0.16, alpha: 1.0)
                              : NSColor(red: 0.96, green: 0.95, blue: 0.97, alpha: 1.0)
            case .monochrome:
                return isDark ? NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
                              : NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
            case .nordic:
                return isDark ? NSColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1.0)
                              : NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1.0)
            case .espresso:
                return isDark ? NSColor(red: 0.13, green: 0.11, blue: 0.10, alpha: 1.0)
                              : NSColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1.0)
            case .matcha:
                return isDark ? NSColor(red: 0.10, green: 0.13, blue: 0.11, alpha: 1.0)
                              : NSColor(red: 0.94, green: 0.96, blue: 0.94, alpha: 1.0)
            case .bordeaux:
                return isDark ? NSColor(red: 0.14, green: 0.11, blue: 0.13, alpha: 1.0)
                              : NSColor(red: 0.97, green: 0.95, blue: 0.96, alpha: 1.0)
            case .solarized:
                return isDark ? NSColor(red: 0.02, green: 0.15, blue: 0.18, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.96, blue: 0.89, alpha: 1.0)
            }
        })
    }

    // Article List & Detail Background
    var listBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch self {
            case .slate:
                return isDark ? NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)
                              : NSColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
            case .sepia:
                return isDark ? NSColor(red: 0.17, green: 0.15, blue: 0.12, alpha: 1.0)
                              : NSColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1.0)
            case .sage:
                return isDark ? NSColor(red: 0.13, green: 0.15, blue: 0.13, alpha: 1.0)
                              : NSColor(red: 0.96, green: 0.97, blue: 0.95, alpha: 1.0)
            case .dusk:
                return isDark ? NSColor(red: 0.15, green: 0.14, blue: 0.18, alpha: 1.0)
                              : NSColor(red: 0.97, green: 0.96, blue: 0.98, alpha: 1.0)
            case .monochrome:
                return isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
            case .nordic:
                return isDark ? NSColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1.0)
                              : NSColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
            case .espresso:
                return isDark ? NSColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1.0)
            case .matcha:
                return isDark ? NSColor(red: 0.12, green: 0.15, blue: 0.13, alpha: 1.0)
                              : NSColor(red: 0.96, green: 0.97, blue: 0.95, alpha: 1.0)
            case .bordeaux:
                return isDark ? NSColor(red: 0.16, green: 0.13, blue: 0.15, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.96, blue: 0.97, alpha: 1.0)
            case .solarized:
                return isDark ? NSColor(red: 0.04, green: 0.19, blue: 0.23, alpha: 1.0)
                              : NSColor(red: 0.95, green: 0.93, blue: 0.85, alpha: 1.0)
            }
        })
    }

    // Card Surface Background
    var cardBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch self {
            case .slate:
                return isDark ? NSColor(red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0)
                              : NSColor(white: 1.0, alpha: 0.88)
            case .sepia:
                return isDark ? NSColor(red: 0.21, green: 0.18, blue: 0.15, alpha: 1.0)
                              : NSColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 0.95)
            case .sage:
                return isDark ? NSColor(red: 0.16, green: 0.19, blue: 0.17, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.99, blue: 0.98, alpha: 0.92)
            case .dusk:
                return isDark ? NSColor(red: 0.19, green: 0.17, blue: 0.23, alpha: 1.0)
                              : NSColor(red: 0.99, green: 0.98, blue: 1.0, alpha: 0.92)
            case .monochrome:
                return isDark ? NSColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1.0)
                              : NSColor(white: 1.0, alpha: 0.95)
            case .nordic:
                return isDark ? NSColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1.0)
                              : NSColor(white: 1.0, alpha: 0.92)
            case .espresso:
                return isDark ? NSColor(red: 0.19, green: 0.16, blue: 0.14, alpha: 1.0)
                              : NSColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 0.95)
            case .matcha:
                return isDark ? NSColor(red: 0.16, green: 0.19, blue: 0.17, alpha: 1.0)
                              : NSColor(red: 0.98, green: 0.99, blue: 0.98, alpha: 0.92)
            case .bordeaux:
                return isDark ? NSColor(red: 0.20, green: 0.16, blue: 0.19, alpha: 1.0)
                              : NSColor(white: 1.0, alpha: 0.92)
            case .solarized:
                return isDark ? NSColor(red: 0.06, green: 0.23, blue: 0.27, alpha: 1.0)
                              : NSColor(red: 0.99, green: 0.98, blue: 0.93, alpha: 0.95)
            }
        })
    }

    // Card Selection
    var cardSelected: Color {
        accentColor.opacity(0.14)
    }

    var cardSelectedBorder: Color {
        accentColor.opacity(0.38)
    }

    var detailBackground: Color {
        listBackground
    }

    // MARK: - Surfaces & Chrome
    var toolbarBackground: Color {
        windowBackground
    }

    var hairlineBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(white: 1.0, alpha: 0.08) : NSColor(white: 0.0, alpha: 0.09)
        })
    }

    var cardHover: Color {
        Color.primary.opacity(0.04)
    }

    // MARK: - Badges & Counts
    var badgeBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(white: 1.0, alpha: 0.08) : NSColor(white: 0.0, alpha: 0.06)
        })
    }

    var badgeText: Color {
        Color.secondary
    }

    var activeBadgeBackground: Color {
        accentColor.opacity(0.14)
    }

    var activeBadgeText: Color {
        accentColor
    }

    // MARK: - Status & Media Pigments
    var podcastColor: Color {
        Color(red: 0.52, green: 0.44, blue: 0.70)
    }

    var youtubeColor: Color {
        Color(red: 0.80, green: 0.30, blue: 0.28)
    }

    var successColor: Color {
        Color(red: 0.32, green: 0.58, blue: 0.36)
    }

    var warningColor: Color {
        Color(red: 0.82, green: 0.62, blue: 0.22)
    }

    var readerThemeDefault: ReaderTheme {
        switch self {
        case .sepia: return .sepia
        case .solarized: return .solarized
        case .nordic: return .nordic
        case .matcha: return .matcha
        case .espresso: return .espresso
        case .slate, .sage, .dusk, .monochrome, .bordeaux: return .system
        }
    }
}

struct AppSettingsKeys {
    static let readerTheme = "readerTheme"
    static let readerFontFamily = "readerFontFamily"
    static let readerFontSize = "readerFontSize"
    static let readerLineHeight = "readerLineHeight"
    static let isCompactListMode = "isCompactListMode"
    static let showFavicons = "showFavicons"
    static let enableSingleKeyShortcuts = "enableSingleKeyShortcuts"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let autoReaderMode = "autoReaderMode"
    static let autoCleanupDays = "autoCleanupDays"
    static let mutedKeywords = "mutedKeywords"
    static let defaultReadingMode = "defaultReadingMode"
    static let preferredExternalBrowser = "preferredExternalBrowser"
    static let offlinePrecacheEnabled = "offlinePrecacheEnabled"
    static let isContentBlockerEnabled = "isContentBlockerEnabled"
    static let appColorPalette = "appColorPalette"
    static let isBionicReadingEnabled = "isBionicReadingEnabled"
    static let showReadingTimeStreams = "showReadingTimeStreams"
    static let isSyncEnabled = "isSyncEnabled"
    static let isLocalPeerSyncEnabled = "isLocalPeerSyncEnabled"
}


