import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    var text: String
    var citations: [Citation] = []
    var actions: [ProposedAction] = []
    var isError = false
}

@Observable
final class SaathiModel {
    enum ActionState: Equatable { case pending, running, done(String), failed(String) }

    var messages: [ChatMessage] = []
    var sending = false
    var aiAvailable: Bool?
    var actionStates: [String: ActionState] = [:]
    var contextOpportunityId: String?

    func checkStatus() async {
        aiAvailable = (try? await NaviqAPI.aiStatus().available) ?? nil
    }

    func send(_ text: String) async {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, !sending else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        sending = true
        defer { sending = false }
        let history = messages
            .filter { !$0.isError && $0.role != .system }
            .suffix(20)
            .map { (role: $0.role == .user ? "user" : "assistant", content: String($0.text.prefix(3900))) }
        do {
            let reply = try await NaviqAPI.chat(messages: Array(history), contextOpportunityId: contextOpportunityId)
            messages.append(ChatMessage(role: .assistant, text: reply.reply, citations: reply.citations, actions: reply.proposedActions))
            for a in reply.proposedActions { actionStates[a.id] = .pending }
            aiAvailable = true
        } catch let e as APIError {
            if e.isAIUnavailable, e.code == "AI_UNAVAILABLE" { aiAvailable = false }
            messages.append(ChatMessage(role: .assistant, text: e.localizedDescription, isError: true))
        } catch {
            messages.append(ChatMessage(role: .assistant, text: error.localizedDescription, isError: true))
        }
    }
}

struct SaathiView: View {
    @Environment(AppRouter.self) private var router
    @State private var model = SaathiModel()
    @State private var input: String = ""
    @State private var composerFor: Opportunity?
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "What should I do next?",
        "Find opportunities that match my skills",
        "What scholarship criteria am I missing?",
        "Help me build a cybersecurity roadmap",
        "Show me my upcoming deadlines",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: NaviqSpacing.l) {
                            intro
                            ForEach(model.messages) { m in
                                MessageView(message: m, actionStates: model.actionStates) { action in
                                    Task { await perform(action) }
                                } onDismiss: { action in
                                    model.actionStates[action.id] = .failed("Dismissed")
                                }
                                .id(m.id)
                            }
                            if model.sending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Saathi is checking your data…").font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
                                }
                                .id("typing")
                            }
                        }
                        .padding(NaviqSpacing.page)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.messages.count) {
                        withAnimation(.smooth) { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                    }
                }
                composer
            }
            .naviqPage()
            .navigationTitle("Saathi")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: OpportunityLink.self) { OpportunityDetailView(opportunityId: $0.id) }
            .toolbar {
                if !model.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New chat") { model.messages = []; model.contextOpportunityId = nil }
                    }
                }
            }
            .task { await model.checkStatus() }
            .task(id: router.saathiPrompt?.text) { await consumeQueuedPrompt() }
            .sheet(item: $composerFor) { opp in
                DraftComposerView(kind: .email, opportunity: opp) { _ in }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            Text("Your assistant").kickerStyle(NaviqColor.accent)
            Text("Ask about your opportunities, eligibility, deadlines, or next steps.")
                .font(NaviqFont.headline)
                .foregroundStyle(NaviqColor.ink)
            Text("Saathi reads your Naviq profile and verified listings. It can suggest actions, but you confirm every change.")
                .font(.footnote)
                .foregroundStyle(NaviqColor.inkSecondary)
            if model.aiAvailable == false {
                NoticeBanner(text: "Saathi AI isn't configured on this server right now. Discover, eligibility checks, saving, tracking, and roadmaps still work.", tone: .info)
            }
            if model.messages.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { Task { await model.send(s) } } label: { Chip(text: s) }
                            .buttonStyle(.plain)
                            .disabled(model.sending || model.aiAvailable == false)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .bottom, spacing: NaviqSpacing.s) {
                TextField("Message Saathi", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background { RoundedRectangle(cornerRadius: 20).fill(NaviqColor.surface) }
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(NaviqColor.rule) }
                    .submitLabel(.send)
                    .onSubmit(sendInput)
                    .disabled(model.aiAvailable == false)
                Button(action: sendInput) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(NaviqColor.onAccent)
                        .background { Circle().fill(canSend ? NaviqColor.ink : NaviqColor.rule) }
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, NaviqSpacing.page)
            .padding(.vertical, NaviqSpacing.s)
        }
        .background { NaviqColor.paper.ignoresSafeArea() }
    }

    private var canSend: Bool { !input.trimmed.isEmpty && !model.sending && model.aiAvailable != false }

    private func sendInput() {
        let text = input
        input = ""
        Task { await model.send(text) }
    }

    private func consumeQueuedPrompt() async {
        guard let prompt = router.saathiPrompt else { return }
        router.saathiPrompt = nil
        if prompt.opportunityId != nil { model.contextOpportunityId = prompt.opportunityId }
        if model.aiAvailable == nil { await model.checkStatus() }
        if model.aiAvailable == false { input = prompt.text; return }
        await model.send(prompt.text)
    }

    /// Executes a proposed action through the normal API. Success is shown
    /// only after the server confirms it.
    private func perform(_ action: ProposedAction) async {
        model.actionStates[action.id] = .running
        do {
            switch action.type {
            case "save_opportunity":
                guard let id = action.opportunityId else { throw APIError.network("Missing opportunity.") }
                try await NaviqAPI.setSaved(id, saved: true)
                router.savedVersion += 1
                model.actionStates[action.id] = .done("Saved — confirmed by Naviq.")
            case "track_application":
                guard let id = action.opportunityId else { throw APIError.network("Missing opportunity.") }
                _ = try await NaviqAPI.createApplication(JSONBody.object(["opportunityId": id, "nextAction": action.nextAction]))
                router.applicationsVersion += 1
                await ReminderCoordinator.syncAfterChange(requestPermission: true)
                model.actionStates[action.id] = .done("Added to your tracker. You haven't applied yet — do that on the official site.")
            case "generate_roadmap":
                _ = try await NaviqAPI.generateRoadmap(goal: action.goal ?? "My goal", opportunityId: action.opportunityId)
                router.roadmapVersion += 1
                model.actionStates[action.id] = .done("Roadmap created. Open the Roadmap tab to review it.")
            case "draft_email":
                guard let id = action.opportunityId else { throw APIError.network("Missing opportunity.") }
                composerFor = try await NaviqAPI.opportunity(id)
                model.actionStates[action.id] = .done("Opened the email composer. Review before using.")
            default:
                model.actionStates[action.id] = .failed("This action isn't supported.")
            }
            Haptics.success()
        } catch let e as APIError where e.code == "CONFLICT" {
            model.actionStates[action.id] = .done("Already in your tracker.")
        } catch {
            model.actionStates[action.id] = .failed(error.localizedDescription)
            Haptics.warning()
        }
    }
}

