import SwiftUI
import AppKit
import WebKit

struct FiltersSettingsTab: View {

    @AppStorage(AppSettingsKeys.mutedKeywords) private var mutedKeywordsRaw = ""
    @State private var newKeyword = ""

    private var keywords: [String] {
        mutedKeywordsRaw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Articles containing these keywords in their title or summary will be automatically hidden from your article lists.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                TextField("Add keyword to mute (e.g. spoiler, crypto)...", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addKeyword()
                    }

                Button("Add") {
                    addKeyword()
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if keywords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No muted keywords yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(keywords, id: \.self) { kw in
                        HStack {
                            Image(systemName: "nosign")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.8))
                            Text(kw)
                                .font(.callout)
                            Spacer()
                            Button {
                                removeKeyword(kw)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = keywords
        if !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            current.append(trimmed)
            mutedKeywordsRaw = current.joined(separator: ",")
        }
        newKeyword = ""
    }

    private func removeKeyword(_ kw: String) {
        var current = keywords
        current.removeAll { $0 == kw }
        mutedKeywordsRaw = current.joined(separator: ",")
    }
}

// MARK: - 5. Sync Tab
