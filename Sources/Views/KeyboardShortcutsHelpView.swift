import SwiftUI

struct KeyboardShortcutsHelpView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.bottom, 4)

            Divider()

            // Shortcut Columns
            HStack(alignment: .top, spacing: 32) {
                // Column 1: Navigation
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "Navigation"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    shortcutRow(key: "J", title: String(localized: "Next Article"))
                    shortcutRow(key: "K", title: String(localized: "Previous Article"))
                    shortcutRow(key: "Space", title: String(localized: "Page Down / Next Article"))
                    shortcutRow(keys: ["⇧", "Space"], title: String(localized: "Page Up"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Column 2: Actions
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "Article Actions"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    shortcutRow(keys: ["M", "⌘U"], title: String(localized: "Toggle Read Status"))
                    shortcutRow(key: "S", title: String(localized: "Toggle Bookmark"))
                    shortcutRow(keys: ["O", "⌘⏎"], title: String(localized: "Open in Browser"))
                    shortcutRow(key: "⌘R", title: String(localized: "Refresh All Feeds"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)

            Divider()

            HStack {
                Text(String(localized: "Press ? anytime to toggle this helper."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                shortcutRow(key: "Esc", title: String(localized: "Close"))
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func shortcutRow(key: String, title: String) -> some View {
        HStack(spacing: 12) {
            keyBadge(key)
                .frame(minWidth: 44, alignment: .center)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    @ViewBuilder
    private func shortcutRow(keys: [String], title: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { k in
                    keyBadge(k)
                }
            }
            .frame(minWidth: 54, alignment: .center)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    @ViewBuilder
    private func keyBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
    }
}
