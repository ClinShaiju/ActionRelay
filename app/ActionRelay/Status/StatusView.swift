import SwiftUI

struct StatusView: View {
    @StateObject private var listener = ListenerService.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Listener") {
                    row("Running", value: listener.running ? "yes" : "no", ok: listener.running)
                    row("Pairing", value: pairingPresent ? "imported" : "missing", ok: pairingPresent)
                    if listener.running {
                        row("Tunnel", value: listener.tunnelUp ? "up" : "connecting…", ok: listener.tunnelUp)
                        row("Relay", value: listener.relayUp ? "streaming" : "off", ok: listener.relayUp)
                    }
                    row("Last event", value: listener.lastEvent ?? "—", ok: listener.lastEvent != nil)
                    if let err = listener.lastError {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Error", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.footnote.bold())
                            Text(err).font(.footnote).foregroundStyle(.secondary)
                                .textSelection(.enabled) // full message, copyable
                        }
                    }
                }

                Section {
                    if listener.running {
                        Button("Stop listener", role: .destructive) { listener.stop() }
                    } else {
                        Button("Start listener") { listener.start() }
                    }
                } footer: {
                    Text("Requires a loopback VPN (LocalDevVPN or StosVPN, free on the App Store) installed AND enabled — that provides the 10.7.0.1 route to the device's own services. Without it the tunnel times out. ActionRelay itself has no Network Extension; it rides that VPN. Set system Action Button → \"No Action\" so presses don't double-fire (§8.2). After a reboot, open the app once to restart the listener.")
                }

                Section {
                    Text("Tunnel + relay run over the imported pairing file. When you press the Action Button, watch \"Last event\". If Tunnel or Relay stays down, the Error row above (tap-and-hold to copy) shows why.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ActionRelay")
        }
    }

    private var pairingPresent: Bool {
        FileManager.default.fileExists(atPath: Store.pairingFile.path)
    }

    private func row(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}
