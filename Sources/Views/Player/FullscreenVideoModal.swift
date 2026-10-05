import SwiftUI
import WebKit

struct FullscreenVideoModal: View {
    let videoID: String
    let title: String
    let link: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            NativeVideoPlayerCanvas(
                videoID: videoID,
                title: title,
                isModalFullscreen: true,
                onToggleFullscreen: onClose
            )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
