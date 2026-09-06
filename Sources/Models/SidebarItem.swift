import Foundation

enum SidebarItem: Hashable, Identifiable {
    case all
    case unread
    case today
    case bookmarks
    case podcasts
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "sidebar-all"
        case .unread: return "sidebar-unread"
        case .today: return "sidebar-today"
        case .bookmarks: return "sidebar-bookmarks"
        case .podcasts: return "sidebar-podcasts"
        case .feed(let uuid): return "sidebar-feed-\(uuid.uuidString)"
        }
    }
}