private struct MessageView: View {
    let message: ChatMessage
    let actionStates: [String: SaathiModel.ActionState]
    let onConfirm: (ProposedAction) -> Void
    let onDismiss: (ProposedAction) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(NaviqColor.paper)
                    .background { RoundedRectangle(cornerRadius: 18).fill(NaviqColor.ink) }
            }
            .accessibilityLabel("You said: \(message.text)")
        } else {
            VStack(alignment: .leading, spacing: NaviqSpacing.s) {
                HStack(spacing: 6) {
                    NaviqMark(size: 14)
                    Text(message.isError ? "Saathi · unavailable" : "Saathi").kickerStyle(message.isError ? NaviqColor.coral : NaviqColor.inkTertiary)
                }
                Text(LocalizedStringKey(message.text))
                    .foregroundStyle(message.isError ? NaviqColor.coral : NaviqColor.ink)
                    .textSelection(.enabled)
                if !message.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sources").kickerStyle()
                        ForEach(message.citations) { c in
                            NavigationLink(value: OpportunityLink(id: c.opportunityId)) {
                                HStack(spacing: 6) {
                                    Image(systemName: c.verificationStatus == "verified" ? "checkmark.seal" : "exclamationmark.triangle")
                                        .foregroundStyle(c.verificationStatus == "verified" ? NaviqColor.jade : NaviqColor.amber)
                                    Text(c.title).font(.footnote.weight(.semibold)).foregroundStyle(NaviqColor.accent).multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                ForEach(message.actions) { action in
                    ActionCard(action: action, state: actionStates[action.id] ?? .pending, onConfirm: { onConfirm(action) }, onDismiss: { onDismiss(action) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ActionCard: View {
    let action: ProposedAction
    let state: SaathiModel.ActionState
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested action · needs your OK").kickerStyle(NaviqColor.accent)
            Text(action.label).font(.headline).foregroundStyle(NaviqColor.ink)
            if let next = action.nextAction { Text("Next step: \(next)").font(.footnote).foregroundStyle(NaviqColor.inkSecondary) }
            switch state {
            case .pending:
                HStack {
                    Button("Confirm", action: onConfirm).buttonStyle(.borderedProminent).tint(NaviqColor.ink)
                    Button("Not now", action: onDismiss).buttonStyle(.bordered).tint(NaviqColor.inkSecondary)
                }
            case .running:
                ProgressView()
            case .done(let m):
                Label(m, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(NaviqColor.jade)
            case .failed(let m):
                Label(m, systemImage: m == "Dismissed" ? "xmark" : "exclamationmark.triangle").font(.footnote)
                    .foregroundStyle(m == "Dismissed" ? NaviqColor.inkTertiary : NaviqColor.coral)
            }
        }
        .padding(NaviqSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 14).fill(NaviqColor.surface) }
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(NaviqColor.accent.opacity(0.4)) }
    }
}
