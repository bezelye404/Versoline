import Foundation

/// Gives freed heap pages back to the system.
///
/// Refreshing feeds parses many documents and creates a lot of short-lived strings. Swift frees them,
/// but the allocator keeps the emptied pages mapped, so the resident size stays at the refresh peak
/// even though the live data is small. `malloc_zone_pressure_relief` returns those pages. It is
/// cheap, safe at any time, and runs off the main thread.
enum MemoryRelief {
    static func trim() {
        Task.detached(priority: .utility) {
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }
}
