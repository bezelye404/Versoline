import Testing
import Foundation
import CryptoKit
@testable import Versoline

@Suite("Peer Handshake Tests")
struct PeerHandshakeTests {

    /// A device with its own identity and trust list, backed by a temp directory.
    final class Device {
        let store: PeerTrustStore
        let identity: LocalPeerIdentity
        let directory: URL

        init(name: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            store = PeerTrustStore(directory: directory, deviceName: { name })
            identity = try #require(store.identity())
        }

        func handshake(role: PeerHandshake.Role, pairing: Bool) -> PeerHandshake {
            PeerHandshake(deviceId: identity.deviceId, name: identity.name, publicKey: identity.publicKey,
                          sign: { self.identity.sign($0) }, trusted: { self.store.peer(for: $0) },
                          pairingAllowed: pairing, role: role)
        }

        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    struct Outcome {
        var eventsA: [HandshakeEvent] = []
        var eventsB: [HandshakeEvent] = []
    }

    /// Runs two handshakes against each other. `decideA`/`decideB` answer confirmation prompts.
    private func run(
        _ a: PeerHandshake, _ b: PeerHandshake,
        decideA: Bool = true, decideB: Bool = true,
        tamper: ((inout HandshakeMessage, _ fromA: Bool) -> Void)? = nil
    ) -> Outcome {
        var outcome = Outcome()
        var toA: [HandshakeMessage] = []
        var toB: [HandshakeMessage] = []

        func absorb(_ step: HandshakeStep, fromA: Bool) {
            for var message in step.send {
                tamper?(&message, fromA)
                if fromA { toB.append(message) } else { toA.append(message) }
            }
            guard let event = step.event else { return }
            if fromA { outcome.eventsA.append(event) } else { outcome.eventsB.append(event) }
            if case .needsConfirmation = event {
                let reply = fromA ? a.userDecision(accepted: decideA) : b.userDecision(accepted: decideB)
                absorb(reply, fromA: fromA)
            }
        }

        absorb(a.start(), fromA: true)
        absorb(b.start(), fromA: false)
        var guardCounter = 0
        while (!toA.isEmpty || !toB.isEmpty) && guardCounter < 100 {
            guardCounter += 1
            if !toA.isEmpty { absorb(a.receive(toA.removeFirst()), fromA: true) }
            if !toB.isEmpty { absorb(b.receive(toB.removeFirst()), fromA: false) }
        }
        return outcome
    }

    private func code(in events: [HandshakeEvent]) -> String? {
        for case .needsConfirmation(_, let code) in events { return code }
        return nil
    }

    private func failure(in events: [HandshakeEvent]) -> String? {
        for case .failed(let reason) in events { return reason }
        return nil
    }

    private func authenticated(in events: [HandshakeEvent]) -> (TrustedPeer, Bool)? {
        for case .authenticated(let peer, let newly) in events { return (peer, newly) }
        return nil
    }

    // MARK: - Pairing

    @Test("Pairing shows the same code on both devices and both end up authenticated and new")
    func pairingSucceeds() throws {
        let alice = try Device(name: "Alice Mac"); let bob = try Device(name: "Bob Mac")
        defer { alice.cleanup(); bob.cleanup() }

        let result = run(alice.handshake(role: .initiator, pairing: true), bob.handshake(role: .responder, pairing: true))

        let codeA = try #require(code(in: result.eventsA))
        let codeB = try #require(code(in: result.eventsB))
        #expect(codeA == codeB)
        #expect(codeA.count == 6)
        let (peerSeenByA, newA) = try #require(authenticated(in: result.eventsA))
        let (peerSeenByB, newB) = try #require(authenticated(in: result.eventsB))
        #expect(newA && newB)
        #expect(peerSeenByA.deviceId == bob.identity.deviceId)
        #expect(peerSeenByB.deviceId == alice.identity.deviceId)
        #expect(peerSeenByA.publicKey == bob.identity.publicKey)
    }

    @Test("Without pairing mode an unknown device is refused")
    func unknownRefused() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup() }

        let result = run(alice.handshake(role: .initiator, pairing: false), bob.handshake(role: .responder, pairing: true))

