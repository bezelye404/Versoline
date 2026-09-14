import Foundation

enum SidebarItem: Hashable, Identifiable {
    case all
    case unread
    case today
    case bookmarks
    case podcasts
    case downloaded
    case quickReads
    case longReads
    case videos
    case folder(UUID)
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "sidebar-all"
        case .unread: return "sidebar-unread"
        case .today: return "sidebar-today"
        case .bookmarks: return "sidebar-bookmarks"
        case .podcasts: return "sidebar-podcasts"
        case .downloaded: return "sidebar-downloaded"
        case .quickReads: return "sidebar-quick-reads"
        case .longReads: return "sidebar-long-reads"
        case .videos: return "sidebar-videos"
        case .folder(let uuid): return "sidebar-folder-\(uuid.uuidString)"
        case .feed(let uuid): return "sidebar-feed-\(uuid.uuidString)"
        }
    }
}

// MARK: - Daily Reading Stat Model for Native Charts

struct DailyReadingStat: Identifiable, Hashable {
    let id = UUID()
    let day: String
    let date: Date
    let count: Int
}
