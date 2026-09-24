import Foundation
import MultipeerConnectivity
import AppKit

// MARK: - Local Peer Sync Engine (P2P Wi-Fi & Bluetooth Real-Time Mesh)

final class LocalPeerSyncEngine: NSObject, @unchecked Sendable {

    private let serviceType = "versoline-sync"
    private let myPeerId: MCPeerID

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var connectedPeerCount: Int = 0

    var onPeerEventReceived: (@Sendable (SyncPeerEvent) -> Void)?
    var onConnectedPeersChanged: (@Sendable (Int) -> Void)?

    override init() {
        let deviceName = Host.current().localizedName ?? "Mac"
        self.myPeerId = MCPeerID(displayName: deviceName)
        super.init()

        setupLifecycleObservers()
    }

    func start() {
        guard session == nil else { return }

        let sess = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .optional)
        sess.delegate = self
        self.session = sess

        let adv = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        self.advertiser = adv

        let brow = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        brow.delegate = self
        brow.startBrowsingForPeers()
        self.browser = brow

        log("Local P2P sync engine started (service: \(serviceType))", level: .info)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser = nil

        session?.disconnect()
        session = nil

        connectedPeerCount = 0
        onConnectedPeersChanged?(0)

        log("Local P2P sync engine stopped", level: .info)
    }

    // MARK: - Event Broadcast (Sub-100ms Latency)

    func broadcastEvent(_ event: SyncPeerEvent) {
        guard let session, !session.connectedPeers.isEmpty else { return }

        autoreleasepool {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(event)
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                log("Failed to broadcast P2P sync event: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    private var wasRunningBeforeSleep = false

    private func setupLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.wasRunningBeforeSleep = (self.session != nil)
            if self.wasRunningBeforeSleep {
                self.stop()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.wasRunningBeforeSleep {
                self.wasRunningBeforeSleep = false
                self.start()
            }
        }
    }

    private func log(_ message: String, level: LogLevel = .info) {
        Task { @MainActor in
            AppLogger.shared.log(message, level: level, category: .network)
        }
    }
}

// MARK: - MCSessionDelegate

extension LocalPeerSyncEngine: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peerCount = session.connectedPeers.count
        let peerName = peerID.displayName
        let isNowConnected = (state == .connected)
        let stateName = switch state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .notConnected: "Disconnected"
        @unknown default: "Unknown"
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connectedPeerCount = peerCount
            self.onConnectedPeersChanged?(peerCount)
            self.log("P2P Peer '\(peerName)' state: \(stateName)", level: .debug)

            if isNowConnected {
                self.broadcastEvent(.requestFullSync)
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peerName = peerID.displayName
        autoreleasepool {
            do {
                let decoder = JSONDecoder()
                let event = try decoder.decode(SyncPeerEvent.self, from: data)
                onPeerEventReceived?(event)
            } catch {
                log("Failed to decode P2P message from '\(peerName)': \(error.localizedDescription)", level: .warning)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension LocalPeerSyncEngine: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Automatically accept trusted local connection from Versoline devices
        invitationHandler(true, self.session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        log("Advertiser failed to start: \(error.localizedDescription)", level: .error)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension LocalPeerSyncEngine: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let session else { return }
        // Invite peer to join our session
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log("P2P Peer '\(peerID.displayName)' left local network", level: .debug)
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        log("Browser failed to start: \(error.localizedDescription)", level: .error)
    }
}
