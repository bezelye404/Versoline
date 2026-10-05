import SwiftUI
import Charts

struct FolderStreamRow: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme
    let folder: Folder

    var body: some View {
        NavigationLink(value: SidebarItem.folder(folder.id)) {
            HStack(spacing: 8) {
                Image(systemName: folder.isSmartFolder ? "sparkles" : "tray.2")
                    .font(.system(size: 13))
                    .foregroundStyle(folder.isSmartFolder ? theme.accentColor : Color.secondary)
                    .frame(width: 18)

                Text(folder.isSmartFolder ? String(localized: "Smart Stream") : String(localized: "All in Folder"))
                    .font(.system(size: 13))

                Spacer()

                let count = store.itemsCountForFolder(folder.id)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.badgeText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(theme.badgeBackground, in: Capsule())
                }
            }
        }
    }
}
