import SwiftUI

struct ArticleDetailView: View {

    @Environment(FeedStore.self) private var store
    let selectedItem: FeedItem?

    // Always read fresh data from store
    private var currentItem: FeedItem? {
        guard let item = selectedItem else { return nil }
        return store.items[item.feedId]?.first { $0.id == item.id }
    }

    private var currentFeed: Feed? {
        guard let item = selectedItem else { return nil }
        return store.feed(for: item.feedId)
    }

    var body: some View {
        Group {
            if let item = currentItem {
                VStack(spacing: 0) {
                    articleHeader(item: item)
                    Divider()
                    articleContent(item: item)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("Select an article")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Select an article from the list on the left to read.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func articleHeader(item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 16) {
                if let feedTitle = currentFeed?.title {
                    Label(feedTitle, systemImage: "dot.radiowaves.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let author = item.author, !author.isEmpty {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let date = item.pubDate {
                    Label(formattedDate(date), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    // Bookmark toggle
                    Button {
                        store.toggleBookmark(item)
                    } label: {
                        Label(
                            item.isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                            systemImage: item.isBookmarked ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(item.isBookmarked ? .orange : .secondary)

                    // Read toggle
                    Button {
                        store.toggleReadStatus(item)
                    } label: {
                        Label(
                            item.isRead ? "Mark as Unread" : "Mark as Read",
                            systemImage: item.isRead ? "circle" : "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    // Open in browser
                    if let url = URL(string: item.link) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func articleContent(item: FeedItem) -> some View {
        let contentHTML = item.content ?? item.itemDescription

        if contentHTML.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
                Text("Content not available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let url = URL(string: item.link) {
                    Button("Open in Browser") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WebView(html: contentHTML)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
