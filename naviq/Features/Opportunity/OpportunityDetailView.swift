import SwiftUI

@Observable
final class OpportunityDetailModel {
    let id: String
    var opportunity: LoadState<Opportunity> = .idle
    var eligibility: LoadState<EligibilityResult> = .idle
    var declarations: [String: Bool] = [:]
    var drafts: [Draft] = []
    var actionError: String?
    var explanation: LoadState<MatchExplanation> = .idle

    init(id: String) { self.id = id }

    func load() async {
        if opportunity.value == nil { opportunity = .loading }
        do {
            opportunity = .loaded(try await NaviqAPI.opportunity(id))
            await checkEligibility()
            drafts = (try? await NaviqAPI.drafts(opportunityId: id)) ?? []
        } catch {
            opportunity = .failed(error.localizedDescription)
        }
    }

    func checkEligibility() async {
        if eligibility.value == nil { eligibility = .loading }
        do { eligibility = .loaded(try await NaviqAPI.checkEligibility(id, declarations: declarations)) }
        catch { eligibility = .failed(error.localizedDescription) }
    }

    func toggleSave() async -> Bool {
        guard var opp = opportunity.value else { return false }
        let newValue = !(opp.isSaved ?? false)
        opp.isSaved = newValue
        opportunity = .loaded(opp)
        do {
            try await NaviqAPI.setSaved(id, saved: newValue)
            return true
        } catch {
            opp.isSaved = !newValue
            opportunity = .loaded(opp)
            actionError = "Couldn't update saved state: \(error.localizedDescription)"
            return false
        }
    }

    func explain() async {
        explanation = .loading
        do { explanation = .loaded(try await NaviqAPI.explainMatch(id)) }
        catch { explanation = .failed(error.localizedDescription) }
    }
}

