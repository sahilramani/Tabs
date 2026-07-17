//
//  PDFDocumentPicker.swift
//  Tabs
//
//  A thin SwiftUI wrapper around `UIDocumentPickerViewController`, restricted to
//  PDFs. The user picks a file from Files/iCloud Drive; we only ever read its
//  bytes locally.
//

import SwiftUI
import UniformTypeIdentifiers

/// Presents the system document picker for statement import, returning the
/// chosen URLs via `onPick`. The user can select several PDFs at once, or a
/// whole folder of monthly statements — folder expansion happens in the scanner.
struct PDFDocumentPicker: UIViewControllerRepresentable {

    /// What the picker lets the user choose. The import sheet narrows this to
    /// just PDFs or just folders so each entry point does one obvious thing.
    var contentTypes: [UTType] = [.pdf, .folder]

    /// Called with the selected URLs (PDF files and/or folders). These are
    /// security-scoped, in-place URLs; the scanner balances access calls and
    /// reads them entirely on-device.
    let onPick: ([URL]) -> Void

    /// Called if the user cancels without selecting anything.
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Allow PDFs and folders. `asCopy: false` so a folder can be opened in
        // place and enumerated; the scanner holds security-scoped access while
        // it reads. Multiple selection covers "pick all my monthly statements".
        //
        // On the Mac this requires running as Mac Catalyst (the project sets
        // SUPPORTS_MACCATALYST): Catalyst bridges this picker to a real
        // NSOpenPanel where selecting a folder and clicking Open returns it.
        // The "Designed for iPad" variant is disabled — its remote picker can
        // never return a folder, only navigate into it.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes, asCopy: false
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    #if targetEnvironment(macCatalyst)
    /// Presents a real AppKit `NSOpenPanel` configured as a folder chooser and
    /// returns the selection synchronously (the panel runs its own modal loop).
    ///
    /// Why this exists: on the Mac, the UIKit document picker — under both
    /// "Designed for iPad" AND Catalyst — can only *navigate into* a folder;
    /// its Open button never returns one, and SwiftUI's drop modifiers don't
    /// receive Finder drags either (both verified empirically). Catalyst runs
    /// on top of AppKit, so the public NSOpenPanel API is reachable through
    /// the ObjC runtime even though it can't be linked directly.
    static func chooseFoldersViaOpenPanel() -> [URL] {
        guard let panelClass = NSClassFromString("NSOpenPanel") as? NSObject.Type,
              let panel = panelClass.perform(NSSelectorFromString("openPanel"))?
                  .takeUnretainedValue() as? NSObject
        else { return [] }

        panel.setValue(true, forKey: "canChooseDirectories")
        panel.setValue(false, forKey: "canChooseFiles")
        panel.setValue(true, forKey: "allowsMultipleSelection")
        panel.setValue("Scan Folder", forKey: "prompt")
        panel.setValue("Choose a folder of statements — subfolders are scanned too.", forKey: "message")

        let runModalSelector = NSSelectorFromString("runModal")
        guard let implementation = panel.method(for: runModalSelector) else { return [] }
        typealias RunModalFunction = @convention(c) (NSObject, Selector) -> Int
        let runModal = unsafeBitCast(implementation, to: RunModalFunction.self)

        let okResponse = 1   // NSApplication.ModalResponse.OK
        guard runModal(panel, runModalSelector) == okResponse else { return [] }
        return (panel.value(forKey: "URLs") as? [URL]) ?? []
    }
    #endif

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: PDFDocumentPicker

        init(_ parent: PDFDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else {
                parent.onCancel()
                return
            }
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
