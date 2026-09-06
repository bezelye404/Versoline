import SwiftUI

struct EqualizerWaveformView: View {

    let isPlaying: Bool
    var tint: Color = .accentColor
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 14

    @State private var phase: CGFloat = 0.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(multiplier: 0.8, offset: 0.2)
            bar(multiplier: 1.0, offset: 0.6)
            bar(multiplier: 0.7, offset: 0.9)
            bar(multiplier: 0.9, offset: 0.4)
        }
        .frame(height: maxHeight)
        .onAppear {
            if isPlaying {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    phase = 0.0
                }
            }
        }
    }

    @ViewBuilder
    private func bar(multiplier: CGFloat, offset: CGFloat) -> some View {
        let baseHeight: CGFloat = 3.5
        let dynamicHeight = isPlaying ? (baseHeight + (maxHeight - baseHeight) * multiplier * (0.3 + 0.7 * abs(sin((phase + offset) * .pi)))) : baseHeight

        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(tint)
            .frame(width: barWidth, height: dynamicHeight)
    }
}
