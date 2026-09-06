import Foundation

enum SidebarItem: Hashable, Identifiable {
    case all
    case bookmarks
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "sidebar-all"
        case .bookmarks: return "sidebar-bookmarks"
        case .feed(let uuid): return "sidebar-feed-\(uuid.uuidString)"
        }
    }
}
