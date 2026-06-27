import SwiftUI
import UniformTypeIdentifiers

/// Import + validate the pairing record into the app container (§7.1).
/// Generated once on a computer with `idevice_pair` (docs/pairing.md), then
/// lives on-device. The in-app listener reads it from there.
struct PairingView: View {
    @State private var importing = false
    @State private var message: String?
    @State private var present = PairingView.pairingPresent()
    @State private var pasteText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Pairing file")
                        Spacer()
                        Image(systemName: present ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(present ? .green : .secondary)
                    }
                    Button("Import pairing file…") { importing = true }
                    if present {
                        Button("Remove", role: .destructive) { remove() }
                    }
                } footer: {
                    Text("Generate on a computer with idevice_pair (not iLoader on iOS 26.x). See docs/pairing.md.")
                }

                Section {
                    TextEditor(text: $pasteText)
                        .frame(minHeight: 120)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Import pasted text") {
                        message = PairingImport.savePasted(pasteText)
                        present = PairingImport.present
                        if present { pasteText = "" }
                    }
                    .disabled(pasteText.isEmpty)
                } header: {
                    Text("Or paste pairing data")
                } footer: {
                    Text("Bulletproof fallback: paste the pairing file's contents (XML or base64) here. No file picker needed.")
                }

                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Pairing")
            .sheet(isPresented: $importing) {
                DocumentPicker(
                    onPick: { url in
                        importing = false
                        message = PairingImport.save(from: url)
                        present = PairingImport.present
                    },
                    onCancel: { importing = false })
                .ignoresSafeArea()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pairingImported)) { note in
                message = note.userInfo?["message"] as? String
                present = PairingImport.present
            }
        }
    }

    private func remove() {
        try? FileManager.default.removeItem(at: Store.pairingFile)
        present = false
        message = "Removed."
    }

    private static func pairingPresent() -> Bool { PairingImport.present }
}
