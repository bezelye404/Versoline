import SwiftUI
import AppKit
import AVFoundation

struct PodcastChapter: Identifiable, Hashable {
    let id = UUID()
    let timestamp: String
    let seconds: Double
    let title: String
}

// MARK: - Quote Card Generator & Preview (Native ImageRenderer / Zero External Deps)
