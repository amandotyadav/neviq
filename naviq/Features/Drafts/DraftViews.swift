import SwiftUI
import UIKit

/// Generates a draft with Saathi from verified profile facts, then hands it
/// to the editor for review. Nothing is ever sent from here.
struct DraftComposerView: View {
    enum Kind: String, Identifiable {
        case email, coverLetter, resume, resumeSummary
        var id: String { rawValue }
        var apiKind: String {
            switch self {
            case .email: "email"
            case .coverLetter: "cover_letter"
            case .resume: "resume"
            case .resumeSummary: "resume_summary"
            }
        }
        var title: String {
            switch self {
            case .email: "Application email"
            case .coverLetter: "Cover letter"
            case .resume: "Tailored resume"
            case .resumeSummary: "Resume summary"
            }
        }
    }

    let kind: Kind
    let opportunity: Opportunity?
    let onCreated: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tone = "formal"
    @State private var recipient: String = ""
    @State private var notes: String = ""
    @State private var generating = false
    @State private var error: APIError?
    @State private var created: Draft?

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    DraftEditorBody(draft: created, onSaved: { onCreated($0) }, onDeleted: { _ in dismiss() }, close: { dismiss() })
                } else {
                    form
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if created == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private var form: some View {
        Form {
            if let opportunity {
                Section("For") { Text(opportunity.title).font(.headline) }
            }
            if kind == .email {
                Section("Tone") {
                    Picker("Tone", selection: $tone) {
                        Text("Formal").tag("formal")
                        Text("Warm").tag("warm")
                        Text("Concise").tag("concise")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Recipient (optional)") {
                    TextField("e.g. Programme Coordinator", text: $recipient)
                }
            }
            Section {
                TextField("Anything true you'd like included", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            } header: { Text("Your notes (optional)") } footer: {
                Text("Saathi uses only your Naviq profile and these notes. Missing details appear as [ADD: …] placeholders for you to fill in — it won't invent grades, experience, or achievements.")
            }
            if let error {
                Section {
                    Label(error.localizedDescription, systemImage: error.isAIUnavailable ? "sparkles.slash" : "exclamationmark.triangle")
                        .foregroundStyle(NaviqColor.coral)
                    if error.isAIUnavailable {
                        Text("You can still write this yourself in Applications ▸ Drafts.").font(.footnote)
                    }
                }
            }
            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        Spacer()
                        if generating { ProgressView(); Text("Drafting…") } else { Label("Draft with Saathi", systemImage: "sparkles") }
                        Spacer()
                    }
                }
                .disabled(generating)
            }
        }
    }

    private func generate() {
        generating = true
        error = nil
        Task {
            do {
                let draft: Draft
                if kind == .email, let opportunity {
                    draft = try await NaviqAPI.draftEmail(opportunityId: opportunity.id, tone: tone, recipient: recipient, notes: notes)
                } else {
                    draft = try await NaviqAPI.generateDocument(kind: kind.apiKind, opportunityId: opportunity?.id, notes: notes)
                }
                Haptics.success()
                onCreated(draft)
                withAnimation(.smooth) { created = draft }
            } catch let e as APIError {
                error = e
            } catch {
                self.error = .network(error.localizedDescription)
            }
            generating = false
        }
    }
}

