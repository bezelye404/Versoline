import SwiftUI

struct EqualizerWaveformView: View {

    let isPlaying: Bool
    var tint: Color? = nil
    var barWidth: CGFloat = 2.0
    var maxHeight: CGFloat = 12

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0.0

    private var effectiveTint: Color {
        tint ?? theme.accentColor
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            bar(multiplier: 0.8, offset: 0.2)
            bar(multiplier: 1.0, offset: 0.6)
            bar(multiplier: 0.7, offset: 0.9)
            bar(multiplier: 0.9, offset: 0.4)
        }
        .frame(height: maxHeight)
        .onAppear {
            updateAnimation(playing: isPlaying)
        }
        .onDisappear {
            phase = 0.0
        }
        .onChange(of: isPlaying) { _, playing in
            updateAnimation(playing: playing)
        }
    }

    private func updateAnimation(playing: Bool) {
        if playing && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                phase = 0.0
            }
        }
    }

    @ViewBuilder
    private func bar(multiplier: CGFloat, offset: CGFloat) -> some View {
        let minScale: CGFloat = 0.25
        let currentScale: CGFloat = (isPlaying && !reduceMotion) ? (minScale + (1.0 - minScale) * multiplier * (0.3 + 0.7 * abs(sin((phase + offset) * .pi)))) : (isPlaying ? 0.6 : minScale)

        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(effectiveTint)
            .frame(width: barWidth, height: maxHeight)
            .scaleEffect(y: currentScale, anchor: .bottom)
    }
}
