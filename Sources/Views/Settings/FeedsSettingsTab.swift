import SwiftUI

/// Muted keywords and feed diagnostics share one tab: both are about which feeds and articles you see.
struct FeedsSettingsTab: View {

    private enum Page: Hashable {
        case filters
        case rules
        case health
    }

    @State private var page: Page = .filters

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text("Filters").tag(Page.filters)
                Text("Rules").tag(Page.rules)
                Text("Feed Health").tag(Page.health)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch page {
            case .filters: FiltersSettingsTab()
            case .rules: RulesSettingsTab()
            case .health: FeedHealthSettingsTab()
            }
        }
    }
}
