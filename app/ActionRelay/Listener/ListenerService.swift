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
    private var watchdog: Timer?
    private var connecting = false

    /// Steady reconnect cadence. ponytail: fixed interval, not exponential
    /// backoff — a loopback-VPN blip (or switching to a real VPN and back) should
    /// recover on the next tick, not after a stretched-out delay. Ceiling: while
    /// the route is genuinely gone each attempt still costs a connect-timeout;
    /// 3s is the gap between attempts, a battery-vs-responsiveness balance.
    private static let watchdogInterval: TimeInterval = 3
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

        // Health watchdog: whenever the relay isn't streaming and we aren't
        // mid-connect, (re)establish. Steady cadence, so recovery is prompt and
        // predictable no matter how long the route was gone.
        watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running, !self.relayUp, !self.connecting else { return }
                self.connect()
            }
        }
    }

    /// A fresh relay wired to the classifier, surfacing connect/close so the
    /// watchdog (and the immediate path below) can react.
    private func makeRelay() -> RelayClient {
        let relay = RelayClient()
        relay.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, let classifier = self.classifier else { return }
                if let g = classifier.onEvent(event.phase, event.tsMs) { self.fire(g) }
            }
        }
        relay.onConnected = { [weak self] in
            Task { @MainActor in
                self?.relayUp = true
                self?.connecting = false   // settled: streaming
            }
        }
        relay.onClosed = { [weak self] msg in
            Task { @MainActor in
                guard let self else { return }
                self.relayUp = false
                self.connecting = false
                if let msg { self.lastError = "relay: \(msg)" }
                // Stream died (VPN flap / sleep). Reconnect now unless stopping;
                // the watchdog is the backstop if this attempt also fails.
                if self.running {
                    self.tunnelUp = false
                    self.connect()
                }
            }
        }
        return relay
    }

    /// One connect attempt: bring up the tunnel, then start the relay over it.
    /// No retry loop here — the watchdog drives retries at a fixed cadence.
    /// `connecting` stays true until the relay reports connected or closed, so a
    /// watchdog tick can't spawn a second tunnel during the handshake window.
    private func connect() {
        guard running, !connecting else { return }
        connecting = true
#if canImport(IDevice)
        Task.detached { [weak self] in
            do {
                let tunnel = TunnelBringup()
                try tunnel.start()
                guard let a = tunnel.adapter, let h = tunnel.handshake else {
                    throw TunnelBringup.TunnelError.message("tunnel handles unavailable")
                }
                let relay = await MainActor.run { () -> RelayClient? in
                    guard self?.running == true else {  // stop() raced us
                        tunnel.stop(); self?.connecting = false; return nil
                    }
                    self?.tunnel?.stop()             // drop the dead tunnel, if any
                    let r = self?.makeRelay() ?? RelayClient()
                    self?.tunnel = tunnel
                    self?.relay = r
                    self?.tunnelUp = true
                    return r
                }
                guard let relay else { return }
                relay.startRSD(adapter: a, handshake: h) // onConnected/onClosed clears `connecting`
            } catch {
                await MainActor.run {
                    self?.tunnelUp = false
                    self?.lastError = "tunnel: \(error)"
                    self?.connecting = false          // let the watchdog retry next tick
                }
            }
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
        running = false        // set first so onClosed/watchdog won't reconnect
        connecting = false
        pollTimer?.invalidate(); pollTimer = nil
        watchdog?.invalidate(); watchdog = nil
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