struct OpportunityDetailView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: OpportunityDetailModel
    @State private var showTrack = false
    @State private var composer: DraftComposerView.Kind?
    @State private var openedDraft: Draft?
    @State private var savedPulse = false

    init(opportunityId: String) {
        self.model = OpportunityDetailModel(id: opportunityId)
    }

    var body: some View {
        Group {
            switch model.opportunity {
            case .idle, .loading:
                ScrollView { SkeletonRows(count: 4).padding(NaviqSpacing.page) }
            case .failed(let m):
                ErrorStateView(message: m) { Task { await model.load() } }
            case .loaded(let opp):
                content(opp)
            }
        }
        .naviqPage()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: $showTrack) {
            if let opp = model.opportunity.value {
                TrackSheet(opportunity: opp) { app in
                    var o = opp
                    o.tracked = TrackedRef(id: app.id, status: app.status.rawValue, archived: false)
                    model.opportunity = .loaded(o)
                    router.applicationsVersion += 1
                }
                .presentationDetents([.large])
            }
        }
        .sheet(item: $composer) { kind in
            if let opp = model.opportunity.value {
                DraftComposerView(kind: kind, opportunity: opp) { draft in
                    model.drafts.insert(draft, at: 0)
                }
            }
        }
        .sheet(item: $openedDraft) { draft in
            DraftEditorView(draft: draft) { updated in
                if let i = model.drafts.firstIndex(where: { $0.id == updated.id }) { model.drafts[i] = updated }
            } onDelete: { id in
                model.drafts.removeAll { $0.id == id }
            }
        }
    }

    private func content(_ opp: Opportunity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NaviqSpacing.xxl) {
                header(opp)
                factsGrid(opp)
                actions(opp)
                if let err = model.actionError { NoticeBanner(text: err) }
                whySection(opp)
                EligibilityReportView(state: model.eligibility, declarations: $model.declarations) {
                    Task { await model.checkEligibility() }
                }
                sourceSection(opp)
                if !opp.requiredDocuments.isEmpty { documentsSection(opp) }
                draftsSection(opp)
                Button {
                    router.askSaathi("Help me with “\(opp.title)”. What should I do next?", opportunityId: opp.id)
                } label: {
                    Label("Ask Saathi about this", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, NaviqSpacing.page)
            .padding(.bottom, NaviqSpacing.xxl)
        }
        .refreshable { await model.load() }
    }

    // MARK: Header & facts

    private func header(_ opp: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            HStack(spacing: 6) {
                Text(opp.typeLabel).kickerStyle(NaviqColor.accent)
                if opp.isCampus { Text("· Campus listing").kickerStyle(NaviqColor.coral) }
            }
            Text(opp.title)
                .font(NaviqFont.title)
                .foregroundStyle(NaviqColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(opp.organization).font(.title3).foregroundStyle(NaviqColor.inkSecondary)
            HStack(spacing: NaviqSpacing.m) {
                VerificationLabel(status: opp.verificationStatus, lastVerifiedAt: opp.lastVerifiedAt, isStale: opp.isStale)
                DeadlineLabel(availability: opp.availability, deadline: opp.deadline)
            }
            .padding(.top, 4)
        }
        .padding(.top, NaviqSpacing.s)
    }

    private func factsGrid(_ opp: Opportunity) -> some View {
        VStack(spacing: 0) {
            Hairline()
            Grid(alignment: .topLeading, horizontalSpacing: NaviqSpacing.l, verticalSpacing: NaviqSpacing.l) {
                GridRow {
                    fact("Deadline", opp.deadline.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Not published", note: opp.deadlineNote)
                    fact(opp.award != nil ? "Award" : "Stipend", opp.moneyLine ?? ((opp.award ?? opp.stipend)?.description != nil ? "See details" : "Not published"),
                         note: (opp.award ?? opp.stipend)?.description)
                }
                GridRow {
                    fact("Where", [opp.workModeLabel, opp.location?.display].compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? (opp.workMode == "not_applicable" ? "Not applicable" : "Not published"))
                    fact("Duration", opp.duration ?? (opp.opportunityType == "scholarship" ? "Per academic year" : "Not published"))
                }
            }
            .padding(.vertical, NaviqSpacing.l)
            Hairline()
        }
    }

    private func fact(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).kickerStyle()
            Text(value)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(value == "Not published" ? NaviqColor.inkTertiary : NaviqColor.ink)
            if let note {
                Text(note).font(.caption).foregroundStyle(NaviqColor.inkTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func actions(_ opp: Opportunity) -> some View {
        VStack(spacing: NaviqSpacing.m) {
            HStack(spacing: NaviqSpacing.m) {
                Button {
                    Task {
                        if await model.toggleSave() {
                            Haptics.success()
                            router.savedVersion += 1
                            if !reduceMotion {
                                withAnimation(.spring(duration: 0.3, bounce: 0.5)) { savedPulse = true }
                                try? await Task.sleep(for: .milliseconds(300))
                                withAnimation(.spring) { savedPulse = false }
                            }
                        }
                    }
                } label: {
                    Label(opp.isSaved == true ? "Saved" : "Save", systemImage: opp.isSaved == true ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                        .scaleEffect(savedPulse ? 1.08 : 1)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityValue(opp.isSaved == true ? "Saved" : "Not saved")

                if let tracked = opp.tracked {
                    Button { router.tab = .applications } label: {
                        Label(ApplicationStatus(rawValue: tracked.status)?.label ?? "Tracked", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button { showTrack = true } label: { Label("Track", systemImage: "plus.circle") }
                        .buttonStyle(PrimaryButtonStyle(tint: NaviqColor.ink))
                }
            }
            if let url = URL(string: opp.applicationUrl ?? opp.sourceUrl) {
                Link(destination: url) {
                    HStack {
                        Text(opp.availability == "closed" ? "View on official site" : "Apply on the official site")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Opening this link doesn't mark you as applied. Update your tracker once you've submitted.")
                    .font(.caption)
                    .foregroundStyle(NaviqColor.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Why this opportunity

    private func whySection(_ opp: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Why this opportunity?")
            if let match = opp.match {
                if match.factors.isEmpty {
                    Text("Add skills and interests to your profile to see how this fits you.")
                        .foregroundStyle(NaviqColor.inkSecondary)
                }
                ForEach(match.factors, id: \.self) { f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: f.positive ? "plus.circle.fill" : "minus.circle")
                            .foregroundStyle(f.positive ? NaviqColor.jade : NaviqColor.amber)
                            .accessibilityLabel(f.positive ? "In your favour" : "Consider")
                        Text(f.detail).foregroundStyle(NaviqColor.ink)
                    }
                    .font(.callout)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Match strength").kickerStyle()
                    Text("\(match.score)/100").font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(NaviqColor.inkSecondary)
                    Spacer()
                }
                Text(match.scoreLabel + ".").font(.caption).foregroundStyle(NaviqColor.inkTertiary)
            }

            switch model.explanation {
            case .idle:
                Button { Task { await model.explain() } } label: {
                    Label("Explain this in plain words", systemImage: "text.bubble")
                }
                .font(.subheadline.weight(.semibold))
            case .loading:
                HStack { ProgressView(); Text("Saathi is reading the criteria…").foregroundStyle(NaviqColor.inkSecondary) }
            case .failed(let m):
                NoticeBanner(text: m, tone: .info)
            case .loaded(let e):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Written by Saathi AI from the facts above", systemImage: "sparkles").kickerStyle(NaviqColor.accent)
                    Text(e.explanation).foregroundStyle(NaviqColor.ink)
                    ForEach(e.nextSteps, id: \.self) { s in
                        Label(s, systemImage: "arrow.turn.down.right").font(.callout).foregroundStyle(NaviqColor.inkSecondary)
                    }
                }
                .padding(NaviqSpacing.l)
                .background { RoundedRectangle(cornerRadius: 12).fill(NaviqColor.accentSoft) }
            }
        }
    }

    // MARK: Source

    private func sourceSection(_ opp: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "From the official source")
            if let desc = opp.officialDescription {
                Text(desc).foregroundStyle(NaviqColor.ink)
            } else {
                Text("The source description hasn't been captured. Read the official page for full details.")
                    .foregroundStyle(NaviqColor.inkSecondary)
            }
            if let summary = opp.summary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(opp.summarySource == "ai" ? "Summary · AI-generated" : "Summary · Naviq editor").kickerStyle()
                    Text(summary).font(.callout).foregroundStyle(NaviqColor.inkSecondary)
                }
                .padding(.leading, NaviqSpacing.m)
                .overlay(alignment: .leading) { Rectangle().fill(NaviqColor.rule).frame(width: 2) }
            }
            VStack(alignment: .leading, spacing: 8) {
                sourceLink("Official source", opp.sourceUrl)
                ForEach(opp.additionalSources ?? [], id: \.self) { s in sourceLink(s.label, s.url) }
            }
            if let notes = opp.verificationNotes {
                Text("Verification notes: \(notes)").font(.caption).foregroundStyle(NaviqColor.inkTertiary)
            }
        }
    }

    private func sourceLink(_ label: String, _ url: String) -> some View {
        Group {
            if let u = URL(string: url) {
                Link(destination: u) {
                    HStack(alignment: .top) {
                        Image(systemName: "link")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).font(.subheadline.weight(.semibold))
                            Text(u.host() ?? url).font(.caption).foregroundStyle(NaviqColor.inkTertiary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .accessibilityHint("Opens \(u.host() ?? "the website")")
            }
        }
    }

    private func documentsSection(_ opp: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            SectionHeader(kicker: "Documents the source asks for")
            ForEach(opp.requiredDocuments, id: \.self) { d in
                Label(d, systemImage: "doc.text").foregroundStyle(NaviqColor.ink).font(.callout)
            }
        }
    }

    // MARK: Drafts

    private func draftsSection(_ opp: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Application materials")
            Text("Saathi drafts from your profile only. You review and edit everything — nothing is sent for you.")
                .font(.footnote)
                .foregroundStyle(NaviqColor.inkSecondary)
            HStack(spacing: NaviqSpacing.m) {
                Button { composer = .email } label: { Label("Email", systemImage: "envelope") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { composer = .coverLetter } label: { Label("Cover letter", systemImage: "doc.richtext") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            ForEach(model.drafts) { d in
                Button { openedDraft = d } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.kindLabel).font(.subheadline.weight(.semibold)).foregroundStyle(NaviqColor.ink)
                            Text(d.reviewedAt == nil ? "Not yet reviewed" : "Reviewed \(d.reviewedAt!.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(d.reviewedAt == nil ? NaviqColor.amber : NaviqColor.inkTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(NaviqColor.inkTertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
    }
}
