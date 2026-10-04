import SwiftUI

struct SyncSettingsTab: View {

    @State private var coordinator = SyncCoordinator.shared
    @State private var peerPendingRemoval: TrustedPeer?

    var body: some View {
        Form {
            Section("Nearby Sync") {
                Toggle("Sync with My Paired Macs", isOn: Binding(
                    get: { coordinator.isEnabled },
                    set: { coordinator.setEnabled($0) }
                ))

                Text("Keeps feeds, folders, bookmarks, read states, and settings in sync between your own Macs over the local network. Data goes directly from Mac to Mac, is encrypted, and never touches a server or the cloud. Only devices you pair below can connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if coordinator.isEnabled {
                    HStack {
                        Circle()
                            .fill(coordinator.connectedPeerCount > 0 ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(coordinator.connectedPeerCount > 0
                             ? String(format: String(localized: "%d paired device(s) connected"), coordinator.connectedPeerCount)
                             : String(localized: "Looking for your paired devices on the local network...")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Paired Devices") {
                if coordinator.trustedPeers.isEmpty {
                    Text("No devices paired yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.trustedPeers) { peer in
                        HStack {
                            Image(systemName: "laptopcomputer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                Text(String(format: String(localized: "Paired %@"), peer.pairedAt.formatted(date: .abbreviated, time: .omitted)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) { peerPendingRemoval = peer }
                        }
                    }
                }

                pairingControls
            }

            if coordinator.isEnabled && !coordinator.trustedPeers.isEmpty {
                Section("Sync Status & Actions") {
                    if let lastSync = coordinator.lastSyncDate {
                        LabeledContent("Last Synchronized:", value: lastSync.formatted(date: .abbreviated, time: .standard))
                    } else {
                        LabeledContent("Last Synchronized:", value: String(localized: "Not yet synced"))
                    }

                    Button {
                        coordinator.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(coordinator.connectedPeerCount == 0)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
        .confirmationDialog(
            String(localized: "Remove this device?"),
            isPresented: Binding(get: { peerPendingRemoval != nil }, set: { if !$0 { peerPendingRemoval = nil } }),
            presenting: peerPendingRemoval
        ) { peer in
            Button("Remove", role: .destructive) { coordinator.removeTrustedPeer(peer) }
        } message: { peer in
            Text(String(format: String(localized: "%@ will no longer be able to sync with this Mac. You can pair it again later."), peer.name))
        }
    }

    @ViewBuilder
    private var pairingControls: some View {
        switch coordinator.pairingState {
        case .idle:
            Button {
                coordinator.startPairing()
            } label: {
                Label("Pair New Device", systemImage: "plus.circle")
            }
            .disabled(!coordinator.isEnabled)

            if !coordinator.isEnabled {
                Text("Turn on Nearby Sync first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .searching:
            HStack {
                ProgressView().controlSize(.small)
                Text("Open Pair New Device on your other Mac too. Both Macs must be on the same network.")
                    .font(.caption)
            }
            Button("Cancel") { coordinator.cancelPairing() }

        case .confirming(let peerName, let code):
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: String(localized: "Does %@ show this code?"), peerName))
                Text(code)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .kerning(4)
                Text("Only continue if both Macs show exactly the same six digits. If they differ, someone else may be trying to connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Codes Match") { coordinator.confirmPairing(codesMatch: true) }
                        .buttonStyle(.borderedProminent)
                    Button("They Differ", role: .destructive) { coordinator.confirmPairing(codesMatch: false) }
                }
            }

        case .succeeded(let peerName):
            Label(String(format: String(localized: "%@ is now paired."), peerName), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Done") { coordinator.cancelPairing() }

        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Button("Try Again") { coordinator.startPairing() }
            Button("Cancel") { coordinator.cancelPairing() }
        }
    }
}
