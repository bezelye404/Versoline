import SwiftUI
import AppKit

// MARK: - Native reader
//
// Renders an ArticleDocument with plain SwiftUI text and images. No web view, so reading an article needs no
// WebContent/GPU/Networking helper processes; blocks are lazy so long articles only keep what is on screen.

struct NativeReaderView: View {
    let document: ArticleDocument
    let title: String
    let metaLine: String
    let byline: String
    let fontSize: Double
    let fontFamily: ReaderFontFamily
    let lineHeight: ReaderLineHeight
    let theme: ReaderTheme
    let isBionic: Bool
    let onOpenURL: (URL) -> Void

    @Environment(\.appTheme) private var appTheme

    private var textColor: Color { theme.nativeText ?? .primary }
    private var linkColor: Color { theme.nativeLink ?? appTheme.accentColor }
    private var lineSpacing: CGFloat {
        let multiplier = Double(lineHeight.rawValue) ?? 1.8
        return max(2, fontSize * (multiplier - 1.2) * 0.8)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                header
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
        }
        .background(theme.nativeBackground ?? Color.clear)
        .foregroundStyle(textColor)
        .tint(linkColor)
        .environment(\.openURL, OpenURLAction { url in
            onOpenURL(url)
            return .handled
        })
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .opacity(0.6)
            }
            Text(title)
                .font(.system(size: fontSize * 1.7, weight: .bold, design: fontFamily.nativeDesign))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !byline.isEmpty {
                Text(byline)
                    .font(.system(size: 13))
                    .opacity(0.72)
            }
            Divider().opacity(0.6).padding(.top, 8)
        }
        .padding(.bottom, 4)
    }

    // MARK: Blocks

    private func styled(_ text: AttributedString) -> AttributedString {
        isBionic ? BionicReading.apply(to: text) : text
    }

    private func bodyFont(scale: Double = 1, weight: Font.Weight = .regular) -> Font {
        .system(size: fontSize * scale, weight: weight, design: fontFamily.nativeDesign)
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            let scale: Double = level <= 1 ? 1.45 : (level == 2 ? 1.3 : (level == 3 ? 1.15 : 1.05))
            Text(text)
                .font(bodyFont(scale: scale, weight: .semibold))
                .padding(.top, fontSize * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(styled(text))
                .font(bodyFont())
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)

        case .quote(let text):
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(textColor.opacity(0.3))
                    .frame(width: 3)
                Text(styled(text))
                    .font(bodyFont())
                    .lineSpacing(lineSpacing)
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: fontSize * 0.45) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(bodyFont())
                            .monospacedDigit()
                            .opacity(0.6)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(styled(item))
                            .font(bodyFont())
                            .lineSpacing(lineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: max(12, fontSize * 0.85), design: .monospaced))
                    .lineSpacing(3)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .image(let url, let alt, let caption):
            ReaderImageView(url: url, alt: alt, caption: caption, captionColor: textColor.opacity(0.6))

        case .rule:
            Divider()
        }
    }
}

// MARK: - Image

private struct ReaderImageView: View {
    let url: URL
    let alt: String
    let caption: String?
    let captionColor: Color

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        if failed {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .transition(.opacity)
                    } else {
                        Color.secondary.opacity(0.08).frame(height: 200)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(alt)

                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(captionColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task(id: url) {
                // Downsampled to what a 720pt column needs on a Retina display; kept off the heap when scrolled away.
                if let loaded = await ImageDownsampleCache.shared.image(for: url, maxPixelSize: 1440) {
                    withAnimation(AppAnimation.quickFeedback) { image = loaded }
                } else {
                    failed = true
                }
            }
        }
    }
}
