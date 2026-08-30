//
//  ImportSheetView.swift
//  Tabs
//
//  The "Add subscriptions" sheet: four on-device paths for feeding Tabs a
//  statement. The sheet only *chooses* a path — it reports the selection and
//  dismisses; the home screen presents the matching system picker so the
//  picker isn't fighting the sheet for presentation.
//
//  PRIVACY: purely navigational. No I/O.
//

import SwiftUI

/// The import path the user picked from the sheet.
enum ImportAction {
    case scanScreenshot
    case importPDF
    case importFolder
    case addManually
    /// Import the synthetic statements bundled with the app, so the detector
    /// can be tried without handing it a real bank statement.
    case trySampleStatements
}

struct ImportSheetView: View {
    /// Called with the chosen path just before the sheet dismisses itself.
    let onSelect: (ImportAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            optionCard
            sampleCard
            footer
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Add subscriptions")
                .font(.title2.bold())
                .foregroundStyle(Theme.label)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    private var optionCard: some View {
        VStack(spacing: 0) {
            option(
                icon: "camera.viewfinder",
                title: "Scan a screenshot",
                subtitle: "OCR your bank app, on-device",
                action: .scanScreenshot
            )
            divider
            option(
                icon: "doc.text",
                title: "Import a PDF statement",
                subtitle: "Text extracted with PDFKit",
                action: .importPDF
            )
            divider
            option(
                icon: "folder",
                title: "Import a folder",
                subtitle: "Months at once — better detection",
                action: .importFolder
            )
            divider
            option(
                icon: "pencil",
                title: "Add manually",
                subtitle: "Name, price, and billing cycle",
                action: .addManually
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.bgElevated)
        )
    }

    /// Four months of fictional statements ship with the app. Detection needs
    /// at least three sightings of a charge, so one month would find nothing.
    private var sampleCard: some View {
        VStack(spacing: 0) {
            option(
                icon: "wand.and.stars",
                title: "Try sample statements",
                subtitle: "Four fictional months — no data of your own",
                action: .trySampleStatements
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.bgElevated)
        )
    }

    private func option(icon: String, title: String, subtitle: String, action: ImportAction) -> some View {
        Button {
            onSelect(action)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.label)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, 16 + 38 + 14)   // align with the titles
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.caption)
            Text("Everything is read locally. Nothing leaves this iPhone.")
                .font(.caption)
        }
        .foregroundStyle(Theme.tertiary)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ImportSheetView { _ in }
        }
}
