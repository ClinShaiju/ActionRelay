# Phase 0 — Signal discovery (GO/NO-GO)

**Status: ✅ GO — confirmed on iPhone 16 Pro (iPhone17,1), iOS 26.5 (build 23F77), 2026-06-26.**

The Action Button emits a clean, distinct, sub-threshold down/up pair in plain
syslog at default log level. All four Phase-0 questions answered. Build proceeds.

## The match predicate (store as config, §7.3)

```jsonc
{
  "relay": "syslog",                              // com.apple.syslog_relay, plain ASCII
  "process": "backboardd",
  "subsystem": "backboardd",
  "level": "NOTICE",                              // default level — NO logging profile needed
  "message_contains": "Action page:0xB usage:0x2D",
  "phase": { "down": "downEvent:1", "up": "downEvent:0" }
}
```

The two lines, verbatim:

```
backboardd{backboardd}[70] <NOTICE>: Action page:0xB usage:0x2D downEvent:1 down
backboardd{backboardd}[70] <NOTICE>: Action page:0xB usage:0x2D downEvent:0 up
```

Parse: match the substring `Action page:0xB usage:0x2D`; `downEvent:1` → DOWN,
`downEvent:0` → UP; timestamp = the syslog line's leading µs timestamp (monotonic
enough; fall back to local receipt time if needed). Feed `(phase, ts_ms)` to the
classifier (`core/src/classifier.rs`).

## Q&A (§3)

| Question | Answer |
|---|---|
| Distinct sub-threshold (short-tap) line? | **Yes.** DOWN logs at the instant of physical press, before the hold gesture recognizer decides. Down and up are separate lines. |
| Which relay carries it? | **`syslog_relay`** — plain ASCII, newline-terminated. The easy path; no os_trace_relay decode needed. |
| Log level / profile needed? | **Default `<NOTICE>`.** No Apple logging-config profile required. |
| Exact match signature | Process `backboardd`, subsystem `backboardd`, message `Action page:0xB usage:0x2D downEvent:[1|0]`. |

`page:0xB usage:0x2D` is how backboardd reports the Action Button; it labels the
event "Action" itself. Confirmed by corroborating lines on every press:
`kernel{AppleM68Buttons}: ButtonStates ... Index: 3 State: 1/0`,
`kernel{AppleSMC}: HID buttonIndex=13 buttonState=1/0`,
`SpringBoard: button down/up (sq160)`,
`SpringBoard: Action Button press event delivery latency analytics`.

## Empirical validation of classifier thresholds

Captured sequence — 2 taps, 1 hold, 1 double — with measured down→up dt:

| Gesture | dt (down→up) | Threshold (press_max 350 / hold_min 600) | Verdict |
|---|---|---|---|
| tap 1 | 181 ms | < 350 | press ✓ |
| tap 2 | 188 ms | < 350 | press ✓ |
| **hold** | **1038 ms** | ≥ 600 | hold ✓ |
| double ① | 154 ms | < 350 | press |
| double ② | 154 ms; 2nd down 151 ms after 1st up | gap ≤ 350 | **double ✓** |

The shipped defaults (`press_max_ms 350`, `hold_min_ms 600`, `double_window_ms 350`)
classify this real-device data with zero errors. Tunables remain in config.

## Capture method (reproducible)

Host: Windows 11, USB, no jailbreak. Tooling: `pymobiledevice3` (pip).

1. Apple Mobile Device Service (classic iTunes 64-bit, **not** the MS Store
   "Apple Devices" app) provides usbmuxd:27015.
2. **Critical Windows gotcha:** force UTF-8 or pymobiledevice3 crashes mid-stream.
   Apple log lines contain ` ` (narrow no-break space) which the default
   cp1252 stdout codec cannot encode → `UnicodeEncodeError` kills `syslog` after
   the backlog flush (~2 s). Always:
   ```sh
   PYTHONUTF8=1 PYTHONIOENCODING=utf-8 \
     py -3.12 -m pymobiledevice3 syslog live \
     | grep --line-buffered -E "Action page:0xB usage:0x2D"
   ```
3. Disable Auto-Lock on the phone during capture (syslog refuses while locked).

## On-device implication

The NE starts `com.apple.syslog_relay` over the RSD tunnel, line-parses the
stream, matches the predicate above, and drives the classifier — exactly the
Phase-2 plan, on the simplest (syslog, no DDI) path. Signal foundation is solid.
