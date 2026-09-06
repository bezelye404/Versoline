import SwiftUI

struct QueuePopoverView: View {

    @State private var player = AudioPlayerService.shared
    @Environment(FeedStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Up Next"))
                    .font(.headline)

                Spacer()

                if !player.queue.isEmpty {
                    Button(String(localized: "Clear All")) {
                        player.clearQueue()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            Divider()

            if player.queue.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Queue is empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Right-click any episode in the list to Add to Queue or Play Next."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)

                                    if let duration = item.formattedDuration {
                                        Text(duration)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button {
                                    player.play(item: item, store: store)
                                    player.removeFromQueue(at: index)
                                } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "Play Now"))

                                Button {
                                    player.removeFromQueue(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "Remove from Queue"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
