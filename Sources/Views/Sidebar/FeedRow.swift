import SwiftUI
import Charts

struct FeedRow: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme
    let feed: Feed
    var isInsidePinnedSection: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(hostOrURL: feed.url, size: 16)
                .frame(width: 18, height: 18)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(AppAnimation.hover, value: isHovered)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(feed.title)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(1)

                    if feed.isPinned && !isInsidePinnedSection {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.accentColor.opacity(0.85))
                    }
                }
            }

            Spacer()

            let unread = store.unreadCount(for: feed.id)
            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(AppAnimation.bouncy, value: unread)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Native Reading Insights Sheet (Apple Charts / Zero 3rd-party libs)
