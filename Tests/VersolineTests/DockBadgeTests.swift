import Testing
@testable import Versoline

struct DockBadgeTests {
    @Test func theBadgeShowsTheCountAndStaysShortForBigNumbers() {
        #expect(DockBadge.label(forUnreadCount: 0) == nil)
        #expect(DockBadge.label(forUnreadCount: -3) == nil)
        #expect(DockBadge.label(forUnreadCount: 1) == "1")
        #expect(DockBadge.label(forUnreadCount: 999) == "999")
        #expect(DockBadge.label(forUnreadCount: 1_000) == "999+")
        #expect(DockBadge.label(forUnreadCount: 1_578) == "999+")
    }
}
