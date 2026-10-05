import SwiftUI
import AppKit
import WebKit

struct GeneralSettingsTab: View {

    @AppStorage(AppSettingsKeys.appColorPalette) private var appColorPaletteRaw = AppColorPalette.slate.rawValue
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    @AppStorage(AppSettingsKeys.showFavicons) private var showFavicons = true
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false
    @AppStorage(AppSettingsKeys.showDockBadge) private var showDockBadge = false
    @AppStorage(AppSettingsKeys.preferredExternalBrowser) private var preferredExternalBrowserRaw = ExternalBrowserOption.systemDefault.rawValue
    @AppStorage(AppSettingsKeys.offlinePrecacheEnabled) private var offlinePrecacheEnabled = false
    @AppStorage(AppSettingsKeys.isContentBlockerEnabled) private var isContentBlockerEnabled = true
    @AppStorage(AppSettingsKeys.showReadingTimeStreams) private var showReadingTimeStreams = false
    @AppStorage(AppSettingsKeys.groupSimilarStories) private var groupSimilarStories = true
    @AppStorage(AppSettingsKeys.markOldAsReadDays) private var markOldAsReadDays = 0
    @AppStorage(AppSettingsKeys.playYouTubeInApp) private var playYouTubeInApp = true
    @AppStorage(AppSettingsKeys.enableSingleKeyShortcuts) private var enableSingleKeyShortcuts = true

    private var selectedPalette: AppColorPalette {
        AppColorPalette(rawValue: appColorPaletteRaw) ?? .slate
    }

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    // One row of colour swatches instead of ten large cards.
                    HStack(spacing: 10) {
                        ForEach(AppColorPalette.allCases) { palette in
                            swatch(for: palette)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(selectedPalette.title)
                            .font(.subheadline.weight(.medium))
                        Text(selectedPalette.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .animation(AppAnimation.quickFeedback, value: appColorPaletteRaw)
                }
                .padding(.vertical, 2)

                Toggle(isOn: $isCompactListMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compact Article List")
                        Text("Hides article snippet summaries in the list to fit more articles on screen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showFavicons) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Site Favicons")
                        Text("Displays website logos next to feeds and article titles for quick visual recognition.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showDockBadge) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Unread Count on the Dock Icon")
                        Text("A badge with the number of unread articles. It updates while the app is open; nothing runs in the background.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showMenuBarIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Menu Bar Icon")
                        Text("Keeps a Versoline status icon in your macOS top menu bar with an unread badge.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Reading") {
                Toggle(isOn: $groupSimilarStories) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group the Same Story")
                        Text("Shows one row when several of your feeds report the same news, with the other sources one tap away. Reading it marks the other versions as read.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Mark Old Unread as Read:", selection: $markOldAsReadDays) {
                    Text("Never").tag(0)
                    Text("After 3 Days").tag(3)
                    Text("After a Week").tag(7)
                    Text("After 2 Weeks").tag(14)
                    Text("After a Month").tag(30)
                }
                Text("Keeps the Unread list about what is new: articles you never opened are marked as read once they are this old. Bookmarks are not affected.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $showReadingTimeStreams) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Quick & Deep Reads")
                        Text("Adds 'Quick Reads (<3m)' and 'Deep Reads (>7m)' filters to the Smart Streams section in your sidebar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $offlinePrecacheEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pre-cache Articles for Offline Access")
                        Text("Pre-loads readable articles in the background so they are ready even without an internet connection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Keyboard") {
                Toggle(isOn: $enableSingleKeyShortcuts) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Single-Key Navigation")
                        Text("Enables vim-style keyboard navigation (J, K, M, S, O) without holding Command.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Web Browser & Privacy") {
                Toggle(isOn: $isContentBlockerEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Block Ads & Trackers (WebKit Content Blocker)")
                        Text("Enables native WebKit content blocking for live web browsing. Blocks advertising networks, analytics trackers, and popup scripts while keeping RSS feeds untouched.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $playYouTubeInApp) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play YouTube Videos in Versoline")
                        Text("Off opens videos in your browser instead. The built-in player loads a web page and needs about 100 MB of extra memory while a video is open.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Preferred Browser:", selection: $preferredExternalBrowserRaw) {
                    ForEach(ExternalBrowserOption.allCases) { browser in
                        Text(browser.title).tag(browser.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(for palette: AppColorPalette) -> some View {
        let isSelected = appColorPaletteRaw == palette.rawValue
        return Button {
            withAnimation(AppAnimation.interactiveSpring) {
                appColorPaletteRaw = palette.rawValue
            }
            AppHaptics.selection()
        } label: {
            ZStack {
                Circle().fill(palette.windowBackground)
                Circle().fill(palette.accentColor).frame(width: 12, height: 12).offset(x: -4, y: 0)
                Circle().fill(palette.bookmarkColor).frame(width: 12, height: 12).offset(x: 4, y: 0)
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(isSelected ? palette.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1))
            .scaleEffect(isSelected ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .help(palette.title)
        .accessibilityLabel(palette.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 2. Reader Tab
