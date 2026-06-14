//
//  LocalStatementScannerService.swift
//  Tabs
//
//  ─────────────────────────────────────────────────────────────────────────
//  PRIVACY MANIFESTO (read me):
//
//  This service is the heart of Tabs's "100% on-device" promise.
//
//  • Image OCR runs through Apple's Vision framework (`VNRecognizeTextRequest`)
//    locally on the Neural Engine / CPU. No image data leaves the device.
//  • PDF extraction uses PDFKit (`PDFDocument`) which reads bytes already on
//    disk. No upload, no remote parsing.
//  • Detection (`RecurringChargeDetector`) is pure string processing.
//
//  THERE ARE NO NETWORK CALLS ANYWHERE IN THIS FILE — AND THERE MUST NEVER BE.
//  If you ever find yourself importing a networking type here, stop. The whole
//  value proposition of this app is that the user's bank statements never touch
//  a server. Keep it that way.
//  ─────────────────────────────────────────────────────────────────────────
//

import Foundation
// Vision's request/handler types (VNImageRequestHandler, VNRecognizeTextRequest)
// predate Swift Concurrency and aren't marked Sendable, yet we legitimately use
// them across a dispatch boundary. `@preconcurrency` silences the resulting
// Sendable warnings without weakening our own concurrency safety.
@preconcurrency import Vision
import PDFKit
import UIKit

/// Errors surfaced to the UI. Each case maps to a friendly, user-facing message.
enum StatementScanError: LocalizedError, Equatable {
    case invalidImage
    case noTextFound
    case couldNotReadPDF
    case emptyDocument
    case noSubscriptionsDetected

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "That image couldn't be read. Try a clearer screenshot."
        case .noTextFound:
            return "No text was found in the image."
        case .couldNotReadPDF:
            return "Could not read PDF. The file may be password-protected or corrupted."
        case .emptyDocument:
            return "The PDF didn't contain any readable text. If it's a scanned (image-only) statement, try a screenshot instead."
        case .noSubscriptionsDetected:
            return "No subscriptions detected. You can still add them manually."
        }
    }
}

/// Parses on-device statement sources (images, PDFs) into subscription drafts.
///
/// Two layers:
///   1. Extraction — turn a source into a raw text block (Vision / PDFKit).
///   2. Detection  — turn raw text into drafts (`RecurringChargeDetector`).
/// The UI owns approval + persistence.
final class LocalStatementScannerService {

    /// The generic recurring-charge detector that turns statement text into drafts.
    private let detector: RecurringChargeDetector

    init(catalog: SubscriptionKeywordCatalog = SubscriptionKeywordCatalog()) {
        self.detector = RecurringChargeDetector(catalog: catalog)
    }

    // MARK: - 1a. Image extraction (Vision)

    /// Recognizes text in an image entirely on-device and returns drafts.
    ///
    /// - Parameter imageData: Raw image bytes (e.g. from `PhotosPicker`).
    func scanImage(data imageData: Data) async throws -> [ScannedSubscriptionDraft] {
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
            throw StatementScanError.invalidImage
        }
        let text = try await recognizeText(in: cgImage)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StatementScanError.noTextFound
        }
        return try parseDrafts(from: text)
    }

    /// Wraps `VNRecognizeTextRequest` in async/await. Runs off the main thread.
    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Take the top candidate for each recognized line and join them.
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            // `.accurate` is slower but far better for the small text on statements.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // `VNImageRequestHandler` performs recognition locally.
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            // Perform on a background queue so we never block the UI.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 1b. PDF extraction (PDFKit)

    /// Loads a single PDF and returns drafts. Convenience wrapper over `scanPDFs`.
    func scanPDF(at url: URL) async throws -> [ScannedSubscriptionDraft] {
        try await scanPDFs(at: [url])
    }

    /// Loads PDFs from the picked URLs — which may be individual PDF files
    /// and/or folders of monthly statements — merges their text, and parses the
    /// combined blob in one pass.
    ///
    /// Merging months is intentional: the detector collapses repeated charges
    /// into a single draft, while extra months raise the chance of catching a
    /// subscription a single statement happened to miss (and confirm recurrence).
    /// A file that can't be opened is skipped so one bad PDF doesn't fail the batch.
    func scanPDFs(at urls: [URL]) async throws -> [ScannedSubscriptionDraft] {
        var combined = ""
        var readCount = 0
        var sawAnyPDF = false

        for picked in urls {
            // Stop promptly if the user cancelled the scan from the overlay.
            try Task.checkCancellation()

            // Hold security-scoped access to the picked item for the whole time
            // we read it (and, for a folder, all the PDFs inside it). Process-wide
            // access persists across the extraction tasks. Still 100% local.
            let didStartAccess = picked.startAccessingSecurityScopedResource()
            defer { if didStartAccess { picked.stopAccessingSecurityScopedResource() } }

            let pdfURLs = Self.expandToPDFs(picked)
            guard !pdfURLs.isEmpty else { continue }
            sawAnyPDF = true

            // Extract every PDF concurrently — a folder of monthly statements
            // is the common case and extraction is CPU-bound per file — then
            // stitch results back in the stable name-sorted order so detection
            // (and the drafts it produces) stays deterministic. A file that
            // can't be opened yields nil and is skipped, so one bad PDF
            // doesn't fail the batch. Each task bails early if cancelled.
            let texts = await withTaskGroup(of: (Int, String?).self) { group in
                for (index, pdfURL) in pdfURLs.enumerated() {
                    group.addTask(priority: .userInitiated) {
                        guard !Task.isCancelled else { return (index, nil) }
                        return (index, try? Self.extractText(fromPDFAt: pdfURL))
                    }
                }
                var collected = [String?](repeating: nil, count: pdfURLs.count)
                for await (index, text) in group {
                    collected[index] = text
                }
                return collected
            }

            for text in texts {
                guard let text else { continue }
                combined.append("\n")
                combined.append(text)
                readCount += 1
            }
        }

        try Task.checkCancellation()

        // Selected a folder with no PDFs in it at all.
        guard sawAnyPDF else { throw StatementScanError.noSubscriptionsDetected }
        // Found PDFs but none could be opened/read.
        guard readCount > 0 else { throw StatementScanError.couldNotReadPDF }
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StatementScanError.emptyDocument
        }
        return try parseDrafts(from: combined)
    }

    /// Expands a picked URL into the PDF files it represents:
    ///   • a PDF file  → itself
    ///   • a folder    → every `.pdf` inside it (recursively), name-sorted
    ///   • anything else → empty
    private static func expandToPDFs(_ url: URL) -> [URL] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }

        if isDirectory.boolValue {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "pdf" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } else {
            return url.pathExtension.lowercased() == "pdf" ? [url] : []
        }
    }

    /// Pulls the `.string` value out of every page of a `PDFDocument`.
    private static func extractText(fromPDFAt url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw StatementScanError.couldNotReadPDF
        }
        // `document.string` concatenates all pages, but we iterate page-by-page
        // to be resilient to any single page that fails to render text.
        var pageStrings: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let pageText = page.string {
                pageStrings.append(pageText)
            }
        }
        return pageStrings.joined(separator: "\n")
    }

    // MARK: - 2. Detection

    /// Turns extracted statement text into subscription drafts via the generic
    /// `RecurringChargeDetector`. The single entry point the extraction paths
    /// call, kept `internal` so it's unit-testable.
    func parseDrafts(from text: String) throws -> [ScannedSubscriptionDraft] {
        let drafts = detector.drafts(from: text)
        guard !drafts.isEmpty else { throw StatementScanError.noSubscriptionsDetected }
        return drafts
    }
}
