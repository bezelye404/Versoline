import SwiftUI
import AppKit
import WebKit

struct FeedHealthSettingsTab: View {

    @Environment(FeedStore.self) private var store
    private var healthService = FeedHealthService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feed Health Diagnostics")
                        .font(.headline)
                    Text("Scan feeds for HTTP errors, dead links, or inactive sources.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if healthService.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button {
                    Task {
                        await healthService.scan(store: store)
                    }
                } label: {
                    Label(healthService.isScanning ? "Scanning..." : "Scan Feeds", systemImage: "arrow.clockwise")
                }
                .disabled(healthService.isScanning)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Summary bar if reports exist
            if !healthService.reports.isEmpty {
                let brokenCount = healthService.reports.filter {
                    if case .broken = $0.status { return true }
                    return false
                }.count
                let staleCount = healthService.reports.filter {
                    if case .stale = $0.status { return true }
                    return false
                }.count
                let healthyCount = healthService.reports.filter {
                    if case .healthy = $0.status { return true }
                    return false
                }.count

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("\(healthyCount) Healthy")
                            .font(.caption)
                    }

                    if staleCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(.orange).frame(width: 8, height: 8)
                            Text("\(staleCount) Stale (>6 mos)")
                                .font(.caption)
                        }
                    }

                    if brokenCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("\(brokenCount) Broken")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        Spacer()

                        Button("Remove All Broken Feeds") {
                            healthService.removeAllBroken(store: store)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

                Divider()
            }

            // Report List
            if healthService.reports.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Diagnostics Run Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click 'Scan Feeds' above to test feed accessibility, response times, and identify broken feeds.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(healthService.reports) { report in
                        HStack(spacing: 10) {
                            switch report.status {
                            case .healthy:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .stale(let days):
                                Image(systemName: "clock.badge.exclamationmark.fill")
                                    .foregroundStyle(.orange)
                                    .help("No articles in \(days) days")
                            case .broken(let reason):
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .help(reason)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.feedTitle)
                                    .font(.system(.body, weight: .medium))
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(report.feedURL)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)

                                    if case .stale(let days) = report.status {
                                        Text("• Inactive for \(days) days")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else if case .broken(let reason) = report.status {
                                        Text("• \(reason)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Spacer()

                            if report.status.isProblematic {
                                Button {
                                    healthService.removeFeed(report, store: store)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove feed")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}
