import NetworkExtension
import Foundation

/// The real daemon (§5). Persistent background process: brings up the loopback
/// VPN, (eventually) the RSD tunnel + log relay, runs the classifier, dispatches.
///
/// Today it stands up a minimal tunnel and the classifier/dispatcher pipeline.
/// The tunnel transport (idevice/em_proxy) and relay stream are stubbed pending
/// Phase 0 + the Rust core link — see RelayClient and docs/signal.md.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var relay: RelayClient?
    private var classifier: Classifier?
    private var pollTimer: DispatchSourceTimer?

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let config = AppConfig.load()

        // Route only the device-services virtual address into the tunnel (§5);
        // everything else bypasses so webhooks don't loop.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.7.0.2"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "10.7.0.1",
                                           subnetMask: "255.255.255.255")]
        ipv4.excludedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error { completionHandler(error); return }
            self?.startPipeline(config)
            self?.mark(tunnelUp: true)
            completionHandler(nil)
        }
    }

    private func startPipeline(_ config: AppConfig) {
        let cfg = ClassifierConfig(pressMaxMs: config.pressMaxMs,
                                   holdMinMs: config.holdMinMs,
                                   doubleWindowMs: config.doubleWindowMs)
        let classifier = Classifier(cfg)
        let dispatcher = Dispatcher(config: config)
        self.classifier = classifier

        let relay = RelayClient()
        relay.onEvent = { [weak self] event in
            if let g = classifier.onEvent(event.phase, event.tsMs) {
                dispatcher.dispatch(g)
            }
            self?.bumpHeartbeat()
        }
        relay.start()
        self.relay = relay

        // Poll to flush buffered single presses once their double-window closes.
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            let now = Self.monotonicMs()
            if let g = self?.classifier?.poll(now) { dispatcher.dispatch(g) }
        }
        timer.resume()
        pollTimer = timer
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        pollTimer?.cancel(); pollTimer = nil
        relay?.stop(); relay = nil
        mark(tunnelUp: false)
        completionHandler()
    }

    // MARK: - status

    private func mark(tunnelUp: Bool) {
        var s = RelayStatus.load()
        s.tunnelUp = tunnelUp
        s.pairingValid = (SharedStore.pairingFile.map { FileManager.default.fileExists(atPath: $0.path) }) ?? false
        s.lastHeartbeat = Date()
        s.save()
    }

    private func bumpHeartbeat() {
        var s = RelayStatus.load()
        s.lastHeartbeat = Date()
        s.save()
    }

    static func monotonicMs() -> UInt64 {
        UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}
