import Testing
import SwiftUI
@testable import Versoline

@Suite("AppAnimation Tests")
@MainActor
struct AppAnimationTests {

    @Test("Reduce Motion swaps any animation for the short fade")
    func reduceMotionUsesFade() {
        #expect(AppAnimation.motion(.bouncy, reduceMotion: true) == AppAnimation.reduced)
        #expect(AppAnimation.motion(.spring(response: 0.3, dampingFraction: 0.5), reduceMotion: true) == AppAnimation.reduced)
    }

    @Test("Without Reduce Motion the requested animation is kept")
    func normalMotionIsUntouched() {
        #expect(AppAnimation.motion(.bouncy, reduceMotion: false) == .bouncy)
    }

    @Test("Stagger delay is capped at 0.15 seconds")
    func staggerCap() {
        #expect(AppAnimation.stagger(index: 0) == 0)
        #expect(AppAnimation.stagger(index: 100) == 0.15)
    }
}
