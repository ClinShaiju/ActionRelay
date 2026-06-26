# ActionRelay — On-Device, Untethered iPhone Action Button Press Detector

> Working name. Rename freely (`pressbridge`, `actiond`, etc.).
> Hand-off spec for Claude Code. Read this whole file before writing code. Build in the phase order given — **Phase 0 is a go/no-go gate and must pass before any app code is written.**

---

## 1. One-paragraph summary

iOS only delivers the Action Button to third-party code as a *hold*, and only inside a live camera-capture session. The raw button **down/up** HID transitions, however, are logged by `backboardd` the instant the button moves — before the hold-threshold gesture recognizer decides whether to fire the assigned action. Those log entries are readable off-device over USB via the `os_trace_relay` / `syslog_relay` lockdown services with nothing but a pairing record. This project moves that listener **onto the device**: it stands up a SideStore/StikDebug-style on-device loopback tunnel to the phone's *own* lockdownd (pairing file + NetworkExtension VPN), starts the log relay over that tunnel, filters for the Action Button event, classifies single-press vs hold vs double-press from the down/up timing, and dispatches a user-configured action. No jailbreak. No tether. Works in the iOS 17.4–18.x / 26 range where TrollStore is dead. Signed and installed with Feather using the user's paid (distribution) certificate.

---

## 2. Why this is possible (and the exact wall it threads)

- **Reading another process's log on-device is sandbox-blocked.** `OSLogStore` only exposes `.currentProcessIdentifier` to sandboxed apps; the system store needs `com.apple.logging.local-store`, an entitlement no legitimately-issued cert can carry. So we do **not** read the log via OSLogStore.
- **Instead we use the lockdown relay**, the same channel `idevicesyslog` uses. On the host side it needs only a **pairing record** — no Apple entitlement, no Developer Disk Image.
- **The pairing record is obtainable and portable.** Generated once on a computer, it lives on-device afterward. This is exactly what SideStore/StikDebug rely on.
- **iOS 17.4+ hides lockdown services behind a RemoteServiceDiscovery (RSD) tunnel.** That tunnel is what the NetworkExtension loopback VPN provides. The `com.apple.developer.networking.networkextension` (packet-tunnel-provider) capability is a **normal paid-account capability** — this is the one place the user's distribution cert genuinely unlocks something.
- **Net:** trust = pairing file; transport = NE loopback VPN; data = `os_trace_relay`. All three are reachable without a jailbreak on modern iOS.

---

## 3. The single biggest risk — gate it in Phase 0

**We do not yet know, with certainty, that a sub-threshold Action Button press emits a distinct, parseable `backboardd` log line at a capturable log level.** The architecture is sound and the raw IOKit HID down/up *should* log independently of the hold gesture, but this must be **empirically confirmed on the target device/iOS before building the app.** Phase 0 exists solely to answer:

1. Does pressing the Action Button (short tap, below the hold threshold) produce a log line distinct from a hold?
2. Which relay carries it — `syslog_relay` (plain ASCII, easy) or `os_trace_relay` (structured unified-log, captures more)?
3. At what log level — default, or does it require an Apple-provided logging config profile to raise `backboardd`/HID subsystem verbosity?
4. What is the exact, stable matchable signature (subsystem, category, message substring, button usage page/usage code)?

If Phase 0 finds no usable sub-threshold signal at any capturable level, **stop** and fall back (see §11). Do not build on an unverified signal.

---

## 4. Target & constraints

- **Confirmed device:** **iPhone 16 Pro (A18 Pro, TXM-capable), iOS 26.5**, 128 GB. Has the Action Button. This is *the* build to develop and test against — pin tooling to it.
- **iOS range covered by the tooling:** the `idevice`/LocalDevVPN loopback stack runs 17.4 → 18.x → 26.x. 26.5 is recent, and these tools chase iOS point releases, so use the **latest** `idevice` / StikDebug build and treat the idevice Discord compatibility channel as source of truth for whether 26.5's tunnel is currently healthy.
- **Signing/install:** Feather, on-device, with the user's **paid Apple Developer (distribution) certificate** + a `.mobileprovision` that includes the Network Extensions capability. Free accounts cannot provision packet-tunnel-provider — paid is required here.
- **No jailbreak, no TrollStore** (patched on 26.x).
- **Runtime requirement:** Wi-Fi **or** Airplane Mode on, and the loopback VPN active, at all times the listener runs. Inherent to the LocalDevVPN approach; surface it clearly in the UI.

