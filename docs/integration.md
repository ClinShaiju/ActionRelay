# Phase 1/2 — idevice integration recipe (reverse-engineered)

Grounded in the actual source of `jkcoxson/idevice` and the reference app
`StephenDev0/StikDebug`, inspected 2026-06-26. This is the proven path; follow it
instead of the spec's assumed em_proxy/minimuxer wiring (see "Key correction").

## Key correction to the spec

The spec (PROJECT.md §5) assumed we must run a `NEPacketTunnelProvider` to provide
the loopback so the device can reach its own lockdownd. **That is no longer how it
works.** Modern `idevice` ships its **own userspace TCP/IP stack** (the "adapter":
`adapter_connect` / `adapter_send` / `adapter_recv` / `adapter_close`). It brings up
the RSD tunnel to the device's own services entirely in userspace — **no system
`utun`, no NEPacketTunnelProvider needed for transport.** That's why StikDebug has
**no** Network Extension at all; it creates the tunnel in-process in the main app.

Consequence for ActionRelay: the NE is needed **only for background persistence**
(keeping the listener alive while backgrounded/locked), not for the tunnel. Two
viable persistence strategies — decide on-device:

1. **NE-as-keepalive (spec-aligned).** Run idevice's userspace tunnel + relay
   *inside* a `NEPacketTunnelProvider`. The NE process stays alive while the VPN is
   "connected"; we set minimal tunnel settings and let idevice do its userspace
   work. Cleanest story for an always-on listener; needs the paid NE entitlement.
2. **Background audio/location keepalive (StikDebug-style).** No NE; keep the main
   app alive with a silent `AVAudioSession` or `CLLocationManager` background mode.
   Simpler entitlements, but App-Store-fragile and a worse "always-on" story.

Recommendation: **strategy 1**, because §14's definition of done is a backgrounded,
screen-locked, always-on listener — exactly what the NE keeps alive. The entitlements
(§9) are already in place. Validate on-device that idevice's userspace adapter runs
inside the NE process (memory budget §5 — profile it).

## Dependency: prebuilt xcframework (no from-source cross-compile)

`idevice` publishes a prebuilt xcframework as a GitHub release asset, so we don't
cross-compile the Rust ourselves:

- Release: `jkcoxson/idevice` **v0.1.64**
- Asset: `idevice-xcframework-v0.1.64.zip` (~213 MB)
- Contents: `swift/IDevice.xcframework` (device arm64 + sim + macOS + maccatalyst slices)
- sha256: `b8250402a23c850f80b9be1d4add309aae6c935ee6a797b73616e4d8f170be5d`
- Swift module: `import IDevice` (modulemap exposes the C API `idevice.h`)

Because it's 213 MB, **don't vendor it in git**. CI downloads + extracts it before
build (see scripts/fetch_idevice.sh and the ci workflow). Pin the version + sha256.

## The proven FFI call sequence

All functions return `IdeviceFfiError *` (NULL = success); free with
`idevice_error_free`. Handles are opaque pointers.

### Tunnel bring-up (Phase 1)
```c
// 1. Load the pairing record (from the App Group container).
// 2. Create the RSD tunnel from the remote pairing to the device's own services.
//    StikDebug uses tunnel_create_rppairing(addr, …) → AdapterHandle.
tunnel_create_rppairing(const idevice_sockaddr *addr, …, AdapterHandle **adapter);
// 3. RSD handshake over the tunnel socket.
rsd_handshake_new(ReadWriteOpaque *socket, …, RsdHandshakeHandle **handshake);
// 4. Heartbeat to keep the pairing/tunnel alive — run a marco/polo loop on a thread.
heartbeat_connect_rsd(AdapterHandle*, RsdHandshakeHandle*, HeartbeatClientHandle**);
//    loop: heartbeat_get_marco(client, …); heartbeat_send_polo(client);
```
Liveness check (spec §7.1 step 3): after the handshake, `rsd_get_services` /
`idevice_rsd_checkin` confirms the tunnel is up before starting any relay.

### Relay stream (Phase 2)
```c
syslog_relay_connect_rsd(AdapterHandle *adapter,
                         RsdHandshakeHandle *handshake,
                         SyslogRelayClientHandle **client);   // start com.apple.syslog_relay
char *line;
while (syslog_relay_next(client, &line) == NULL) {            // blocks per line
    // match Phase-0 predicate, classify, dispatch:
    if (strstr(line, "Action page:0xB usage:0x2D")) {
        phase = strstr(line, "downEvent:1") ? DOWN : UP;
        classifier.on_event(phase, now_ms);
    }
    idevice_string_free(line);
}
syslog_relay_client_free(client);
```

This mirrors StikDebug `JITEnableContext.startSyslogRelay(handler:onError:)` →
`SystemLogStream`. Our handler is the only difference: it filters for the Action
Button predicate (docs/signal.md) and drives the classifier instead of rendering
every line.

## Mapping onto ActionRelay's existing code

- `tunnel/RelayClient.swift` — replace the stub loop with `syslog_relay_*` above;
  emit `ButtonEvent{phase, ts}` to its `onEvent` callback. (Real code staged behind
  `#if canImport(IDevice)`.)
- `tunnel/PacketTunnelProvider.swift` — in `startTunnel`, do the tunnel bring-up +
  heartbeat before `relay.start()`. Keep routing minimal; idevice's adapter is
  userspace, so the NE's packet flow is incidental (strategy 1).
- `tunnel/Classifier.swift` / `core` — unchanged; already validated against real
  device timing (docs/signal.md).
- Pairing file already imported to the App Group by `app/.../PairingView.swift`.

## Remaining work that needs the device (cannot be done from CI alone)

1. Confirm idevice's userspace adapter runs inside the NE process within the memory
   budget (§5). If too heavy, fall back to strategy 2.
2. `tunnel_create_rppairing` argument plumbing (the `idevice_sockaddr` / pairing
   handles) — exact shapes from `idevice.h`; verify against a live tunnel.
3. Heartbeat cadence + reconnect on drop (Phase 5).
4. Signed build (Feather + your cert) — the NE won't load unsigned, so end-to-end
   tunnel validation requires it.

CI can prove **link + compile** against `IDevice.xcframework`; runtime tunnel
validation is a device + signed-build step.
