import Foundation
import MultipeerConnectivity
import AppKit

// Transport for nearby sync. Everything that decides *who may talk* lives in `PeerHandshake`
// (mutual authentication and pairing, unit-tested without a network). This class only moves bytes:
//
// - The MultipeerConnectivity session requires encryption.
// - A connection from an unknown device is only accepted while the user has "Pair New Device" open.
// - No sync event is read from, or sent to, a peer until its handshake has finished.
// - Unauthenticated connections are dropped after a short timeout.
//
// All mutable state is touched only on `queue`, a private serial queue. MultipeerConnectivity calls the
// delegate methods on its own threads, so every delegate method just hops onto `queue`.

final class LocalPeerSyncEngine: NSObject, @unchecked Sendable {

    struct Handlers: Sendable {
        var onEvent: @Sendable (SyncPeerEvent) -> Void = { _ in }
        /// A peer finished authentication. `newlyPaired` is true for a first-time pairing.
        var onAuthenticated: @Sendable (TrustedPeer, _ newlyPaired: Bool) -> Void = { _, _ in }
        var onAuthenticatedCountChanged: @Sendable (Int) -> Void = { _ in }
        /// Pairing: both screens must show this code; call `confirmPairing` with the user's answer.
        var onConfirmation: @Sendable (_ peerName: String, _ code: String) -> Void = { _, _ in }
        /// Pairing ended without success (rejected, mismatch, timeout, wrong state).
        var onPairingFailed: @Sendable (String) -> Void = { _ in }
        var onLog: @Sendable (String, LogLevel) -> Void = { _, _ in }
    }

    // Only ever touched on `queue`.
    private final class Link: @unchecked Sendable {
        let handshake: PeerHandshake
        let role: PeerHandshake.Role
        let wasPairing: Bool
        var authenticated: TrustedPeer?
        var awaitingUser = false
        var deadline = UUID()

        init(handshake: PeerHandshake, role: PeerHandshake.Role, wasPairing: Bool) {
            self.handshake = handshake
            self.role = role
            self.wasPairing = wasPairing
        }
    }

    /// Largest message accepted from a peer.
    static let maxMessageBytes = 2 * 1024 * 1024
    private static let serviceType = "versoline-sync"
    private static let knownPeerTimeout: TimeInterval = 20
    private static let pairingTimeout: TimeInterval = 120

    private let queue = DispatchQueue(label: "\(AppInfo.identifier).peer-sync")
    private let trustStore: PeerTrustStore

    // Touched only on `queue`.
    private var handlers = Handlers()
    private var identity: LocalPeerIdentity?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var pairingMode = false
    private var links: [MCPeerID: Link] = [:]
    private var invited: Set<MCPeerID> = []
    private var wasRunningBeforeSleep = false
    private var observers: [NSObjectProtocol] = []

    init(trustStore: PeerTrustStore) {
        self.trustStore = trustStore
        super.init()
        setupLifecycleObservers()
    }

