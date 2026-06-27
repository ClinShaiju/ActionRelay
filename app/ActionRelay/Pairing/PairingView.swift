import SwiftUI
import UniformTypeIdentifiers

/// Import + validate the pairing record into the app container (§7.1).
/// Generated once on a computer with `idevice_pair` (docs/pairing.md), then
/// lives on-device. The in-app listener reads it from there.
struct PairingView: View {
    @State private var importing = false
    @State private var message: String?
    @State private var present = PairingView.pairingPresent()

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

                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Pairing")
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pairingImported)) { note in
                message = note.userInfo?["message"] as? String
                present = PairingImport.present
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let src = try? result.get().first else { return }
        if let src {
            message = PairingImport.save(from: src)
            present = PairingImport.present
        }
    }

    private func remove() {
        try? FileManager.default.removeItem(at: Store.pairingFile)
        present = false
        message = "Removed."
    }

    private static func pairingPresent() -> Bool { PairingImport.present }
}
