import Foundation
import UserNotifications

/// The listener, in-process (no Network Extension). Owns the keepalive, the
/// idevice tunnel + relay, the classifier, and dispatch. Background survival is
/// the silent-audio KeepAlive; the 10.7.0.1 route comes from a loopback VPN
/// (LocalDevVPN/StosVPN) the user enables separately.
@MainActor
final class ListenerService: ObservableObject {
    static let shared = ListenerService()

    @Published private(set) var running = false
    @Published private(set) var tunnelUp = false
    @Published private(set) var relayUp = false
    @Published private(set) var lastEvent: String?
    @Published private(set) var lastError: String?

    private let keepAlive = KeepAlive()
    private var relay: RelayClient?
    private var classifier: Classifier?
    private var dispatcher: Dispatcher?
    private var pollTimer: Timer?
    private var connecting = false
#if canImport(IDevice)
    private var tunnel: TunnelBringup?
#endif

    func start() {
        guard !running else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let config = AppConfig.load()
        classifier = Classifier(ClassifierConfig(
            pressMaxMs: config.pressMaxMs, holdMinMs: config.holdMinMs, doubleWindowMs: config.doubleWindowMs))
        dispatcher = Dispatcher(config: config)

        keepAlive.start()
        running = true
        connect()

        // Flush buffered single presses once their double-window closes.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let classifier = self.classifier else { return }
                if let g = classifier.poll(Self.nowMs()) { self.fire(g) }
            }
        }
    }

    /// A fresh relay wired to the classifier, with auto-reconnect on stream close.
    private func makeRelay() -> RelayClient {
        let relay = RelayClient()
        relay.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, let classifier = self.classifier else { return }
                if let g = classifier.onEvent(event.phase, event.tsMs) { self.fire(g) }
            }
        }
        relay.onConnected = { [weak self] in
            Task { @MainActor in self?.relayUp = true }
        }
        relay.onClosed = { [weak self] msg in
            Task { @MainActor in
                guard let self else { return }
                self.relayUp = false
                if let msg { self.lastError = "relay: \(msg)" }
                // Stream died (VPN flap / sleep). Re-establish unless we're stopping.
                if self.running {
                    self.tunnelUp = false
                    self.connect()
                }
            }
        }
        return relay
    }

    /// Bring up tunnel + relay, retrying with backoff until connected or stopped.
    /// Reused for the first connect and every reconnect after a VPN drop.
    private func connect() {
        guard running, !connecting else { return }
        connecting = true
#if canImport(IDevice)
        Task.detached { [weak self] in
            var delaySec: UInt64 = 1
            while await self?.running == true {
                do {
                    let tunnel = TunnelBringup()
                    try tunnel.start()
                    guard let a = tunnel.adapter, let h = tunnel.handshake else {
                        throw TunnelBringup.TunnelError.message("tunnel handles unavailable")
                    }
                    let relay = await MainActor.run { () -> RelayClient in
                        self?.tunnel?.stop()              // drop the dead tunnel, if any
                        let r = self?.makeRelay() ?? RelayClient()
                        self?.tunnel = tunnel
                        self?.relay = r
                        self?.tunnelUp = true
                        self?.connecting = false
                        return r
                    }
                    relay.startRSD(adapter: a, handshake: h)
                    return
                } catch {
                    await MainActor.run {
                        self?.tunnelUp = false
                        self?.lastError = "tunnel: \(error)"
                    }
                    try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
                    delaySec = min(delaySec * 2, 10) // cap backoff at 10s
                }
            }
            await MainActor.run { self?.connecting = false }
        }
#else
        let relay = makeRelay()
        self.relay = relay
        relay.start()
        connecting = false
#endif
    }

    func stop() {
        guard running else { return }
        running = false        // set first so onClosed won't trigger a reconnect
        connecting = false
        pollTimer?.invalidate(); pollTimer = nil
        relay?.stop(); relay = nil
        classifier = nil
        dispatcher = nil
        keepAlive.stop()
#if canImport(IDevice)
        tunnel?.stop(); tunnel = nil
#endif
        tunnelUp = false
        relayUp = false
    }

    private func fire(_ g: Gesture) {
        guard let dispatcher else { return }
        dispatcher.dispatch(g)
        lastEvent = "\(dispatcher.label(g)) @ \(Date().formatted(date: .omitted, time: .standard))"
    }

    static func nowMs() -> UInt64 { UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }
}
