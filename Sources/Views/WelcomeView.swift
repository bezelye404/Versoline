import SwiftUI

/// Shown in the list column while the library is empty: one clear place to start instead of three
/// empty panels.
struct WelcomeView: View {

    var addByURL: () -> Void
    var browseCatalog: () -> Void
    var importOPML: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "newspaper")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text(String(localized: "Welcome to Versoline"))
                    .font(.title3.weight(.semibold))
                Text(String(localized: "Add your first feed to start reading."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button(action: addByURL) {
                    Label(String(localized: "Add a Feed by URL"), systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: browseCatalog) {
                    Label(String(localized: "Browse the Catalog"), systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: importOPML) {
                    Label(String(localized: "Import OPML"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(maxWidth: 240)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
