import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case sepia
    case dark
    case oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .sepia: return String(localized: "Sepia")
        case .dark: return String(localized: "Dark")
        case .oled: return String(localized: "OLED Black")
        }
    }

    var backgroundColorCSS: String {
        switch self {
        case .system: return "transparent"
        case .light: return "#ffffff"
        case .sepia: return "#f8f1e3"
        case .dark: return "#1c1c1e"
        case .oled: return "#000000"
        }
    }

    var textColorCSS: String {
        switch self {
        case .system: return "var(--text-color)"
        case .light: return "#1d1d1f"
        case .sepia: return "#433422"
        case .dark: return "#e5e5e7"
        case .oled: return "#d1d1d6"
        }
    }

    var linkColorCSS: String {
        switch self {
        case .system: return "var(--link-color)"
        case .light: return "#0066cc"
        case .sepia: return "#9b4d0e"
        case .dark: return "#6cb4ee"
        case .oled: return "#5ea4ea"
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slate: return String(localized: "Slate")
        case .sepia: return String(localized: "Sepia")
        case .sage: return String(localized: "Sage")
        case .dusk: return String(localized: "Dusk")
        case .monochrome: return String(localized: "Monochrome")
        }
    }

    var subtitle: String {
        switch self {
        case .slate: return String(localized: "Nordic Steel")
        case .sepia: return String(localized: "Warm Editorial Paper")
        case .sage: return String(localized: "Natural Herb & Stone")
        case .dusk: return String(localized: "Muted Evening Violet")
        case .monochrome: return String(localized: "Minimal High-Contrast")
        }
    }

    // Accent Color
    var accentColor: Color {
        switch self {
        case .slate: return Color(red: 0.28, green: 0.48, blue: 0.68)
        case .sepia: return Color(red: 0.65, green: 0.38, blue: 0.22)
        case .sage: return Color(red: 0.32, green: 0.50, blue: 0.40)
        case .dusk: return Color(red: 0.48, green: 0.40, blue: 0.62)
        case .monochrome: return Color.primary.opacity(0.85)
        }
    }

    // Bookmark / Star
    var bookmarkColor: Color {
        switch self {
        case .slate: return Color(red: 0.82, green: 0.58, blue: 0.24)
        case .sepia: return Color(red: 0.72, green: 0.45, blue: 0.20)
        case .sage: return Color(red: 0.68, green: 0.55, blue: 0.28)
        case .dusk: return Color(red: 0.74, green: 0.52, blue: 0.38)
        case .monochrome: return Color.primary.opacity(0.85)
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

    var readerThemeDefault: ReaderTheme {
        switch self {
        case .sepia: return .sepia
        case .slate, .sage, .dusk, .monochrome: return .system
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
}


