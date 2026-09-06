import Foundation

enum SidebarItem: Hashable, Identifiable {
    case all
    case unread
    case today
    case bookmarks
    case podcasts
    case downloaded
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
        case .folder(let uuid): return "sidebar-folder-\(uuid.uuidString)"
        case .feed(let uuid): return "sidebar-feed-\(uuid.uuidString)"
        }
    }
}
