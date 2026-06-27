import Foundation
#if canImport(IDevice)
import IDevice
#endif

/// Streams Action Button down/up events from the device's own `syslog_relay`,
/// carried over the idevice RSD userspace tunnel (docs/integration.md). The
/// Phase-0 predicate (docs/signal.md) is matched here.
struct ButtonEvent {
    let phase: Phase
    let tsMs: UInt64
}

final class RelayClient {
    var onEvent: ((ButtonEvent) -> Void)?
    private var running = false

    /// Pure parse of one syslog line → ButtonEvent. Mirrors
    /// `core/src/relay.rs::parse_syslog_line`; no FFI, fully testable.
    static func parse(_ line: String, tsMs: UInt64) -> ButtonEvent? {
        guard line.contains("Action page:0xB usage:0x2D") else { return nil }
        if line.contains("downEvent:1") { return ButtonEvent(phase: .down, tsMs: tsMs) }
        if line.contains("downEvent:0") { return ButtonEvent(phase: .up, tsMs: tsMs) }
        return nil
    }

    private static func nowMs() -> UInt64 {
        UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

#if canImport(IDevice)
    private var client: OpaquePointer?
    private var thread: Thread?

    /// Start the relay over an already-established RSD tunnel. `adapter` and
    /// `handshake` come from the tunnel bring-up (see integration.md). Verified
    /// idevice FFI: connect_rsd → next loop → free.
    func startRSD(adapter: OpaquePointer, handshake: OpaquePointer) {
        running = true
        let t = Thread { [weak self] in
            guard let self else { return }
            var client: OpaquePointer?
            if let err = syslog_relay_connect_rsd(adapter, handshake, &client) {
                idevice_error_free(err); return
            }
            self.client = client
            while self.running {
                var raw: UnsafeMutablePointer<CChar>?
                if let err = syslog_relay_next(client, &raw) { idevice_error_free(err); break }
                guard let raw else { continue }
                let line = String(cString: raw)
                idevice_string_free(raw)
                if let event = RelayClient.parse(line, tsMs: RelayClient.nowMs()) {
                    self.onEvent?(event)
                }
            }
            if let client { syslog_relay_client_free(client) }
        }
        t.stackSize = 512 * 1024
        thread = t
        t.start()
    }
#endif

    /// Fallback used until the idevice tunnel is wired. Emits nothing — a green
    /// build must never imply a working signal (docs/integration.md).
    func start() {
        // ponytail: no-op stub. Real path is startRSD(adapter:handshake:),
        // active once IDevice.xcframework is linked + the tunnel is brought up.
    }

    func stop() {
        running = false
#if canImport(IDevice)
        thread = nil
        client = nil
#endif
    }
}
