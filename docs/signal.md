# Phase 0 — Signal discovery (GO/NO-GO)

**Status: ⛔ NOT YET RUN — blocks all tunnel/relay work.**

This is the go/no-go gate (PROJECT.md §3, §10). It requires the physical
iPhone 16 Pro (iOS 26.5) tethered to a computer. It **cannot be done in CI or by
the agent** — it is a hardware capture. Until it produces a confirmed match
predicate below, `core/src/relay.rs` and `tunnel/RelayClient.swift` stay stubs
and the listener emits nothing.

## Procedure

1. Tether the target iPhone to a Mac/PC with a working pairing.
2. Stream the log two ways and capture both:
   - `idevicesyslog`  (plain syslog → `syslog_relay`)
   - `pymobiledevice3 syslog live`  and/or  `pymobiledevice3 os_trace_relay`
3. With each stream recording, perform and timestamp:
   - (a) **short tap** (well below the hold threshold), ×10
   - (b) **hold** until the system action fires, ×10
   - (c) **double tap**, ×10
4. Diff (a) vs (b) vs (c). Look for `backboardd` / IOHID lines around the Action
   Button usage. Identify a line that appears for (a) **distinct** from (b).

## Questions to answer (fill in)

| Question | Answer |
|---|---|
| Distinct sub-threshold (short-tap) line exists? | _TBD_ |
| Which relay carries it — `syslog_relay` or `os_trace_relay`? | _TBD_ |
| Log level — default, or needs an Apple logging-config profile? | _TBD_ |
| Exact match: subsystem / category / message substring | _TBD_ |
| Button usage page / usage code, and down=?/up=? encoding | _TBD_ |
| Is a usable monotonic timestamp present per line? | _TBD_ |

## Deliverable — the match predicate

Once captured, record it here in the shape `relay.rs::MatchPredicate` expects,
and store it as **config** (not a hardcoded constant) so it is patchable per-iOS
without a rebuild (§7.3):

```jsonc
{
  "relay": "syslog",            // or "os_trace"
  "message_contains": "<substring>",
  "subsystem": null,            // os_trace only
  "category": null              // os_trace only
}
```

## If no usable signal is found

**Stop. Do not build on an unverified signal.** Invoke the §11 fallbacks in
priority order and document which applies:

1. Hold-classified-as-press (fire on the hold's `down`).
2. Shortcuts → local-server bridge (still hold-gated).
3. `AVCaptureEventInteraction` true-press, but only during a live capture session.
