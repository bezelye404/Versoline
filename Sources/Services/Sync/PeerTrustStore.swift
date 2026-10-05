import Foundation
import CryptoKit
import os

// Stored next to the library under `~/Library/Application Support/Versoline` (so a factory reset
// removes them) with owner-only file permissions. The private key never leaves this Mac.

struct TrustedPeer: Codable, Equatable, Identifiable, Sendable {
    let deviceId: UUID
    var name: String
    let publicKey: Data
    let pairedAt: Date

    var id: UUID { deviceId }
}

struct LocalPeerIdentity: Sendable {
    let deviceId: UUID
    let name: String
    let publicKey: Data
    fileprivate let privateKey: Data

    func sign(_ data: Data) -> Data {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey),
              let signature = try? key.signature(for: data) else { return Data() }
        return signature
    }
}

final class PeerTrustStore: @unchecked Sendable {

    private struct IdentityFile: Codable {
        let deviceId: UUID
        let privateKey: Data
    }

    private struct State {
        var identity: LocalPeerIdentity?
        var peers: [TrustedPeer] = []
        var loaded = false
    }

    private let directory: URL
    private let deviceName: @Sendable () -> String
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(directory: URL, deviceName: @escaping @Sendable () -> String = { Host.current().localizedName ?? "Mac" }) {
        self.directory = directory
        self.deviceName = deviceName
    }

    private var identityURL: URL { directory.appendingPathComponent("sync-identity.json") }
    private var peersURL: URL { directory.appendingPathComponent("sync-trusted-devices.json") }

    /// Loads the identity, creating and saving it on first use.
    func identity() -> LocalPeerIdentity? {
        state.withLock { s in
            loadIfNeeded(&s)
            if let existing = s.identity { return existing }

            let key = Curve25519.Signing.PrivateKey()
            let file = IdentityFile(deviceId: UUID(), privateKey: key.rawRepresentation)
            guard write(file, to: identityURL) else { return nil }
            let created = LocalPeerIdentity(deviceId: file.deviceId, name: deviceName(),
                                            publicKey: key.publicKey.rawRepresentation, privateKey: file.privateKey)
            s.identity = created
            return created
        }
    }

    var peers: [TrustedPeer] {
        state.withLock { s in
            loadIfNeeded(&s)
            return s.peers
        }
    }

    func peer(for deviceId: UUID) -> TrustedPeer? {
        peers.first { $0.deviceId == deviceId }
    }

    @discardableResult
    func trust(_ peer: TrustedPeer) -> Bool {
        state.withLock { s in
            loadIfNeeded(&s)
            s.peers.removeAll { $0.deviceId == peer.deviceId }
            s.peers.append(peer)
            return write(s.peers, to: peersURL)
        }
    }

    func remove(_ deviceId: UUID) {
        state.withLock { s in
            loadIfNeeded(&s)
            s.peers.removeAll { $0.deviceId == deviceId }
            _ = write(s.peers, to: peersURL)
        }
    }

    /// Forgets everything held in memory (used after a factory reset has deleted the files).
    func forgetAll() {
        state.withLock { $0 = State() }
    }

    private func loadIfNeeded(_ s: inout State) {
        guard !s.loaded else { return }
        s.loaded = true

        if let data = try? Data(contentsOf: identityURL),
           let file = try? JSONDecoder().decode(IdentityFile.self, from: data),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: file.privateKey) {
            s.identity = LocalPeerIdentity(deviceId: file.deviceId, name: deviceName(),
                                           publicKey: key.publicKey.rawRepresentation, privateKey: file.privateKey)
        }
        if let data = try? Data(contentsOf: peersURL),
           let decoded = try? JSONDecoder().decode([TrustedPeer].self, from: data) {
            s.peers = decoded
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
