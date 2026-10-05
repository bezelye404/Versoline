import Foundation
import CryptoKit

// Nearby sync only talks to devices the user has paired. Two things are enforced here, independent of
// the transport (MultipeerConnectivity), so they can be tested without a network:
//
// Known devices prove they hold the private key they were paired with (signed challenge over
//    both fresh nonces and both device ids).
// Unknown devices can only join while *both* users have opened "Pair New Device". Both screens then
//    show the same 6-digit code and each user confirms it matches. The code is derived from both
//    identity keys and from nonces exchanged with a commit-reveal step, so a man in the middle
//    cannot choose keys that make the two codes agree.
//
// Only CryptoKit (first-party) is used.

struct PeerHello: Codable, Equatable, Sendable {
    let deviceId: UUID
    let name: String
    let publicKey: Data
    let nonce: Data
}

enum HandshakeMessage: Codable, Equatable, Sendable {
    case hello(PeerHello)
    case pairCommit(Data)
    case pairNonce(Data)
    case pairReveal(Data)
    case pairDecision(accepted: Bool)
    case proof(Data)
}

enum HandshakeEvent: Equatable, Sendable {
    /// Unknown device during pairing: show `code` and ask the user whether it matches the other screen.
    case needsConfirmation(peerName: String, code: String)
    /// The peer proved its identity. `newlyPaired` is true when it should now be added to the trust list.
    case authenticated(TrustedPeer, newlyPaired: Bool)
    case failed(String)
}

struct HandshakeStep: Sendable {
    var send: [HandshakeMessage] = []
    var event: HandshakeEvent?
}

final class PeerHandshake {

    enum Role: Sendable { case initiator, responder }

    private enum State {
        case idle
        case awaitingHello
        case awaitingProof(knownPeer: Bool)
        case pairAwaitingCommit
        case pairAwaitingNonce
        case pairAwaitingReveal
        case pairAwaitingUser
        case pairAwaitingDecision
        case finished
    }

    private let deviceId: UUID
    private let name: String
    private let publicKey: Data
    private let sign: (Data) -> Data
    private let lookupTrusted: (UUID) -> TrustedPeer?
    private let pairingAllowed: Bool
    private let role: Role

    private var state: State = .idle
    private let myNonce: Data
    private var peer: PeerHello?

    // Pairing
    private var myPairNonce: Data
    private var peerCommitment: Data?
    private var peerPairNonce: Data?
    private var iAccepted = false
    private var peerAccepted = false

    init(
        deviceId: UUID,
        name: String,
        publicKey: Data,
        sign: @escaping (Data) -> Data,
        trusted: @escaping (UUID) -> TrustedPeer?,
        pairingAllowed: Bool,
        role: Role,
        randomBytes: (Int) -> Data = PeerHandshake.secureRandom
    ) {
        self.deviceId = deviceId
        self.name = String(name.prefix(64))
        self.publicKey = publicKey
        self.sign = sign
        self.lookupTrusted = trusted
        self.pairingAllowed = pairingAllowed
        self.role = role
        self.myNonce = randomBytes(32)
        self.myPairNonce = randomBytes(16)
    }

