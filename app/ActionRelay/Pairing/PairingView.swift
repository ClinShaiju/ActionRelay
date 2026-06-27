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
                          allowedContentTypes: [.propertyList, .data],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let src = try result.get().first else { return }
            let dest = Store.pairingFile
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: src)
            // Minimal validation: it must be a plist with the expected keys.
            guard let plist = try PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil) as? [String: Any],
                  plist["HostID"] != nil || plist["DeviceCertificate"] != nil else {
                message = "Not a valid pairing record (missing HostID/DeviceCertificate)."
                return
            }
            try data.write(to: dest, options: .atomic)
            present = true
            message = "Imported."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    private func remove() {
        try? FileManager.default.removeItem(at: Store.pairingFile)
        present = false
        message = "Removed."
    }

    private static func pairingPresent() -> Bool {
        FileManager.default.fileExists(atPath: Store.pairingFile.path)
    }
}
