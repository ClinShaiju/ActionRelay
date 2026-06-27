import Foundation
import UserNotifications

/// The listener, in-process (no Network Extension). Owns the keepalive, the
/// idevice tunnel + relay, the classifier, and dispatch. Replaces the old
/// PacketTunnelProvider. Background survival is the silent-audio KeepAlive.
@MainActor
final class ListenerService: ObservableObject {
    static let shared = ListenerService()

    @Published private(set) var running = false
    @Published private(set) var lastEvent: String?
    @Published private(set) var lastError: String?

    private let keepAlive = KeepAlive()
    private var relay: RelayClient?
    private var classifier: Classifier?
    private var pollTimer: Timer?
#if canImport(IDevice)
    private var tunnel: TunnelBringup?
#endif

    func start() {
        guard !running else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let config = AppConfig.load()
        let classifier = Classifier(ClassifierConfig(
            pressMaxMs: config.pressMaxMs, holdMinMs: config.holdMinMs, doubleWindowMs: config.doubleWindowMs))
        let dispatcher = Dispatcher(config: config)
        self.classifier = classifier

        keepAlive.start()

        let relay = RelayClient()
        relay.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let g = classifier.onEvent(event.phase, event.tsMs) { self.fire(g, dispatcher) }
            }
        }
        self.relay = relay
        startRelay(relay)

        // Flush buffered single presses once their double-window closes.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let classifier = self.classifier else { return }
                if let g = classifier.poll(Self.nowMs()) { self.fire(g, dispatcher) }
            }
        }
        running = true
    }

    /// Bring up the idevice tunnel off the main thread, then start the relay over
    /// it. Without IDevice linked, the relay stub runs (emits nothing).
    private func startRelay(_ relay: RelayClient) {
#if canImport(IDevice)
        Task.detached { [weak self] in
            let tunnel = TunnelBringup()
            do {
                try tunnel.start()
                guard let a = tunnel.adapter, let h = tunnel.handshake else {
                    throw TunnelBringup.TunnelError.message("tunnel handles unavailable")
                }
                relay.startRSD(adapter: a, handshake: h)
                await MainActor.run { self?.tunnel = tunnel }
            } catch {
                await MainActor.run { self?.lastError = "tunnel: \(error)" }
            }
        }
#else
        relay.start()
#endif
    }

    func stop() {
        guard running else { return }
        pollTimer?.invalidate(); pollTimer = nil
        relay?.stop(); relay = nil
        classifier = nil
        keepAlive.stop()
#if canImport(IDevice)
        tunnel?.stop(); tunnel = nil
#endif
        running = false
    }

    private func fire(_ g: Gesture, _ dispatcher: Dispatcher) {
        dispatcher.dispatch(g)
        lastEvent = "\(dispatcher.label(g)) @ \(Date().formatted(date: .omitted, time: .standard))"
    }

    static func nowMs() -> UInt64 { UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }
}