    static func secureRandom(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            // Extremely unlikely; fall back to CryptoKit's generator rather than weak randomness.
            return Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0.prefix(count)) })
        }
        return Data(bytes)
    }

    /// First message to send once the transport is connected.
    func start() -> HandshakeStep {
        guard case .idle = state else { return HandshakeStep() }
        state = .awaitingHello
        return HandshakeStep(send: [.hello(PeerHello(deviceId: deviceId, name: name, publicKey: publicKey, nonce: myNonce))])
    }

    func receive(_ message: HandshakeMessage) -> HandshakeStep {
        switch (state, message) {
        case (.idle, .hello(let hello)):
            // The other side's hello can arrive before our transport callback started us.
            let first = start()
            var step = handleHello(hello)
            step.send = first.send + step.send
            return step

        case (.awaitingHello, .hello(let hello)):
            return handleHello(hello)

        case (.awaitingProof(let known), .proof(let signature)):
            return handleProof(signature, knownPeer: known)

        case (.pairAwaitingCommit, .pairCommit(let commitment)):
            peerCommitment = commitment
            state = .pairAwaitingReveal
            return HandshakeStep(send: [.pairNonce(myPairNonce)])

        case (.pairAwaitingNonce, .pairNonce(let nonce)):
            peerPairNonce = nonce
            state = .pairAwaitingUser
            return HandshakeStep(send: [.pairReveal(myPairNonce)], event: confirmationEvent())

        case (.pairAwaitingReveal, .pairReveal(let nonce)):
            guard let commitment = peerCommitment, Self.commitment(for: nonce) == commitment else {
                return fail("The other device did not follow the pairing protocol.")
            }
            peerPairNonce = nonce
            state = .pairAwaitingUser
            return HandshakeStep(event: confirmationEvent())

        case (.pairAwaitingUser, .pairDecision(let accepted)),
             (.pairAwaitingDecision, .pairDecision(let accepted)):
            guard accepted else { return fail("The other device rejected the pairing.") }
            peerAccepted = true
            return advanceIfBothAccepted()

        default:
            return fail("Unexpected message during pairing or authentication.")
        }
    }

    /// The user compared the codes and chose to accept or reject.
    func userDecision(accepted: Bool) -> HandshakeStep {
        guard case .pairAwaitingUser = state else { return HandshakeStep() }
        guard accepted else {
            var step = fail("Pairing was rejected.")
            step.send = [.pairDecision(accepted: false)]
            return step
        }
        iAccepted = true
        state = .pairAwaitingDecision
        var step = advanceIfBothAccepted()
        step.send.insert(.pairDecision(accepted: true), at: 0)
        return step
    }

    private func handleHello(_ hello: PeerHello) -> HandshakeStep {
        guard hello.deviceId != deviceId, hello.nonce.count == 32, hello.publicKey.count == 32 else {
            return fail("Invalid hello from the other device.")
        }
        peer = PeerHello(deviceId: hello.deviceId, name: String(hello.name.prefix(64)), publicKey: hello.publicKey, nonce: hello.nonce)

        if let trusted = lookupTrusted(hello.deviceId) {
            guard trusted.publicKey == hello.publicKey else {
                return fail("The identity of a paired device changed. Remove it and pair again if this is expected.")
            }
            state = .awaitingProof(knownPeer: true)
            return HandshakeStep(send: [.proof(makeProof())])
        }

        guard pairingAllowed else {
            return fail("This device is not paired.")
        }

        switch role {
        case .initiator:
            state = .pairAwaitingNonce
            return HandshakeStep(send: [.pairCommit(Self.commitment(for: myPairNonce))])
        case .responder:
            state = .pairAwaitingCommit
            return HandshakeStep()
        }
    }

    private func handleProof(_ signature: Data, knownPeer: Bool) -> HandshakeStep {
        guard let peer,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: peer.publicKey),
              key.isValidSignature(signature, for: Self.authTranscript(senderNonce: peer.nonce, receiverNonce: myNonce, senderId: peer.deviceId, receiverId: deviceId))
        else {
            return fail("The other device could not prove its identity.")
        }
        state = .finished
        let trusted = TrustedPeer(deviceId: peer.deviceId, name: peer.name, publicKey: peer.publicKey, pairedAt: Date())
        return HandshakeStep(event: .authenticated(trusted, newlyPaired: !knownPeer))
    }

    private func advanceIfBothAccepted() -> HandshakeStep {
        guard iAccepted, peerAccepted else { return HandshakeStep() }
        state = .awaitingProof(knownPeer: false)
        return HandshakeStep(send: [.proof(makeProof())])
    }

    private func confirmationEvent() -> HandshakeEvent? {
        guard let peer, let peerPairNonce else { return nil }
        let code: String
        switch role {
        case .initiator:
            code = Self.pairingCode(initiatorId: deviceId, responderId: peer.deviceId,
                                    initiatorKey: publicKey, responderKey: peer.publicKey,
                                    initiatorNonce: myPairNonce, responderNonce: peerPairNonce)
        case .responder:
            code = Self.pairingCode(initiatorId: peer.deviceId, responderId: deviceId,
                                    initiatorKey: peer.publicKey, responderKey: publicKey,
                                    initiatorNonce: peerPairNonce, responderNonce: myPairNonce)
        }
        return .needsConfirmation(peerName: peer.name, code: code)
    }

    private func makeProof() -> Data {
        guard let peer else { return Data() }
        return sign(Self.authTranscript(senderNonce: myNonce, receiverNonce: peer.nonce, senderId: deviceId, receiverId: peer.deviceId))
    }

    private func fail(_ reason: String) -> HandshakeStep {
        state = .finished
        return HandshakeStep(event: .failed(reason))
    }

    static func commitment(for pairNonce: Data) -> Data {
        Data(SHA256.hash(data: Data("versoline-commit-v1".utf8) + pairNonce))
    }

    static func authTranscript(senderNonce: Data, receiverNonce: Data, senderId: UUID, receiverId: UUID) -> Data {
        var data = Data("versoline-auth-v1".utf8)
        data.append(senderNonce)
        data.append(receiverNonce)
        data.append(contentsOf: withUnsafeBytes(of: senderId.uuid) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: receiverId.uuid) { Array($0) })
        return data
    }

    /// Six digits both screens must show. Depends on both identity keys and both nonces.
    static func pairingCode(
        initiatorId: UUID, responderId: UUID,
        initiatorKey: Data, responderKey: Data,
        initiatorNonce: Data, responderNonce: Data
    ) -> String {
        var data = Data("versoline-sas-v1".utf8)
        data.append(contentsOf: withUnsafeBytes(of: initiatorId.uuid) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: responderId.uuid) { Array($0) })
        data.append(initiatorKey)
        data.append(responderKey)
        data.append(initiatorNonce)
        data.append(responderNonce)
        let digest = Array(SHA256.hash(data: data))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        return String(format: "%06u", value)
    }
}
