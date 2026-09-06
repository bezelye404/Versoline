import SwiftUI

@main
struct EasyRSSApp: App {

    @State private var store = FeedStore()

    init() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.applicationIconImage = NSImage(named: "AppIcon")
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
