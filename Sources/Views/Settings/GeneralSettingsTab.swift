import SwiftUI
import AppKit
import WebKit

struct GeneralSettingsTab: View {

    @AppStorage(AppSettingsKeys.appColorPalette) private var appColorPaletteRaw = AppColorPalette.slate.rawValue
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    @AppStorage(AppSettingsKeys.showFavicons) private var showFavicons = true
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false
    @AppStorage(AppSettingsKeys.preferredExternalBrowser) private var preferredExternalBrowserRaw = ExternalBrowserOption.systemDefault.rawValue
    @AppStorage(AppSettingsKeys.offlinePrecacheEnabled) private var offlinePrecacheEnabled = false
    @AppStorage(AppSettingsKeys.isContentBlockerEnabled) private var isContentBlockerEnabled = true
    @AppStorage(AppSettingsKeys.showReadingTimeStreams) private var showReadingTimeStreams = false

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(AppColorPalette.allCases) { palette in
                        let isSelected = (appColorPaletteRaw == palette.rawValue)
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(palette.accentColor)
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .fill(palette.bookmarkColor)
                                    .frame(width: 12, height: 12)
                            }
                            .padding(.leading, 2)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(palette.title)
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .semibold : .medium)
                                    .lineLimit(1)
                                Text(palette.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(palette.accentColor)
                                    .imageScale(.medium)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? palette.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isSelected ? palette.accentColor.opacity(0.40) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(AppAnimation.interactiveSpring) {
                                appColorPaletteRaw = palette.rawValue
                            }
                            AppHaptics.selection()
                        }
                    }
                }
                .padding(.vertical, 4)
                Text("Customizes the appearance, background tones, and accent colors across the entire app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Compact Article List", isOn: $isCompactListMode)
                Text("Hides article snippet summaries in the list to fit more articles on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Site Favicons", isOn: $showFavicons)
                Text("Displays website logos next to feeds and article titles for quick visual recognition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                Text("Keeps a Versoline status icon in your macOS top menu bar with an unread badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reading Time Filters") {
                Toggle("Show Quick & Deep Reads", isOn: $showReadingTimeStreams)
                Text("Adds 'Quick Reads (<3m)' and 'Deep Reads (>7m)' filters to the Smart Streams section in your sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Web Browser & Privacy") {
                Toggle("Block Ads & Trackers (WebKit Content Blocker)", isOn: $isContentBlockerEnabled)
                Text("Enables native WebKit content blocking for live web browsing. Blocks advertising networks, analytics trackers, and popup scripts while keeping RSS feeds untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("External Browser") {
                Picker("Preferred Browser:", selection: $preferredExternalBrowserRaw) {
                    ForEach(ExternalBrowserOption.allCases) { browser in
                        Text(browser.title).tag(browser.rawValue)
                    }
                }
                Text("Choose which web browser opens when clicking 'Open in Browser'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Offline Reading") {
                Toggle("Pre-cache Articles for Offline Access", isOn: $offlinePrecacheEnabled)
                Text("Pre-loads readable articles in the background so they are ready even without an internet connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

// MARK: - 2. Reader Tab
