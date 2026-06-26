import Foundation
import NetworkExtension
import Combine

/// Installs and toggles the loopback VPN that hosts the listener (§5).
/// The NE keeps running while the VPN is connected; the app only manages it.
@MainActor
final class TunnelManager: ObservableObject {
    @Published var state: NEVPNStatus = .invalid
    @Published var status: RelayStatus = .load()

    private var manager: NETunnelProviderManager?
    private var statusTimer: Timer?

    init() {
        Task { await load() }
        // Mirror the NE's App-Group status into the UI on a slow poll.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.status = .load() }
        }
    }

    func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        let m = managers.first ?? NETunnelProviderManager()
        manager = m
        state = m.connection.status
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.state = m.connection.status }
        }
    }

    /// Create/update the tunnel configuration so iOS will run our NE.
    func install() async throws {
        let m = manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppIDs.tunnelBundleID
        proto.serverAddress = "ActionRelay loopback"
        m.protocolConfiguration = proto
        m.localizedDescription = "ActionRelay"
        m.isEnabled = true
        try await m.saveToPreferences()
        try await m.loadFromPreferences()
        manager = m
    }

    func start() async throws {
        if manager?.protocolConfiguration == nil { try await install() }
        try manager?.connection.startVPNTunnel()
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }
}
