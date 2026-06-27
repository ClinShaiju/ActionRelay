# ActionRelay

On-device, untethered iPhone **Action Button** press detector. Reads the raw
button down/up HID transitions that `backboardd` logs, over the device's own
`syslog_relay` carried by an on-device (userspace) RSD tunnel — no jailbreak, no
tether, **no Network Extension**. Full original design in [PROJECT.md](PROJECT.md);
the architecture that's actually being built is in [docs/integration.md](docs/integration.md).

## Architecture (NE-free)

The spec assumed a NEPacketTunnelProvider was needed for the tunnel. It isn't —
`idevice` ships its own **userspace TCP/IP stack**, so the RSD tunnel to the
device's own services needs no system VPN/utun (the reference app StikDebug has
no NE either). We dropped the Network Extension entirely:

- **One app target, zero restricted entitlements** → installable with *any* cert,
  including an import-only/wildcard one (the NE's `packet-tunnel-provider` + App
  Group can't be provisioned by such certs — that was blocking install).
- **Background persistence** via a silent `AVAudioSession` keepalive (the proven
  sideload technique), not a VPN.
- Tunnel + `syslog_relay` + classifier + dispatch all run **in-app**.

## Status

| Part | State |
|---|---|
| Gesture classifier (§8.1) | ✅ Implemented + tested (Rust canonical, Swift port), validated vs real device timing |
| **Phase 0 signal capture** (§3) | ✅ **GO** — confirmed on iPhone 16 Pro / iOS 26.5, see [docs/signal.md](docs/signal.md) |
| Single-target app (status/config/pairing/keepalive) | ✅ Compiles; **installable, zero restricted entitlements** |
| idevice FFI link (xcframework) | ✅ CI-proven — app compiles+links against `IDevice.xcframework` |
| Relay client `syslog_relay` (§7.2) | ✅ Real FFI loop compiles (`#if canImport(IDevice)`); runtime needs signed build |
| RSD tunnel bring-up (§7.1) | 🚧 Sequence documented (integration.md); in-app bring-up + device runtime remain |
| Feather signing / install (§9) | ✅ Installs with import-only cert (no special entitlements) |

**Phase 0 result:** a short tap emits a distinct down/up pair in plain syslog at
default level — `backboardd <NOTICE>: Action page:0xB usage:0x2D downEvent:1 down`
(and `downEvent:0 up`). Real-device timing validated the classifier thresholds
exactly (181/188 ms taps, 1038 ms hold, 151 ms double-gap). Until the tunnel +
relay are wired in, the listener emits nothing rather than fake a signal.

## What you get from CI

Every push to `main` publishes an **unsigned `.ipa`** to
[Releases](../../releases) (tag `build-<sha>`) and runs the Rust tests. The IPA is
single-target with no restricted entitlements, so **sign it with Feather + any
cert and it installs** — but it won't detect presses until the idevice tunnel is
wired (see [docs/integration.md](docs/integration.md)). The manual *idevice link
probe* workflow adds `ActionRelay-idevice-unsigned.ipa` (links the xcframework).

## Build locally

```sh
cd core && cargo test            # the tested classifier
xcodegen generate && open ActionRelay.xcodeproj   # macOS + brew install xcodegen
```

## Next steps (in order)

1. Wire the in-app idevice tunnel bring-up (`tunnel_create_rppairing` → RSD →
   heartbeat) ahead of `RelayClient.startRSD` — integration.md has the sequence.
2. Validate end-to-end on the device with a Feather-signed build: press → classifier → notification.
3. Tune keepalive robustness (audio-interruption recovery; optional location anchor).
4. Replace the Swift classifier with the Rust one over FFI.

## License

AGPL-3.0-or-later — reuses StikDebug/idevice (AGPL/copyleft), so ActionRelay
inherits it (§6).
