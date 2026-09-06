import SwiftUI

@main
struct EasyRSSApp: App {

    @State private var store = FeedStore()

    init() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.applicationIconImage = Self.createNativeTahoeIcon()
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // macOS dock
    private static func createNativeTahoeIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // macOS Dock için hafif alt gölge
        context.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowBlurRadius = 18
        shadow.set()

        // İkon gövdesi (squircle) ve lacivert arka plan
        let squircleRect = NSRect(x: 48, y: 56, width: 416, height: 416)
        let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: 94, yRadius: 94)
        
        let navyColor = NSColor(red: 0.11, green: 0.16, blue: 0.25, alpha: 1.0)
        navyColor.setFill()
        squirclePath.fill()
        context.restoreGState()

        // İnce açık renk kenar çizgisi
        NSColor.white.withAlphaComponent(0.08).setStroke()
        squirclePath.lineWidth = 1.5
        squirclePath.stroke()

        // Ortadaki RSS sembolü (pastel turuncu)
        let tintColor = NSColor(red: 0.92, green: 0.65, blue: 0.44, alpha: 1.0)
        let pointConfig = NSImage.SymbolConfiguration(pointSize: 180, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [tintColor])
        let fullConfig = pointConfig.applying(colorConfig)

        if let symbolImage = NSImage(systemSymbolName: "dot.radiowaves.up.forward", accessibilityDescription: nil)?
            .withSymbolConfiguration(fullConfig) {
            
            let symbolSize = symbolImage.size
            let symbolX = squircleRect.midX - (symbolSize.width / 2)
            let symbolY = squircleRect.midY - (symbolSize.height / 2)
            let drawRect = NSRect(x: symbolX, y: symbolY, width: symbolSize.width, height: symbolSize.height)

            symbolImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        image.unlockFocus()
        return image
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
