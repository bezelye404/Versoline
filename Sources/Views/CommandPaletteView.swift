import SwiftUI

/// ⌘K palette: type, arrow keys, Return. Opens as an overlay at the top of the window.
struct CommandPaletteView: View {

    let entries: [PaletteEntry]
    var onSelect: (PaletteEntry) -> Void
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var results: [PaletteEntry] {
        CommandPalette.filter(entries, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Go to a feed or run a command..."), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onSubmit { choose(at: highlighted) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if results.isEmpty {
                Text(String(localized: "No matches"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                                row(entry, isHighlighted: index == highlighted)
                                    .id(entry.id)
                                    .onTapGesture { choose(at: index) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: highlighted) { _, newValue in
                        if results.indices.contains(newValue) {
                            proxy.scrollTo(results[newValue].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 520)
        // Opaque on purpose: a translucent material let the page behind it show through the results.
        .background(theme.windowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.hairlineBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onExitCommand(perform: onDismiss)
    }

    private func row(_ entry: PaletteEntry, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.systemImage)
                .frame(width: 20)
                .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
            Text(entry.title)
                .lineLimit(1)
            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHighlighted ? theme.cardSelected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), results.count - 1)
    }

    private func choose(at index: Int) {
        guard results.indices.contains(index) else { return }
        onSelect(results[index])
    }
}