    deinit {
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    func setHandlers(_ handlers: Handlers) {
        queue.async { self.handlers = handlers }
    }

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    func setPairingMode(_ enabled: Bool) {
        queue.async {
            self.pairingMode = enabled
            if !enabled {
                // Drop half-finished pairings; authenticated links stay.
                for (peer, link) in self.links where link.authenticated == nil && link.wasPairing {
                    self.drop(peer, reason: nil)
                }
            }
        }
    }

    func confirmPairing(accepted: Bool) {
        queue.async {
            guard let (peer, link) = self.links.first(where: { $0.value.awaitingUser }) else { return }
            link.awaitingUser = false
            self.process(link.handshake.userDecision(accepted: accepted), from: peer)
        }
    }

    /// Sends an event to every authenticated peer.
    func broadcast(_ event: SyncPeerEvent) {
        queue.async {
            guard let session = self.session else { return }
            let targets = self.links.filter { $0.value.authenticated != nil }.map(\.key)
            guard !targets.isEmpty else { return }
            self.send(.event(event), to: targets, session: session)
        }
    }

    /// Sends events to one authenticated peer; used for the snapshot right after authentication.
    func send(_ events: [SyncPeerEvent], to deviceId: UUID) {
        queue.async {
            guard let session = self.session,
                  let peer = self.links.first(where: { $0.value.authenticated?.deviceId == deviceId })?.key else { return }
            for event in events { self.send(.event(event), to: [peer], session: session) }
        }
    }

    private func startOnQueue() {
        guard session == nil, let identity = trustStore.identity() else { return }
        self.identity = identity

        let peerId = MCPeerID(displayName: String(identity.name.prefix(60)))
        let sess = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        sess.delegate = self
        let adv = MCNearbyServiceAdvertiser(peer: peerId, discoveryInfo: ["id": identity.deviceId.uuidString], serviceType: Self.serviceType)
        adv.delegate = self
        let brow = MCNearbyServiceBrowser(peer: peerId, serviceType: Self.serviceType)
        brow.delegate = self

        session = sess
        advertiser = adv
        browser = brow
        adv.startAdvertisingPeer()
        brow.startBrowsingForPeers()
        log("Nearby sync started", .info)
    }

    private func stopOnQueue() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        links.removeAll()
        invited.removeAll()
        pairingMode = false
        handlers.onAuthenticatedCountChanged(0)
        log("Nearby sync stopped", .info)
    }

    private func setupLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            guard let engine = self else { return }
            engine.queue.async {
                engine.wasRunningBeforeSleep = engine.session != nil
                if engine.wasRunningBeforeSleep { engine.stopOnQueue() }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let engine = self else { return }
            engine.queue.async {
                guard engine.wasRunningBeforeSleep else { return }
                engine.wasRunningBeforeSleep = false
                engine.startOnQueue()
            }
        })
    }

    private func makeLink(for peer: MCPeerID) -> Link? {
        guard let identity else { return nil }
        let role: PeerHandshake.Role = invited.contains(peer) ? .initiator : .responder
        let store = trustStore
        let handshake = PeerHandshake(
            deviceId: identity.deviceId, name: identity.name, publicKey: identity.publicKey,
            sign: { identity.sign($0) }, trusted: { store.peer(for: $0) },
            pairingAllowed: pairingMode, role: role)
        let link = Link(handshake: handshake, role: role, wasPairing: pairingMode)
        links[peer] = link
        scheduleDeadline(for: peer, link: link, seconds: pairingMode ? Self.pairingTimeout : Self.knownPeerTimeout)
        return link
    }

    private func scheduleDeadline(for peer: MCPeerID, link: Link, seconds: TimeInterval) {
        let token = UUID()
        link.deadline = token
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, let current = self.links[peer], current === link,
                  link.deadline == token, link.authenticated == nil else { return }
            self.drop(peer, reason: link.wasPairing ? "Pairing timed out." : nil)
        }
    }

    private func process(_ step: HandshakeStep, from peer: MCPeerID) {
        guard let link = links[peer] else { return }
        if let session {
            for message in step.send { send(.handshake(message), to: [peer], session: session) }
        }
        guard let event = step.event else { return }

        switch event {
        case .needsConfirmation(let name, let code):
            link.awaitingUser = true
            handlers.onConfirmation(name, code)

        case .authenticated(let trusted, let newlyPaired):
            if newlyPaired, !trustStore.trust(trusted) {
                drop(peer, reason: "The pairing could not be saved on this Mac.")
                return
            }
            link.authenticated = trusted
            link.deadline = UUID()
            log("Authenticated nearby device '\(trusted.name)'", .info)
            handlers.onAuthenticatedCountChanged(authenticatedCount())
            handlers.onAuthenticated(trusted, newlyPaired)

        case .failed(let reason):
            log("Nearby device refused: \(reason)", .warning)
            drop(peer, reason: link.wasPairing || link.awaitingUser ? reason : nil)
        }
    }

    private func authenticatedCount() -> Int {
        links.values.filter { $0.authenticated != nil }.count
    }

    private func drop(_ peer: MCPeerID, reason: String?) {
        let wasAuthenticated = links[peer]?.authenticated != nil
        links[peer] = nil
        invited.remove(peer)
        session?.cancelConnectPeer(peer)
        if let reason { handlers.onPairingFailed(reason) }
        if wasAuthenticated { handlers.onAuthenticatedCountChanged(authenticatedCount()) }
    }

    private func send(_ message: SyncWireMessage, to peers: [MCPeerID], session: MCSession) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            log("Failed to send to nearby device: \(error.localizedDescription)", .warning)
        }
    }

    private func handle(data: Data, from peer: MCPeerID) {
        guard data.count <= Self.maxMessageBytes,
              let message = try? JSONDecoder().decode(SyncWireMessage.self, from: data) else {
            log("Dropped an oversized or malformed message from a nearby device", .warning)
            return
        }
        guard let link = links[peer] ?? makeLink(for: peer) else { return }

        switch message {
        case .handshake(let handshakeMessage):
            process(link.handshake.receive(handshakeMessage), from: peer)

        case .event(let event):
            // Nothing is accepted before authentication, and every event is range-checked.
            guard link.authenticated != nil else {
                log("Ignored a sync event from an unauthenticated device", .warning)
                return
            }
            guard SyncEventValidator.isAcceptable(event) else {
                log("Ignored an invalid sync event from a paired device", .warning)
                return
            }
            handlers.onEvent(event)
        }
    }

    private func log(_ message: String, _ level: LogLevel) {
        handlers.onLog(message, level)
    }
}

