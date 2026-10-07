import AppIntents
import SwiftUI
import WidgetKit

// MARK: Configuration

/// Which colors the widget uses: the app's current palette, or one of the app's palettes fixed for this widget.
enum PaletteChoice: String, AppEnum {
    case followApp
    case slate, sepia, sage, dusk, monochrome, nordic, espresso, matcha, bordeaux, solarized

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Palette"

    static let caseDisplayRepresentations: [PaletteChoice: DisplayRepresentation] = [
        .followApp: "Same as the app",
        .slate: "Slate",
        .sepia: "Sepia",
        .sage: "Sage",
        .dusk: "Dusk",
        .monochrome: "Monochrome",
        .nordic: "Nordic Frost",
        .espresso: "Espresso Amber",
        .matcha: "Matcha & Moss",
        .bordeaux: "Bordeaux Plum",
        .solarized: "Solarized Paper",
    ]
}

struct PaletteIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Colors"
    static let description = IntentDescription("Choose the colors of this widget.")

    @Parameter(title: "Palette", default: .followApp)
    var palette: PaletteChoice
}

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette
    let isPlaceholder: Bool
}

struct SnapshotProvider: AppIntentTimelineProvider {

    private func entry(for configuration: PaletteIntent, snapshot: WidgetSnapshot?, isPlaceholder: Bool = false) -> SnapshotEntry {
        let snapshot = snapshot ?? WidgetSnapshot(generatedAt: Date(), unreadCount: 0, headlines: [])
        let name = configuration.palette == .followApp ? snapshot.palette : configuration.palette.rawValue
        return SnapshotEntry(date: Date(), snapshot: snapshot, palette: .named(name), isPlaceholder: isPlaceholder)
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        entry(for: PaletteIntent(), snapshot: .placeholder, isPlaceholder: true)
    }

    func snapshot(for configuration: PaletteIntent, in context: Context) async -> SnapshotEntry {
        context.isPreview
            ? entry(for: configuration, snapshot: .placeholder, isPlaceholder: true)
            : entry(for: configuration, snapshot: WidgetSnapshot.load())
    }

    /// One entry. The app asks for a reload whenever what the widget shows changes; the widget never polls.
    func timeline(for configuration: PaletteIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [entry(for: configuration, snapshot: WidgetSnapshot.load())], policy: .never)
    }
}

// MARK: Colors

private extension WidgetPalette.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

private extension WidgetPalette.Pair {
    func color(_ scheme: ColorScheme) -> Color { (scheme == .dark ? dark : light).color }
}

// MARK: Views

struct VersolineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var accent: Color { entry.palette.accent.color(scheme) }
    private var bookmark: Color { entry.palette.bookmark.color(scheme) }

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
        .containerBackground(for: .widget) { entry.palette.background.color(scheme) }
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
                .foregroundStyle(accent)
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
                    .foregroundStyle(accent)
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
                        .foregroundStyle(bookmark)
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
        AppIntentConfiguration(kind: kind, intent: PaletteIntent.self, provider: SnapshotProvider()) { entry in
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
