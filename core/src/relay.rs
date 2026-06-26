//! Lockdown log-relay protocol notes — the spec for `core/src/relay.rs`'s real
//! implementation, which lands in Phase 2 once Phase 0 (docs/signal.md) picks a
//! relay. No tunnel transport here yet; that comes from `idevice` over the NE.
//!
//! Both relays are thin lockdown services started over the RSD tunnel:
//!
//! `com.apple.syslog_relay`  (PREFER for bring-up, §7.2)
//!   - Streams plain ASCII syslog lines, newline/NUL-terminated.
//!   - Parse = split on `\0`/`\n`, match the Phase-0 substring. Trivial.
//!
//! `com.apple.os_trace_relay` (use only if the event is unified-log-only)
//!   - Start request is a plist: { Request: "StartActivity", Pid: <optional> }.
//!   - Then length-prefixed binary entries: decode (timestamp, pid, subsystem,
//!     category, message) following pymobiledevice3's os_trace_relay.py.
//!
//! The matched payload is reduced to `(Phase, ts_ms)` and handed to the
//! `classifier`. Filter to backboardd's pid where the relay allows, to cut volume.

use crate::classifier::Phase;

/// A normalized button transition extracted from a relay line/entry.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ButtonEvent {
    pub phase: Phase,
    pub ts_ms: u64,
}

/// Which relay the NE should start. Persisted in config (§7.3) so the choice is
/// patchable per-iOS without a rebuild.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RelayKind {
    Syslog,
    OsTrace,
}

/// Phase-0 deliverable, stored as config not a constant (§7.3). The actual
/// values are filled in from docs/signal.md once captured on the device.
#[derive(Clone, Debug)]
pub struct MatchPredicate {
    pub relay: RelayKind,
    /// Substring (syslog) or message fragment (os_trace) that marks the event.
    pub message_contains: String,
    /// Optional subsystem/category filter for os_trace.
    pub subsystem: Option<String>,
    pub category: Option<String>,
}

// ponytail: no parser implementation until Phase 0 fixes the exact line shape —
// writing one now would be guessing at a format we have not captured.
