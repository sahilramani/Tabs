//
//  SampleStatementsView.swift
//  Tabs
//
//  Lets you read the bundled sample statements before handing them to the
//  detector, so "try it without your own data" doesn't mean importing
//  something sight-unseen. Four consecutive fictional months ship with the
//  app; the detector needs three sightings of a charge before it will call
//  it recurring, so one month would find nothing.
//
//  PRIVACY: reads only files inside the app bundle. No I/O beyond that.
//

import SwiftUI
import PDFKit

/// The synthetic statements bundled in `Tabs/SampleStatements`.
enum SampleStatements {

    /// Bundled statement PDFs, oldest month first.
    static var urls: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("summit-2026-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// "summit-2026-03" -> "March 2026". Falls back to the raw name so a
    /// renamed fixture still shows something sensible.
    static func displayName(for url: URL) -> String {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[1]), let month = Int(parts[2]),
              (1...12).contains(month) else {
            return url.deletingPathExtension().lastPathComponent
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = Calendar.current.date(from: components) else { return "\(month)/\(year)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }
}

struct SampleStatementsView: View {
    /// Called just before the sheet dismisses; the home screen runs the import
    /// once this sheet is gone, so the scanning overlay isn't fighting it.
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let urls = SampleStatements.urls

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(urls, id: \.self) { url in
                            NavigationLink {
                                StatementPreview(url: url)
                                    .navigationTitle(SampleStatements.displayName(for: url))
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                Label(SampleStatements.displayName(for: url),
                                      systemImage: "doc.text")
                            }
                        }
                    } header: {
                        Text("Statements")
                    } footer: {
                        Text("Fictional statements from a bank that doesn't exist. "
                             + "Every name, account number, and amount is made up. "
                             + "Tap one to read it before importing.")
                    }
                }

                Button {
                    onImport()
                    dismiss()
                } label: {
                    Text(urls.count == 1 ? "Import this statement"
                                         : "Import all \(urls.count) statements")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(urls.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("Sample statements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Renders one bundled PDF. PDFKit is already a dependency for statement
/// import, so this adds no new framework.
private struct StatementPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

#Preview {
    SampleStatementsView(onImport: {})
}
