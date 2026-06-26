import SwiftUI
import NetworkExtension

struct StatusView: View {
    @StateObject private var tunnel = TunnelManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Listener") {
                    row("VPN", value: vpnLabel, ok: tunnel.state == .connected)
                    row("Tunnel", value: tunnel.status.tunnelUp ? "up" : "down",
                        ok: tunnel.status.tunnelUp)
                    row("Pairing", value: tunnel.status.pairingValid ? "valid" : "missing",
                        ok: tunnel.status.pairingValid)
                    if let hb = tunnel.status.lastHeartbeat {
                        row("Heartbeat", value: hb.formatted(date: .omitted, time: .standard), ok: true)
                    }
                    row("Last event", value: tunnel.status.lastEvent ?? "—", ok: tunnel.status.lastEvent != nil)
                }

                Section {
                    if tunnel.state == .connected || tunnel.state == .connecting {
                        Button("Stop listener", role: .destructive) { tunnel.stop() }
                    } else {
                        Button("Start listener") { Task { try? await tunnel.start() } }
                    }
                } footer: {
                    Text("Requires Wi-Fi or Airplane Mode on and the loopback VPN active at all times (§4). Set system Action Button → \"No Action\" so presses don't double-fire (§8.2).")
                }

                Section("Build status") {
                    Text("⚠️ Pre–Phase 0: the relay signal is not yet confirmed on this device. The listener pipeline is wired but no button events stream until Phase 0 + the Rust tunnel land. See docs/signal.md.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ActionRelay")
        }
    }

    private var vpnLabel: String {
        switch tunnel.state {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .disconnecting: return "disconnecting"
        case .disconnected: return "disconnected"
        case .reasserting: return "reasserting"
        case .invalid: return "not installed"
        @unknown default: return "unknown"
        }
    }

    private func row(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}
