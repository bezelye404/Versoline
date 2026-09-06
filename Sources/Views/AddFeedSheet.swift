import SwiftUI

struct AddFeedSheet: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var feedURL: String = ""
    @State private var isValidating: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Add Feed")
                    .font(.title3.weight(.semibold))

                Text("Enter an RSS or Atom feed URL.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Feed URL")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("https://example.com/feed.xml", text: $feedURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addFeed()
                    }
            }
            .padding(.horizontal, 24)

            // Suggestions
            VStack(alignment: .leading, spacing: 8) {
                Text("Example Feeds")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 4) {
                    suggestionButton("BBC Türkçe", url: "https://feeds.bbci.co.uk/turkce/rss.xml")
                    suggestionButton("Hacker News", url: "https://hnrss.org/frontpage")
                    suggestionButton("The Verge", url: "https://www.theverge.com/rss/index.xml")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addFeed()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }
            .padding(24)
        }
        .frame(width: 420, height: 380)
    }

    private func addFeed() {
        guard !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var urlString = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Auto-prepend https:// if missing
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        isValidating = true

        Task {
            await store.addFeed(url: urlString)
            isValidating = false
            if store.errorMessage == nil {
                dismiss()
            }
        }
    }

    private func suggestionButton(_ title: String, url: String) -> some View {
        Button {
            feedURL = url
        } label: {
            HStack {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.caption)
                Spacer()
                Text(URL(string: url)?.host ?? url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.5))
        )
    }
}
