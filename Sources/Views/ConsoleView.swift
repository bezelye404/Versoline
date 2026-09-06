import SwiftUI
import AppKit

struct ConsoleView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var logger = AppLogger.shared

    @State private var searchText = ""
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var autoScrollToBottom = true
    @State private var showCopiedAlert = false

    private var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            if let level = selectedLevel, entry.level != level {
                return false
            }
            if let category = selectedCategory, entry.category != category {
                return false
            }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matchesMessage = entry.message.lowercased().contains(query)
                let matchesCategory = entry.category.rawValue.lowercased().contains(query)
                let matchesDetails = entry.details?.lowercased().contains(query) ?? false
                return matchesMessage || matchesCategory || matchesDetails
            }
            return true
        }
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
            Divider()

            // Filter Bar
            filterBar
            Divider()

            // Console Log List
            logListView

            Divider()

            // Bottom Status Bar
            footerView
        }
        .frame(minWidth: 700, idealWidth: 840, minHeight: 460, idealHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Developer Console")
                    .font(.headline)
                Text("\(filteredEntries.count) / \(logger.entries.count) events logged")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Search box
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search console...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 220)

            Button {
                copyAllLogs()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy logs to clipboard")

            Button {
                exportLogsToFile()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export logs to a text file")

            Button(role: .destructive) {
                logger.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear all in-memory logs")

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Category:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                categoryFilterChip(title: "All", category: nil)
                ForEach(LogCategory.allCases, id: \.self) { cat in
                    categoryFilterChip(title: cat.rawValue, category: cat, icon: cat.systemImage)
                }

                Divider()
                    .frame(height: 16)

                Text("Level:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                levelFilterChip(title: "All", level: nil)
                ForEach(LogLevel.allCases, id: \.self) { lvl in
                    levelFilterChip(title: lvl.rawValue, level: lvl, icon: lvl.systemImage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private func categoryFilterChip(title: String, category: LogCategory?, icon: String? = nil) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func levelFilterChip(title: String, level: LogLevel?, icon: String? = nil) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            selectedLevel = level
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? levelColor(level).opacity(0.9) : Color.clear)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func levelColor(_ level: LogLevel?) -> Color {
        guard let level else { return .accentColor }
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    // MARK: - Log List

    private var logListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filteredEntries.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredEntries) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: logger.entries.count) { _, _ in
                if autoScrollToBottom, let last = filteredEntries.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No log messages match your filter criteria.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                .toggleStyle(.checkbox)
                .font(.caption)

            Spacer()

            if showCopiedAlert {
                Text("Copied to clipboard!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Text("Memory buffer: \(logger.entries.count) / \(logger.maxEntries)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Actions

    private func copyAllLogs() {
        let text = logger.exportFormattedLogs()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }

    private func exportLogsToFile() {
        let panel = NSSavePanel()
        panel.title = "Export Console Logs"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "easyRSS_debug_logs.txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = logger.exportFormattedLogs()
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Log Row Component

struct LogRow: View {
    let entry: LogEntry
    @State private var isExpanded = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // Timestamp
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .leading)

                // Level Badge
                levelBadge(entry.level)

                // Category Badge
                Text("[\(entry.category.rawValue)]")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                // Message Text
                Text(entry.message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : 2)

                Spacer()

                if entry.details != nil {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Expanded Details Section
            if isExpanded, let details = entry.details, !details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Details:")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.leading, 88)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(entry.level == .error ? Color.red.opacity(0.08) : Color.clear)
    }

    private func levelBadge(_ level: LogLevel) -> some View {
        let (color, text): (Color, String) = switch level {
        case .debug: (.gray, "DEBUG")
        case .info: (.blue, "INFO")
        case .warning: (.orange, "WARN")
        case .error: (.red, "ERROR")
        }

        return Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .frame(width: 48, alignment: .center)
    }
}
