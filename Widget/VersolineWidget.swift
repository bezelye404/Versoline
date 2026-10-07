import SwiftUI
import WidgetKit

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? WidgetSnapshot(generatedAt: Date(), unreadCount: 0, headlines: []), isPlaceholder: false))
        }
    }

    /// One entry. The app asks for a reload whenever the counts change; the widget never polls on its own.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot(generatedAt: Date(), unreadCount: 0, headlines: [])
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: snapshot, isPlaceholder: false)], policy: .never))
    }
}

// MARK: Colors (the app's Slate palette)

private extension Color {
    static let widgetAccent = Color(red: 0.30, green: 0.46, blue: 0.62)
    static let widgetAmber = Color(red: 0.80, green: 0.58, blue: 0.26)
}

// MARK: Views

struct VersolineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    private var headlineLimit: Int {
        switch family {
        case .systemMedium: return 3
        case .systemLarge: return 7
        default: return 0
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                small
            default:
                list
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Unread", systemImage: "envelope.badge")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(snapshot.unreadCount)")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color.widgetAccent)
            Text(LocalizedStringKey(snapshot.unreadCount == 1 ? "article" : "articles"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "\(WidgetSnapshot.urlScheme)://unread"))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Unread", systemImage: "envelope.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.unreadCount)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.widgetAccent)
            }

            if snapshot.headlines.isEmpty {
                Spacer()
                Text("You're all caught up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(snapshot.headlines.prefix(headlineLimit)) { headline in
                    headlineRow(headline)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func headlineRow(_ headline: WidgetSnapshot.Headline) -> some View {
        let row = VStack(alignment: .leading, spacing: 1) {
            Text(headline.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 4) {
                if headline.isTopStory {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.widgetAmber)
                }
                Text(headline.feedTitle)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if !entry.isPlaceholder, let url = WidgetSnapshot.openURL(forArticleLink: headline.link) {
            Link(destination: url) { row }
        } else {
            row
        }
    }
}

// MARK: Widget

struct VersolineWidget: Widget {
    let kind = "VersolineUnreadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            VersolineWidgetView(entry: entry)
        }
        .configurationDisplayName("Unread")
        .description("The number of unread articles and the newest headlines.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct VersolineWidgetBundle: WidgetBundle {
    var body: some Widget {
        VersolineWidget()
    }
}
