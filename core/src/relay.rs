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

/// Phase-0 deliverable, stored as config not a constant (§7.3).
/// CONFIRMED on iPhone 16 Pro / iOS 26.5 — see docs/signal.md.
#[derive(Clone, Debug)]
pub struct MatchPredicate {
    pub relay: RelayKind,
    /// Substring (syslog) or message fragment (os_trace) that marks the event.
    pub message_contains: String,
    /// Optional subsystem/category filter for os_trace.
    pub subsystem: Option<String>,
    pub category: Option<String>,
}

impl Default for MatchPredicate {
    /// The Phase-0 result: backboardd logs the Action Button as a NOTICE-level
    /// syslog line `Action page:0xB usage:0x2D downEvent:1 down` / `downEvent:0 up`.
    fn default() -> Self {
        MatchPredicate {
            relay: RelayKind::Syslog,
            message_contains: "Action page:0xB usage:0x2D".to_string(),
            subsystem: Some("backboardd".to_string()),
            category: None,
        }
    }
}

/// Parse a matched syslog line into a ButtonEvent. Returns None for non-matching
/// lines. Phase is read from `downEvent:1` (down) / `downEvent:0` (up). The
/// caller supplies the timestamp (line ts or local receipt) in ms.
pub fn parse_syslog_line(line: &str, ts_ms: u64) -> Option<ButtonEvent> {
    if !line.contains("Action page:0xB usage:0x2D") {
        return None;
    }
    let phase = if line.contains("downEvent:1") {
        Phase::Down
    } else if line.contains("downEvent:0") {
        Phase::Up
    } else {
        return None;
    };
    Some(ButtonEvent { phase, ts_ms })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_real_device_lines() {
        let down = "backboardd{backboardd}[70] <NOTICE>: Action page:0xB usage:0x2D downEvent:1 down";
        let up = "backboardd{backboardd}[70] <NOTICE>: Action page:0xB usage:0x2D downEvent:0 up";
        assert_eq!(parse_syslog_line(down, 100).unwrap().phase, Phase::Down);
        assert_eq!(parse_syslog_line(up, 200).unwrap().phase, Phase::Up);
        assert!(parse_syslog_line("unrelated locationd spam", 0).is_none());
    }
}
