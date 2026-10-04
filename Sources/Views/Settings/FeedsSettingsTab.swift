import SwiftUI

/// Muted keywords and feed diagnostics share one tab: both are about which feeds and articles you see.
struct FeedsSettingsTab: View {

    private enum Page: Hashable {
        case filters
        case health
    }

    @State private var page: Page = .filters

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text("Filters").tag(Page.filters)
                Text("Feed Health").tag(Page.health)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch page {
            case .filters: FiltersSettingsTab()
            case .health: FeedHealthSettingsTab()
            }
        }
    }
}
