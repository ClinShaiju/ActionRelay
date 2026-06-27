import SwiftUI
import UniformTypeIdentifiers

/// Direct UIDocumentPickerViewController wrapper — SwiftUI's `.fileImporter`
/// opened in an unselectable browse state. `asCopy: true` + `.data` (files only,
/// NOT `.item` which includes folders and triggers browse mode) gives a real,
/// tappable file selector. The picked file is copied into a temp dir we own.
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ c: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onPick(url) } else { parent.onCancel() }
        }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
