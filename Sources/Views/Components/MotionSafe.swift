import SwiftUI

// SF Symbol effects and numeric content transitions are drawn by the system on already-rendered
// symbols/text, so they cost no extra memory and no layout work. Both helpers do nothing when the
// user has "Reduce Motion" turned on.

private struct MotionSafeBounce<Trigger: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Trigger

    func body(content: Content) -> some View {
        // A constant trigger while Reduce Motion is on means the effect never fires.
        content.symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : Optional(trigger))
    }
}

extension View {
    /// One short bounce of an SF Symbol whenever `trigger` changes (e.g. a bookmark star being toggled).
    func motionSafeBounce<Trigger: Equatable>(on trigger: Trigger) -> some View {
        modifier(MotionSafeBounce(trigger: trigger))
    }
}
