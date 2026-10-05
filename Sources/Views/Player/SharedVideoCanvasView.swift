import SwiftUI
import WebKit

struct SharedVideoCanvasView: NSViewRepresentable {

    var isModalFullscreen: Bool = false

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        VideoPlayerService.shared.attach(to: container, isFullscreen: isModalFullscreen)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        VideoPlayerService.shared.attach(to: nsView, isFullscreen: isModalFullscreen)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        VideoPlayerService.shared.detachIfAttached(to: nsView)
    }
}