> **Why iOS 26's JIT breakage does NOT threaten this project.** You'll see chatter that "iOS 26 broke JIT again" (true — SideStore's docs note 26.6/27 only work with a few apps). That breakage is specifically the **debugserver + DDI mount + TXM** path, which iOS 26's Trusted Execution Monitor keeps disrupting. **ActionRelay uses none of that.** We don't mount the Developer Disk Image, don't run debugserver, and never make memory executable — we only bring up the **RSD tunnel** (the stable part that lets StikDebug even *attempt* JIT) and start a read-only **lockdown log relay** over it. So the fragile, TXM-sensitive machinery that breaks on every 26.x point release is exactly the machinery we avoid. Our foundation on 26.5 is firmer than StikDebug's headline feature.

---

## 5. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  ActionRelay.app  (SwiftUI, foreground)                       │
│   • Pairing-file import + validation                          │
│   • Action configuration (notification / webhook / shortcut)  │
│   • Status dashboard (tunnel up?, last event, heartbeat)      │
│   • Starts/stops the NE tunnel                                │
└───────────────┬──────────────────────────────────────────────┘
                │  shared App Group container
                │  (pairing file, config plist, event log)
┌───────────────▼──────────────────────────────────────────────┐
│  PacketTunnel  (NEPacketTunnelProvider extension)             │
│  ── persistent background process, this is the real daemon ── │
│                                                              │
│   [Rust core via FFI]                                        │
│     • minimuxer / em_proxy : on-device usbmux + RSD tunnel    │
│     • idevice              : lockdown, RSD, service start     │
│     • heartbeat            : keep pairing/tunnel alive        │
│     • relay client         : os_trace_relay OR syslog_relay   │
│                                                              │
│   [Swift]                                                    │
│     • line/stream parser   → ButtonEvent {phase, ts}         │
│     • classifier           → Press | Hold | Double           │
│     • dispatcher           → notification | webhook | …       │
└──────────────────────────────────────────────────────────────┘
```

**Why the listener lives in the NE, not the app:** the NEPacketTunnelProvider gets persistent background execution. A plain local HTTP server in the main app would be suspended within seconds of backgrounding. The tunnel *and* the relay client *and* detection run inside the NE so the watcher is always-on whenever the VPN is connected.

**NE constraints to respect (do not ignore):**
- Memory budget is tight (historically ~15–50 MB for tunnel providers). Keep the Rust core lean; stream-parse, never buffer the whole log.
- No `UIApplication`, so the NE **cannot** `openURL`. That limits "run a Shortcut" / "launch app" dispatch from background (see §8).
- The NE *is* the network stack. Route only `10.7.0.1` (the device-services virtual address) into the tunnel; everything else (e.g. webhook destinations) must bypass it via `includedRoutes`/`excludedRoutes`, or you create a loop.

---

## 6. Dependencies & references

| Purpose | Source | Notes |
|---|---|---|
| On-device lockdown/RSD/services | `jkcoxson/idevice` (Rust) | Core lib StikDebug builds on. Verify it exposes (or add) an `os_trace_relay`/`syslog_relay` client. |
| On-device usbmux + NE proxy | `SideStore/minimuxer`, `SideStore/em_proxy` (Rust) | The tunnel transport. |
| Reference architecture | `StephenDev0/StikDebug` | Pairing + VPN + service start, already working on 17.4→26. **AGPL-3.0 — copyleft; if you reuse code, ActionRelay inherits AGPL.** Decide license posture early. |
| Relay protocol reference | `pymobiledevice3` (Python) | `os_trace_relay.py` / `syslog_relay` define the wire format. Host-side; use as protocol spec + Phase 0 tooling. |
| Pairing file generation | `idevice_pair` (idevice fork) | One-time, on a computer. **Use `idevice_pair`, not iLoader, on iOS 26.x** (iLoader lagged 26.4+). Windows needs Apple iTunes drivers (not the MS Store build). |

**Action item for Claude Code:** before Phase 2, inspect `idevice` for an existing syslog/os_trace client. If absent, implement one in the Rust core following the `pymobiledevice3` protocol (it's a thin lockdown service: start `com.apple.os_trace_relay`, send the start-request, stream framed entries).

---

## 7. Protocol notes

### 7.1 Tunnel bring-up (idevice/minimuxer)
1. Load pairing record from the App Group container.
2. Establish the RSD tunnel over the NE (em_proxy provides the loopback; services appear at `10.7.0.1`).
3. Run a `lockdownd` handshake / `GetValue` as a liveness check before starting any relay.
4. Start the heartbeat and keep it running for the life of the tunnel.

### 7.2 Relay client
- **Prefer `syslog_relay` first** for Phase 2 bring-up: it streams **plain ASCII syslog lines, newline/NUL-terminated** — trivial to parse, matches what `idevicesyslog` shows. If Phase 0 proved the Action Button event appears here, ship this.
- **Use `os_trace_relay` if** Phase 0 showed the event only exists in the structured unified log. Heavier: it streams length-prefixed binary entries you must decode (timestamp, pid, subsystem, category, message). Decode following `pymobiledevice3`.
- Either way: **no DDI mount required** (unlike StikDebug's debugserver path — this is strictly simpler than JIT).
- Apply a process filter to `backboardd`'s pid if the relay supports it, to cut volume.

### 7.3 Event shape (to be finalized in Phase 0)
Expect something like a HID usage event for the Action Button's usage page/code with a phase (down=1/up=0) and a timestamp. Phase 0 produces the exact `match predicate`. Store it as config, not a hardcoded constant, so it can be patched per-iOS without a rebuild.

---

## 8. Event classification & dispatch

### 8.1 Classifier (in the NE)
Maintain a tiny state machine over `(phase, monotonic_ts)`:

```
on DOWN(t0): remember t0
on UP(t1):
    dt = t1 - t0
    if dt < PRESS_MAX (≈350 ms):           candidate = .press
    elif dt >= HOLD_MIN (≈600 ms):         candidate = .hold
    else:                                  candidate = .ambiguous (treat as press)

    if a previous .press ended within DOUBLE_WINDOW (≈350 ms):
        emit .double  (and cancel the buffered single)
    else:
        buffer .press for DOUBLE_WINDOW, then emit if not superseded
```

Tunables live in config. Emit on `UP` for responsiveness. Keep all timestamps monotonic (relay timestamps if reliable, else local receipt time).

### 8.2 Critical UX rule — avoid double-firing
Tell the user (and enforce in onboarding) to set the system **Action Button → "No Action"** in Settings. Then a real hold won't trigger a competing system action, and ActionRelay's reader is the sole responder to presses. This is what makes single-press behavior feel native.

### 8.3 Dispatch targets
- **Local notification** — `UNUserNotificationCenter.add(...)` works from an app extension. Primary, always-available output.
- **Webhook** — `URLSession` POST to a user URL. Must bypass the tunnel (exclude its route). Good for Home Assistant, IFTTT, a home server, your OCI VPS, etc.
- **Run a Shortcut / launch an app** — **not directly possible from the NE** (no `openURL`). Options, in order of preference:
  1. Notification with a custom action button the user taps (cheap, reliable, but one tap).
  2. Wake the main app via a notification → the app, on foreground, performs the `shortcuts://run-shortcut?name=…` open.
  3. Webhook → a companion (Pi / server / Pushcut) that round-trips back. Most flexible, needs infra.
  Document the limitation plainly; don't pretend background Shortcut-launch is free.

---

## 9. Entitlements & Feather signing

### 9.1 App + extension entitlements
Main app and the PacketTunnel extension share an App Group:

```xml
<!-- App Group (both targets) -->
<key>com.apple.security.application-groups</key>
<array><string>group.<TEAMID>.com.you.actionrelay</string></array>

<!-- Network Extension (both targets) -->
<key>com.apple.developer.networking.networkextension</key>
<array><string>packet-tunnel-provider</string></array>

<!-- Personal VPN, if NEVPNManager config is used from the app -->
<key>com.apple.developer.networking.vpn.api</key>
<array><string>allow-vpn</string></array>
```

Background modes (app `Info.plist`): not strictly needed for the NE (the VPN keeps it alive), but include nothing you don't use.

### 9.2 Provisioning — the part the cert unlocks
- On the Developer portal, enable **Network Extensions** + **App Groups** on the App ID, regenerate the `.mobileprovision`.
- `packet-tunnel-provider` requires a **paid** account → the user's distribution cert is mandatory; a free dev cert will fail provisioning here.
- The NE extension needs its **own** App ID + provisioning profile with the same capabilities. Two profiles total.

### 9.3 Feather specifics
- Sign with the `.p12` (distribution) + the two `.mobileprovision` files via Feather's on-device zsign flow.
- Feather installs via its localhost OTA path — that path is just delivery; it does **not** relax entitlements, so the profiles above must be correct or AMFI rejects the NE at launch.
- App-extension bundle must be embedded in the app bundle and signed with its matching profile. Verify Feather preserves the embedded extension's entitlements (test early — extensions are a common on-device-signing failure point).

---

## 10. Build phases (do them in order)

### Phase 0 — Signal discovery (GO/NO-GO, do on a computer)
- Tether the target iPhone to a Mac/PC. Use `idevicesyslog` and/or `pymobiledevice3 syslog` / `os_trace_relay`.
- Capture logs while: (a) short-tapping the Action Button, (b) holding it, (c) double-tapping. Diff the streams.
- Determine: distinct sub-threshold line? which relay? which log level? exact match predicate?
- **Deliverable:** a documented match predicate + chosen relay, committed to `/docs/signal.md`. If none found → invoke §11 and stop.

### Phase 1 — On-device tunnel
- Skeleton SwiftUI app + PacketTunnel NE. Wire the Rust core (idevice/minimuxer/em_proxy) over FFI.
- Import a pairing file into the App Group; bring up the loopback VPN; confirm a lockdownd liveness query succeeds over `10.7.0.1`; heartbeat stable for >10 min.
- **Acceptance:** status UI shows "tunnel up" and survives backgrounding + screen lock.

### Phase 2 — Relay stream
- Start the chosen relay over the tunnel from inside the NE; stream lines to the App Group event log; render live in the app.
- **Acceptance:** the app shows a live system-log tail while backgrounded; the Phase-0 predicate matches when the button is pressed.

### Phase 3 — Classification
- Implement the §8.1 state machine; emit `.press` / `.hold` / `.double`.
- **Acceptance:** 50-press manual test, ≥95% correct single-press classification, no hold misfires, double-press detected.

### Phase 4 — Dispatch
- Notification + webhook first; then the Shortcut/launch workarounds from §8.3.
- **Acceptance:** a single press fires the configured action end-to-end with the app backgrounded and screen locked.

### Phase 5 — Persistence & packaging
- Auto-reconnect tunnel on VPN drop; heartbeat recovery; pairing-file-expiry detection with a clear re-pair prompt; onboarding that enforces "Action Button → No Action" and the VPN/Wi-Fi requirement.
- Reproducible Feather build (script the zsign invocation + profile embedding).
- **Acceptance:** cold boot → user enables VPN → presses work without opening the app first (beyond the OS requirement that the VPN be on).

---

## 11. Fallbacks if Phase 0 fails

In priority order, document whichever applies:
1. **Hold-classified-as-press:** if only the hold logs cleanly, you can still fire on the hold's `down` (fastest possible reaction to a hold) — not a true press, but lower-latency than the system action.
2. **Shortcuts → local server bridge:** Action Button (hold) → Shortcut → `Get Contents of URL` → a local server in the app. Still hold-gated; only useful if the goal relaxes to "get the activation into my code untethered."
3. **Camera-capture API:** `AVCaptureEventInteraction` / `.onCameraCaptureEvent` gives a *true* single press with **no** tunnel, but only while a capture session is live (camera indicator on, foreground or a Locked Camera Capture extension). The only fully-portable on-device true-press path; accept its session constraint.

---

## 12. Repository layout

```
actionrelay/
├── PROJECT.md                      # this file
├── docs/
│   ├── signal.md                   # Phase 0 output: match predicate, relay, level
│   └── pairing.md                  # how to generate + import the pairing file
├── app/                            # SwiftUI main app
│   ├── ActionRelayApp.swift
│   ├── Pairing/                    # import, validate, App Group storage
│   ├── Config/                     # action config model + UI
│   └── Status/                     # dashboard
├── tunnel/                         # NEPacketTunnelProvider extension
│   ├── PacketTunnelProvider.swift
│   ├── RelayClient.swift           # FFI -> Rust relay
│   ├── Classifier.swift            # §8.1 state machine
│   └── Dispatcher.swift            # §8.3
├── core/                           # Rust (cargo, staticlib + cbindgen/swift-bridge)
│   ├── src/tunnel.rs               # minimuxer/em_proxy glue
│   ├── src/lockdown.rs             # idevice handshake + heartbeat
│   ├── src/relay.rs                # os_trace_relay / syslog_relay client
│   └── src/ffi.rs                  # C ABI for Swift
├── shared/                         # App Group models (Codable)
└── scripts/
    ├── build.sh                    # cargo + xcodebuild → .ipa
    └── sign_feather.sh             # zsign invocation + profile embedding notes
```

---

## 13. Open questions to resolve while building
- Does `idevice` already implement a syslog/os_trace client, or must `core/src/relay.rs` add it? (Inspect first.)
- Does the Action Button event survive at default log level, or is an Apple logging-config profile required to raise `backboardd` verbosity? (Phase 0.)
- NE memory headroom with the Rust tunnel + relay resident — profile early; trim if near the cap.
- Pairing-file longevity on this iOS build — how often must it be regenerated, and can the heartbeat alone keep it valid?
- License posture: AGPL (if reusing StikDebug code) vs clean-room against the protocol only.
- **iOS 26.5 tunnel currency:** confirm the latest `idevice`/`em_proxy` build brings up the RSD tunnel cleanly on 26.5 *before* Phase 1 (check the idevice Discord compat channel). The relay path doesn't need the DDI, but it does need the tunnel — so a 26.5 tunnel regression would block everything. If the public build lags 26.5, building `idevice` from `main` is the fix.

---

## 14. Definition of done
A single physical press of the Action Button — with the system setting on "No Action," the app backgrounded, and the screen locked — reliably fires the user's configured action, on the target iOS build, with no computer attached, surviving a reboot once the user re-enables the loopback VPN. Honest status surfaced in-app when the VPN is off or the pairing file has expired.
