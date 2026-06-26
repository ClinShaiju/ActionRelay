import Foundation

/// Streams normalized button events from the lockdown log relay.
///
/// STUB. The real client starts `com.apple.syslog_relay` (or `os_trace_relay`)
/// over the RSD tunnel that `idevice`/`em_proxy` bring up across the NE, then
/// reduces matching lines to `(Phase, ts)` using the Phase-0 predicate
/// (docs/signal.md). None of that can be built until Phase 0 confirms a signal
/// and the Rust core is linked in (PROJECT.md §7.2, §13).
struct ButtonEvent {
    let phase: Phase
    let tsMs: UInt64
}

final class RelayClient {
    /// Called for each parsed button transition. Wired to the classifier by the
    /// provider. No-op today.
    var onEvent: ((ButtonEvent) -> Void)?

    func start() {
        // ponytail: nothing to stream until the tunnel + relay exist. Upgrade
        // path: FFI into core/src/relay.rs once Phase 0 lands. Intentionally
        // does not fake events — a green build must not imply a working signal.
    }

    func stop() {}
}