extension LocalPeerSyncEngine: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        queue.async {
            switch state {
            case .connected:
                guard self.links[peerID] == nil, let link = self.makeLink(for: peerID) else { return }
                self.process(link.handshake.start(), from: peerID)
            case .notConnected:
                let wasAuthenticated = self.links[peerID]?.authenticated != nil
                self.links[peerID] = nil
                self.invited.remove(peerID)
                if wasAuthenticated { self.handlers.onAuthenticatedCountChanged(self.authenticatedCount()) }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        queue.async { self.handle(data: data, from: peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension LocalPeerSyncEngine: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // The context is only a hint about who is calling; real identity is proven in the handshake.
        let claimedId = context.flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:))
        nonisolated(unsafe) let reply = invitationHandler
        queue.async {
            let known = claimedId.map { self.trustStore.peer(for: $0) != nil } ?? false
            guard known || self.pairingMode else {
                reply(false, nil)
                return
            }
            reply(true, self.session)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        queue.async { self.log("Nearby advertising failed: \(message)", .error) }
    }
}

extension LocalPeerSyncEngine: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        nonisolated(unsafe) let browser = browser
        queue.async {
            guard let identity = self.identity, let session = self.session,
                  let theirIdString = info?["id"], let theirId = UUID(uuidString: theirIdString),
                  theirId != identity.deviceId else { return }

            let known = self.trustStore.peer(for: theirId) != nil
            guard known || self.pairingMode else { return }
            // Exactly one side invites, otherwise both would connect to each other at once.
            guard identity.deviceId.uuidString < theirIdString else { return }
            guard self.links[peerID] == nil, !self.invited.contains(peerID) else { return }

            self.invited.insert(peerID)
            browser.invitePeer(peerID, to: session, withContext: Data(identity.deviceId.uuidString.utf8), timeout: 15)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        queue.async { self.invited.remove(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let message = error.localizedDescription
        queue.async { self.log("Nearby browsing failed: \(message)", .error) }
    }
}

// MCPeerID is immutable once created, so sharing it between the delegate threads and `queue` is safe.
extension MCPeerID: @retroactive @unchecked Sendable {}