/// Standalone editor sheet for an existing draft.
struct DraftEditorView: View {
    let draft: Draft
    let onSave: (Draft) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DraftEditorBody(draft: draft, onSaved: onSave, onDeleted: { id in onDelete(id); dismiss() }, close: { dismiss() })
                .navigationTitle(draft.kindLabel)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DraftEditorBody: View {
    let onSaved: (Draft) -> Void
    let onDeleted: (String) -> Void
    let close: () -> Void

    @State private var draft: Draft
    @State private var subject: String
    @State private var bodyText: String
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var pdfURL: URL?

    init(draft: Draft, onSaved: @escaping (Draft) -> Void, onDeleted: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.close = close
        self.draft = draft
        self.subject = draft.subject ?? ""
        self.bodyText = draft.body
    }

    private var placeholders: [String] {
        bodyText.matches(of: /\[ADD:\s*([^\]]+)\]/).map { String($0.output.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NaviqSpacing.l) {
                HStack(spacing: 6) {
                    Image(systemName: draft.generatedBy == "ai" ? "sparkles" : "pencil")
                    Text(draft.generatedBy == "ai" ? "Drafted by Saathi AI — review before using" : "Written by you")
                }
                .kickerStyle(draft.generatedBy == "ai" ? NaviqColor.accent : NaviqColor.inkTertiary)

                if !placeholders.isEmpty || !draft.missingInformation.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fill in before using").font(.subheadline.weight(.semibold))
                        ForEach(Array(Set(placeholders + draft.missingInformation)).sorted(), id: \.self) {
                            Label($0, systemImage: "square.and.pencil").font(.footnote)
                        }
                    }
                    .foregroundStyle(NaviqColor.amber)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { RoundedRectangle(cornerRadius: 12).fill(NaviqColor.amberSoft) }
                }

                if draft.kind == "email" || !subject.isEmpty {
                    LabeledField(label: draft.kind == "email" ? "Subject" : "Title") {
                        TextField("Subject", text: $subject)
                    }
                }
                LabeledField(label: "Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .font(.system(.body, design: draft.kind == "resume" ? .monospaced : .default))
                }
                if let error { NoticeBanner(text: error) }

                Button {
                    save(markReviewed: true)
                } label: {
                    if saving { ProgressView().tint(NaviqColor.onAccent) } else {
                        Text(draft.reviewedAt == nil ? "I've reviewed this — save" : "Save changes")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: NaviqColor.ink))
                .disabled(saving)

                HStack(spacing: NaviqSpacing.m) {
                    ShareLink(item: shareText) { Label("Copy / share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(draft.reviewedAt == nil)
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("PDF", systemImage: "doc.richtext") }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(draft.reviewedAt == nil)
                    }
                }
                if draft.reviewedAt == nil {
                    Text("Sharing unlocks after you review and save. Naviq never sends anything for you.")
                        .font(.caption)
                        .foregroundStyle(NaviqColor.inkTertiary)
                }
                Button("Delete draft", role: .destructive) { confirmDelete = true }
                    .font(.subheadline)
            }
            .padding(NaviqSpacing.page)
        }
        .naviqPage()
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        .task(id: bodyText + subject) { pdfURL = PDFExporter.export(title: subject.nilIfEmpty ?? draft.kindLabel, body: bodyText) }
        .confirmationDialog("Delete this draft?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do { try await NaviqAPI.deleteDraft(draft.id); onDeleted(draft.id) }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private var shareText: String { subject.isEmpty ? bodyText : "Subject: \(subject)\n\n\(bodyText)" }

    private func save(markReviewed: Bool) {
        saving = true
        error = nil
        Task {
            do {
                let updated = try await NaviqAPI.updateDraft(draft.id, subject: subject.nilIfEmpty, body: bodyText, markReviewed: markReviewed)
                draft = updated
                onSaved(updated)
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}

/// Renders plain text to a paginated A4 PDF in the temporary directory.
enum PDFExporter {
    static func export(title: String, body: String) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 56
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(title.replacingOccurrences(of: "/", with: "-").prefix(60)).pdf")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let text = NSMutableAttributedString(string: title + "\n\n", attributes: [
            .font: UIFont(descriptor: UIFont.systemFont(ofSize: 18, weight: .semibold).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: 18).fontDescriptor, size: 18),
            .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: body, attributes: [.font: UIFont.systemFont(ofSize: 11), .paragraphStyle: paragraph]))

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { ctx in
                let framesetter = CTFramesetterCreateWithAttributedString(text)
                var location = 0
                while location < text.length {
                    ctx.beginPage()
                    let path = CGPath(rect: page.insetBy(dx: margin, dy: margin), transform: nil)
                    let cg = ctx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: page.height)
                    cg.scaleBy(x: 1, y: -1)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                    CTFrameDraw(frame, cg)
                    cg.restoreGState()
                    let visible = CTFrameGetVisibleStringRange(frame)
                    guard visible.length > 0 else { break }
                    location += visible.length
                }
            }
            return url
        } catch {
            return nil
        }
    }
}
