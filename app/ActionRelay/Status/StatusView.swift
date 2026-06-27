import SwiftUI

struct StatusView: View {
    @StateObject private var listener = ListenerService.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Listener") {
                    row("Running", value: listener.running ? "yes" : "no", ok: listener.running)
                    row("Pairing", value: pairingPresent ? "imported" : "missing", ok: pairingPresent)
                    row("Last event", value: listener.lastEvent ?? "—", ok: listener.lastEvent != nil)
                    if let err = listener.lastError {
                        row("Error", value: err, ok: false)
                    }
                }

                Section {
                    if listener.running {
                        Button("Stop listener", role: .destructive) { listener.stop() }
                    } else {
                        Button("Start listener") { listener.start() }
                    }
                } footer: {
                    Text("Runs in-app with a silent-audio keepalive (no VPN, no Network Extension). Set system Action Button → \"No Action\" so presses don't double-fire (§8.2). After a reboot, open the app once to restart the listener.")
                }

                Section("Build status") {
                    Text("⚠️ The tunnel/relay runtime isn't wired yet, so no button events stream. The pipeline (keepalive → tunnel → relay → classifier → dispatch) is in place; idevice tunnel bring-up is the remaining step. See docs/integration.md.")
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
