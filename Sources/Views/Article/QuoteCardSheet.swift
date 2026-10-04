import SwiftUI
import AppKit
import AVFoundation

struct QuoteCardSheet: View {
    let item: FeedItem
    let feedTitle: String?
    @Environment(\.dismiss) private var dismiss
    @State private var quoteText: String = ""
    @State private var selectedPalette: AppColorPalette = .slate
    @State private var isCopied: Bool = false

    init(item: FeedItem, feedTitle: String?) {
        self.item = item
        self.feedTitle = feedTitle
        let initial = item.itemDescription.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
        _quoteText = State(initialValue: initial.isEmpty ? item.title : String(initial.prefix(280)))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(String(localized: "Quote Card Generator"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Live Preview Card
            QuoteCardPreview(
                quote: quoteText,
                articleTitle: item.title,
                author: item.author,
                feedTitle: feedTitle ?? "Versoline",
                palette: selectedPalette
            )
            .padding(.horizontal, 20)

            // Edit Quote
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Quote Text:"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $quoteText)
                    .font(.system(size: 13))
                    .frame(height: 60)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedPalette.hairlineBorder, lineWidth: 1))
            }
            .padding(.horizontal, 20)

            // Palette selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text(String(localized: "Palette:"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(AppColorPalette.allCases) { palette in
                        Button {
                            selectedPalette = palette
                        } label: {
                            Circle()
                                .fill(palette.accentColor)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: selectedPalette == palette ? 2 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(selectedPalette == palette ? palette.accentColor : Color.clear, lineWidth: 1)
                                        .scaleEffect(1.3)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(palette.title)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button {
                    copyCardToPasteboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? String(localized: "Copied!") : String(localized: "Copy Image to Clipboard"))
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedPalette.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    private func copyCardToPasteboard() {
        let card = QuoteCardPreview(
            quote: quoteText,
            articleTitle: item.title,
            author: item.author,
            feedTitle: feedTitle ?? "Versoline",
            palette: selectedPalette
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0 // High-DPI Retina
        if let image = renderer.nsImage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            AppHaptics.notification()
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCopied = false
            }
        }
    }
}

struct QuoteCardPreview: View {
    let quote: String
    let articleTitle: String
    let author: String?
    let feedTitle: String
    let palette: AppColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.accentColor)
                    .frame(width: 10, height: 10)
                Text(feedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "quote.opening")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.accentColor.opacity(0.4))
            }

            Text("“\(quote)”")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(0.4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(articleTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let author, !author.isEmpty {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Versoline")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}