        #expect(failure(in: result.eventsA) != nil)
        #expect(authenticated(in: result.eventsA) == nil)
        #expect(authenticated(in: result.eventsB) == nil)
    }

    @Test("If either user rejects the code nobody is authenticated")
    func rejection() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup() }

        let result = run(alice.handshake(role: .initiator, pairing: true), bob.handshake(role: .responder, pairing: true), decideB: false)

        #expect(failure(in: result.eventsA) != nil)
        #expect(failure(in: result.eventsB) != nil)
        #expect(authenticated(in: result.eventsA) == nil)
        #expect(authenticated(in: result.eventsB) == nil)
    }

    @Test("A man in the middle ends up with different codes on the two screens")
    func manInTheMiddle() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B"); let mallory = try Device(name: "M")
        defer { alice.cleanup(); bob.cleanup(); mallory.cleanup() }

        // Mallory runs one handshake towards Alice and another towards Bob.
        let towardsAlice = run(alice.handshake(role: .initiator, pairing: true), mallory.handshake(role: .responder, pairing: true), decideA: false)
        let towardsBob = run(mallory.handshake(role: .initiator, pairing: true), bob.handshake(role: .responder, pairing: true), decideB: false)

        let codeAlice = try #require(code(in: towardsAlice.eventsA))
        let codeBob = try #require(code(in: towardsBob.eventsB))
        #expect(codeAlice != codeBob)
    }

    @Test("Pairing fails if the revealed nonce does not match the commitment")
    func commitmentMismatch() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup() }

        let result = run(alice.handshake(role: .initiator, pairing: true), bob.handshake(role: .responder, pairing: true)) { message, fromA in
            if fromA, case .pairReveal = message { message = .pairReveal(Data(repeating: 7, count: 16)) }
        }

        #expect(failure(in: result.eventsB) != nil)
        #expect(authenticated(in: result.eventsB) == nil)
    }

    // MARK: - Known devices

    private func pair(_ a: Device, _ b: Device) throws {
        let result = run(a.handshake(role: .initiator, pairing: true), b.handshake(role: .responder, pairing: true))
        let (forA, _) = try #require(authenticated(in: result.eventsA))
        let (forB, _) = try #require(authenticated(in: result.eventsB))
        a.store.trust(forA)
        b.store.trust(forB)
    }

    @Test("Paired devices reconnect without any prompt, in either role")
    func reconnect() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup() }
        try pair(alice, bob)

        for roles in [(PeerHandshake.Role.initiator, PeerHandshake.Role.responder), (.responder, .initiator)] {
            let result = run(alice.handshake(role: roles.0, pairing: false), bob.handshake(role: roles.1, pairing: false))

            #expect(code(in: result.eventsA) == nil)
            let (_, newlyPaired) = try #require(authenticated(in: result.eventsA))
            #expect(!newlyPaired)
            #expect(authenticated(in: result.eventsB) != nil)
        }
    }

    @Test("A known device with a different key is refused")
    func keyChanged() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        let impostor = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup(); impostor.cleanup() }
        try pair(alice, bob)
        // The impostor claims Bob's device id but holds a different key.
        let forged = PeerHandshake(deviceId: bob.identity.deviceId, name: "B", publicKey: impostor.identity.publicKey,
                                   sign: { impostor.identity.sign($0) }, trusted: { _ in nil }, pairingAllowed: false, role: .responder)

        let result = run(alice.handshake(role: .initiator, pairing: false), forged)

        #expect(failure(in: result.eventsA) != nil)
        #expect(authenticated(in: result.eventsA) == nil)
    }

    @Test("A forged proof from a known device id and key is rejected")
    func forgedProof() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup() }
        try pair(alice, bob)

        let result = run(alice.handshake(role: .initiator, pairing: false), bob.handshake(role: .responder, pairing: false)) { message, fromA in
            if !fromA, case .proof = message { message = .proof(Data(repeating: 1, count: 64)) }
        }

        #expect(failure(in: result.eventsA) != nil)
        #expect(authenticated(in: result.eventsA) == nil)
    }

    @Test("A recorded proof cannot be replayed in a new session")
    func replay() throws {
        let alice = try Device(name: "A"); let bob = try Device(name: "B")
        defer { alice.cleanup(); bob.cleanup() }
        try pair(alice, bob)

        var recorded: Data?
        _ = run(alice.handshake(role: .initiator, pairing: false), bob.handshake(role: .responder, pairing: false)) { message, fromA in
            if !fromA, case .proof(let p) = message { recorded = p }
        }
        let replayed = try #require(recorded)

        let result = run(alice.handshake(role: .initiator, pairing: false), bob.handshake(role: .responder, pairing: false)) { message, fromA in
            if !fromA, case .proof = message { message = .proof(replayed) }
        }

        #expect(failure(in: result.eventsA) != nil)
    }

    @Test("Out-of-order messages fail the handshake")
    func unexpectedMessage() throws {
        let alice = try Device(name: "A")
        defer { alice.cleanup() }
        let handshake = alice.handshake(role: .initiator, pairing: true)
        _ = handshake.start()

        let step = handshake.receive(.pairReveal(Data(repeating: 0, count: 16)))

        if case .failed = step.event {} else { Issue.record("expected failure") }
    }

    @Test("Hello with a wrong-sized key or nonce is rejected")
    func malformedHello() throws {
        let alice = try Device(name: "A")
        defer { alice.cleanup() }
        let handshake = alice.handshake(role: .responder, pairing: true)
        _ = handshake.start()

        let step = handshake.receive(.hello(PeerHello(deviceId: UUID(), name: "x", publicKey: Data(count: 5), nonce: Data(count: 32))))

        if case .failed = step.event {} else { Issue.record("expected failure") }
    }

    // MARK: - Trust store

    @Test("forgetAll clears the in-memory identity and pairings so a reset does not resurrect them")
    func forgetAll() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PeerTrustStore(directory: dir, deviceName: { "Mac" })
        let oldIdentity = try #require(store.identity())
        store.trust(TrustedPeer(deviceId: UUID(), name: "Other", publicKey: Data(repeating: 3, count: 32), pairedAt: Date()))
        try FileManager.default.removeItem(at: dir) // what a factory reset does

        store.forgetAll()

        #expect(store.peers.isEmpty)
        #expect(store.identity()?.deviceId != oldIdentity.deviceId)
    }

    @Test("Identity and trusted devices persist and the files are owner-only")
    func trustStorePersistence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = PeerTrustStore(directory: dir, deviceName: { "Mac" })
        let identity = try #require(first.identity())
        let peer = TrustedPeer(deviceId: UUID(), name: "Other", publicKey: Data(repeating: 3, count: 32), pairedAt: Date())
        first.trust(peer)

        let second = PeerTrustStore(directory: dir, deviceName: { "Mac" })

        #expect(second.identity()?.deviceId == identity.deviceId)
        #expect(second.identity()?.publicKey == identity.publicKey)
        #expect(second.peers == [peer])
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("sync-identity.json").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)

        second.remove(peer.deviceId)
        #expect(PeerTrustStore(directory: dir, deviceName: { "Mac" }).peers.isEmpty)
    }
}
