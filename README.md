# ActionRelay

On-device, untethered iPhone **Action Button** press detector. Reads the raw
button down/up HID transitions that `backboardd` logs, over an on-device
lockdown log relay carried by a NetworkExtension loopback VPN — no jailbreak, no
tether. Full design in [PROJECT.md](PROJECT.md).

## Status — honest

This repo is **pre–Phase 0**. The architecture is scaffolded and the one piece
that is hardware-independent — the gesture **classifier** — is implemented and
tested. Everything that depends on the actual log signal is deliberately stubbed.

| Part | State |
|---|---|
| Gesture classifier (§8.1) | ✅ Implemented + tested (Rust canonical, Swift port) |
| SwiftUI app (status / config / pairing) | ✅ Compiles, wired to App Group |
| PacketTunnel NE skeleton + pipeline | ✅ Compiles; classifier+dispatcher live |
| Dispatch: notification / webhook (§8.3) | ✅ Implemented |
| **Phase 0 signal capture** (§3) | ✅ **GO** — confirmed on iPhone 16 Pro / iOS 26.5, see [docs/signal.md](docs/signal.md) |
| idevice FFI link (xcframework) | ✅ CI-proven — NE compiles+links against `IDevice.xcframework`, see [docs/integration.md](docs/integration.md) |
| Relay client `syslog_relay` (§7.2) | ✅ Real FFI loop compiles (`#if canImport(IDevice)`); runtime needs signed build |
| RSD tunnel bring-up (§7.1) | 🚧 Sequence documented (integration.md); provider code + device runtime remain |
| Feather signing / install (§9) | 🚧 Manual — needs your distribution cert |

**Phase 0 result:** a short tap emits a distinct down/up pair in plain syslog at
default level — `backboardd <NOTICE>: Action page:0xB usage:0x2D downEvent:1 down`
(and `downEvent:0 up`). Real-device timing validated the classifier thresholds
exactly (181/188 ms taps, 1038 ms hold, 151 ms double-gap). The on-device build
proceeds on the simplest path: `syslog_relay`, no DDI. Until the tunnel + relay
are wired in, `RelayClient` emits nothing rather than fake a signal.

## What you get from CI

GitHub Actions builds an **unsigned `.ipa`** (artifact `ActionRelay-unsigned`)
and runs the Rust tests on every push. The unsigned IPA proves the app + NE
compile and bundle; it is **not installable as-is** — sign it with Feather using
your paid Apple Developer distribution cert + the two `.mobileprovision` files
(§9). It will not do anything useful until Phase 0 + the tunnel land.

## Build locally

```sh
# Rust core (the tested classifier)
cd core && cargo test

# Xcode project (macOS, needs xcodegen: brew install xcodegen)
xcodegen generate
open ActionRelay.xcodeproj
```

## Next steps (in order)

1. **Phase 0** on the device — fill in [docs/signal.md](docs/signal.md). Gate.
2. Wire `idevice`/`minimuxer`/`em_proxy` into the Rust core; bring up the RSD
   tunnel in the NE (Phase 1).
3. Implement the relay client against the Phase-0 predicate (Phase 2).
4. Replace the Swift classifier with the Rust one over FFI.
5. Feather signing script with your cert (Phase 5).

## License

AGPL-3.0-or-later — the design reuses StikDebug/idevice/minimuxer
(AGPL/copyleft), so ActionRelay inherits it (§6).
