#if canImport(IDevice)
import Foundation
import IDevice
import Darwin

/// Brings up the idevice RSD **userspace** tunnel to the device's own services
/// (10.7.0.1:49152) from the imported pairing file, then runs a heartbeat
/// keepalive. Hands (adapter, handshake) to the relay. Ported verbatim from
/// StikDebug's proven sequence (docs/integration.md) — compiles in CI; runtime
/// validation needs a Feather-signed device build.
///
/// ponytail: faithful port, trimmed to tunnel + heartbeat (no DDI/debugserver).
/// Ceiling: single tunnel, no auto-reconnect on drop yet (Phase 5).
final class TunnelBringup {
    enum TunnelError: Error, CustomStringConvertible {
        case message(String)
        var description: String { if case let .message(m) = self { return m }; return "tunnel error" }
    }

    private(set) var adapter: OpaquePointer?
    private(set) var handshake: OpaquePointer?
    private var heartbeatClient: OpaquePointer?
    private var heartbeatThread: Thread?
    private var running = false

    private static func consume(_ err: UnsafeMutablePointer<IdeviceFfiError>?, _ fallback: String) -> TunnelError {
        guard let err else { return .message(fallback) }
        let msg = err.pointee.message.map { String(cString: $0) } ?? fallback
        idevice_error_free(err)
        return .message(msg)
    }

    /// Read pairing file → create the tunnel → start heartbeat. Throws on failure.
    /// Run off the main thread (the create call does a network handshake).
    func start() throws {
        // Pairing file (imported via the Pairing tab → Store.pairingFile).
        let path = Store.pairingFile.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw TunnelError.message("No pairing file — import one in the Pairing tab.")
        }
        // Normalize to a canonical binary plist before idevice's Rust `plist`
        // reader sees it. Pasted/AirDropped/emailed XML can carry a BOM or get
        // re-encoded in a way Apple's PropertyListSerialization tolerates but the
        // `plist` crate rejects ("plist error"). Binary plist has no such
        // ambiguity. Idempotent; leaves the file untouched if it can't parse.
        if let data = try? Data(contentsOf: Store.pairingFile),
           let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let bin = try? PropertyListSerialization.data(fromPropertyList: obj, format: .binary, options: 0) {
            try? bin.write(to: Store.pairingFile, options: .atomic)
        }
        var pairing: OpaquePointer?
        if let err = path.withCString({ rp_pairing_file_read($0, &pairing) }) {
            throw Self.consume(err, "read pairing file")
        }
        guard let pairing else { throw TunnelError.message("pairing file handle was nil") }
        defer { rp_pairing_file_free(pairing) }

        // Device-services virtual address (§5).
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(49152).bigEndian
        guard "10.7.0.1".withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            throw TunnelError.message("failed to parse 10.7.0.1")
        }

        var newAdapter: OpaquePointer?
        var newHandshake: OpaquePointer?
        let ffiError = "ActionRelay".withCString { host in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    tunnel_create_rppairing(
                        sa,
                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                        host,
                        pairing,
                        nil,
                        nil,
                        &newAdapter,
                        &newHandshake)
                }
            }
        }
        if let ffiError { throw Self.consume(ffiError, "create tunnel") }
        guard let newAdapter, let newHandshake else {
            if let newHandshake { rsd_handshake_free(newHandshake) }
            if let newAdapter { adapter_free(newAdapter) }
            throw TunnelError.message("tunnel created without valid handles")
        }
        adapter = newAdapter
        handshake = newHandshake
        startHeartbeat()
    }

    private func startHeartbeat() {
        guard let adapter, let handshake else { return }
        var client: OpaquePointer?
        if let err = heartbeat_connect_rsd(adapter, handshake, &client) {
            _ = Self.consume(err, "heartbeat connect"); return
        }
        guard let client else { return }
        heartbeatClient = client
        running = true
        let t = Thread { [weak self] in
            var interval: UInt64 = 15
            while self?.running == true {
                var suggested: UInt64 = 0
                if let err = heartbeat_get_marco(client, interval, &suggested) {
                    idevice_error_free(err)
                    Thread.sleep(forTimeInterval: 1) // brief backoff on timeout/sleepy
                    interval = 15
                    continue
                }
                interval = min(max(suggested, 1), 60)
                if let err = heartbeat_send_polo(client) { idevice_error_free(err) }
            }
        }
        t.stackSize = 256 * 1024
        heartbeatThread = t
        t.start()
    }

    func stop() {
        running = false
        heartbeatThread = nil
        if let heartbeatClient { heartbeat_client_free(heartbeatClient); self.heartbeatClient = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }
}
#endif
