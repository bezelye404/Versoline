import SwiftUI
import AppKit
import WebKit

struct ShortcutsSettingsTab: View {

    @AppStorage(AppSettingsKeys.enableSingleKeyShortcuts) private var enableSingleKeyShortcuts = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Single-Key Navigation", isOn: $enableSingleKeyShortcuts)
                Text("Enables vim-style keyboard navigation (J, K, M, S, O) without holding Command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Cheat Sheet") {
                shortcutRow(key: "J", description: "Next article")
                shortcutRow(key: "K", description: "Previous article")
                shortcutRow(key: "M", description: "Toggle Read / Unread status")
                shortcutRow(key: "S", description: "Toggle Bookmark (Star)")
                shortcutRow(key: "O / ↩", description: "Open article in preferred web browser")
                shortcutRow(key: "⌘ ⇧ R", description: "Toggle Reader Mode")
                shortcutRow(key: "⌘ R", description: "Refresh all feeds")
                shortcutRow(key: "⌘ ⌥ C", description: "Open Developer Debug Console")
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }

    private func shortcutRow(key: String, description: String) -> some View {
        HStack {
            Text(description)
                .font(.callout)
            Spacer()
            Text(key)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - 4. Filters Tab
