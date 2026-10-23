import SwiftUI

/// Navigation values shared across tabs.
struct OpportunityLink: Hashable { let id: String }

@Observable
final class HomeModel {
    var moves: LoadState<[NextMove]> = .idle
    var matches: LoadState<[Opportunity]> = .idle
    var deadlines: [DeadlineItem] = []
    var announcements: LoadState<[Announcement]> = .idle
    var announcementsReason: String?
    var restrictedCount = 0
    var roadmap: Roadmap?
    var partialErrors: [String] = []

    func load() async {
        if moves.value == nil { moves = .loading }
        if matches.value == nil { matches = .loading }
        partialErrors = []
        async let m = NaviqAPI.nextMoves()
        async let r = NaviqAPI.matches()
        async let d = NaviqAPI.deadlines()
        async let a = NaviqAPI.announcements()
        async let rm = NaviqAPI.roadmap()

        do { moves = .loaded(try await m) } catch { moves = .failed(error.localizedDescription) }
        do {
            let env = try await r
            matches = .loaded(env.data)
            restrictedCount = env.meta?.excludedRestricted ?? 0
        } catch { matches = .failed(error.localizedDescription) }
        do { deadlines = try await d } catch { partialErrors.append("Deadlines: \(error.localizedDescription)") }
        do {
            let env = try await a
            announcements = .loaded(env.data)
            announcementsReason = env.meta?.reason
        } catch { announcements = .failed(error.localizedDescription) }
        do { roadmap = try await rm } catch { partialErrors.append("Roadmap: \(error.localizedDescription)") }
    }
}

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = HomeModel()
    @State private var path = NavigationPath()
    @State private var showProfile = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
                    masthead
                    nextMoveSection
                    if !model.deadlines.isEmpty { deadlinesSection }
                    matchesSection
                    roadmapSection
                    campusSection
                    saathiEntry
                    ForEach(model.partialErrors, id: \.self) { NoticeBanner(text: $0) }
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, NaviqSpacing.xxl)
            }
            .naviqPage()
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NaviqWordmark(markSize: 22, font: .system(.headline, design: .rounded).weight(.heavy))
                        .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: {
                        Text(initial)
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(NaviqColor.ink)
                            .frame(width: 34, height: 34)
                            .background { Circle().fill(NaviqColor.sunny) }
                    }
                    .accessibilityLabel("Profile and settings")
                }
            }
            .navigationDestination(for: OpportunityLink.self) { OpportunityDetailView(opportunityId: $0.id) }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .task(id: router.applicationsVersion + router.roadmapVersion + router.savedVersion) { await model.load() }
        }
    }

    private var initial: String { String(session.user?.firstName.prefix(1) ?? "N").uppercased() }

    // MARK: Sections

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(NaviqColor.accent)
            Text("\(greeting), \(session.user?.firstName ?? "there") 👋")
                .font(NaviqFont.display)
                .foregroundStyle(NaviqColor.ink)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let p = session.user?.profile, let degree = p.degree?.nilIfEmpty {
                Text([degree, p.branch?.nilIfEmpty, p.currentYear.map { "Year \($0)" }, p.collegeName].compactMap { $0 }.joined(separator: " · "))
                    .font(NaviqFont.callout)
                    .foregroundStyle(NaviqColor.inkSecondary)
            }
        }
        .padding(.top, NaviqSpacing.s)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    @ViewBuilder private var nextMoveSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            switch model.moves {
            case .idle, .loading: SkeletonRows(count: 1).naviqCard()
            case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }
            case .loaded(let moves) where moves.isEmpty:
                Text("You're all caught up 🎉 Explore Discover for new verified opportunities.")
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .naviqCard()
            case .loaded(let moves):
                if let lead = moves.first {
                    Button { open(lead) } label: { LeadMoveView(move: lead) }.buttonStyle(.plain)
                }
                if moves.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(Array(moves.dropFirst().enumerated()), id: \.element.id) { i, move in
                            if i > 0 { Hairline().padding(.leading, 56) }
                            Button { open(move) } label: {
                                HStack(alignment: .center, spacing: NaviqSpacing.m) {
                                    IconBadge(systemImage: symbol(for: move.kind), fill: tint(for: move.kind), size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(move.title).font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                                        Text(move.detail).font(NaviqFont.meta).foregroundStyle(NaviqColor.inkSecondary).multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(NaviqColor.inkTertiary)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .naviqCard(padding: NaviqSpacing.l)
                }
            }
        }
    }

    private var deadlinesSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Coming up") {
                InlineLink(title: "Tracker") { router.tab = .applications }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NaviqSpacing.m) {
                    ForEach(model.deadlines.prefix(6)) { item in
                        Button {
                            if let id = item.opportunityId, item.kind == "saved_deadline" { path.append(OpportunityLink(id: id)) }
                            else { router.tab = .applications }
                        } label: {
                            VStack(alignment: .leading, spacing: NaviqSpacing.s) {
                                Dateline(date: item.date, tint: item.overdue == true || Dates.daysUntil(item.date) <= 7 ? NaviqColor.coral : NaviqColor.ink,
                                         fill: item.kind == "next_action" ? NaviqColor.mint : NaviqColor.sunny)
                                Text(kindLabel(item)).font(NaviqFont.kicker).foregroundStyle(NaviqColor.inkTertiary)
                                Text(item.title)
                                    .font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink)
                                    .multilineTextAlignment(.leading).lineLimit(3)
                                Spacer(minLength: 0)
                            }
                            .frame(width: 168, height: 168, alignment: .topLeading)
                            .naviqCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    private func kindLabel(_ item: DeadlineItem) -> String {
        switch item.kind {
        case "next_action": item.overdue == true ? "Overdue next step" : "Your next step"
        case "saved_deadline": "Saved · deadline"
        default: "Application deadline"
        }
    }

    @ViewBuilder private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(kicker: "Picked for you") {
                InlineLink(title: "Discover") { router.tab = .discover }
            }
            switch model.matches {
            case .idle, .loading: SkeletonRows(count: 2).naviqCard().padding(.top, NaviqSpacing.m)
            case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }.padding(.top, NaviqSpacing.m)
            case .loaded(let list) where list.isEmpty:
                EmptyStateView(symbol: "binoculars.fill", title: "No confirmed matches yet",
                               message: "Naviq only recommends verified, open listings where something in your profile is confirmed. Add skills and interests, or browse everything in Discover.",
                               actionTitle: "Browse Discover") { router.tab = .discover }
                    .padding(.top, NaviqSpacing.m)
            case .loaded(let list):
                ForEach(Array(list.prefix(3).enumerated()), id: \.element.id) { i, opp in
                    NavigationLink(value: OpportunityLink(id: opp.id)) { OpportunityRow(opportunity: opp, index: i + 1) }
                        .buttonStyle(.plain)
                        .padding(.top, NaviqSpacing.m)
                }
                Text("Ranked by a match heuristic, not a prediction of selection.")
                    .font(.caption)
                    .foregroundStyle(NaviqColor.inkTertiary)
                    .padding(.top, 10)
            }
            if model.restrictedCount > 0, model.matches.value != nil {
                Button { router.tab = .discover } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.open.fill").foregroundStyle(NaviqColor.accent)
                        Text("\(model.restrictedCount) more open listing\(model.restrictedCount == 1 ? " is" : "s are") limited to a specific group or field of study (for example, girl students, existing awardees, or agriculture). Naviq doesn't assume who you are — see them in Discover.")
                            .font(NaviqFont.meta)
                            .foregroundStyle(NaviqColor.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .naviqCard(tint: NaviqColor.accentSoft, padding: NaviqSpacing.m, radius: 18)
                }
                .buttonStyle(.plain)
                .padding(.top, NaviqSpacing.m)
            }
        }
    }

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Your roadmap") {
                InlineLink(title: "Open") { router.tab = .roadmap }
            }
            if let roadmap = model.roadmap, roadmap.progress.total > 0 {
                HStack(spacing: NaviqSpacing.l) {
                    ProgressRing(completed: roadmap.progress.completed, total: roadmap.progress.total)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(roadmap.goal).font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                        Text("\(roadmap.progress.completed) of \(roadmap.progress.total) milestones marked complete by you")
                            .font(NaviqFont.meta.monospacedDigit())
                            .foregroundStyle(NaviqColor.inkSecondary)
                        if let next = roadmap.milestones.first(where: { $0.status == "in_progress" }) ?? roadmap.milestones.first(where: { $0.status == "not_started" }) {
                            Label(next.title, systemImage: "arrow.right.circle.fill")
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(NaviqColor.accent)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .naviqCard()
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: NaviqSpacing.m) {
                    Text("Turn your goal into milestones you can track — with Saathi, or by adding your own.")
                        .foregroundStyle(NaviqColor.inkSecondary)
                    Button("Start a roadmap") { router.tab = .roadmap }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .naviqCard()
            }
        }
    }

    @ViewBuilder private var campusSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "From your campus")
            switch model.announcements {
            case .idle, .loading: SkeletonRows(count: 1).naviqCard()
            case .failed(let m): NoticeBanner(text: m)
            case .loaded(let list) where list.isEmpty:
                Text(model.announcementsReason == "no_college"
                     ? "Add your college in Profile to see official notices from your campus."
                     : "No current notices from your campus administrators.")
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .naviqCard()
            case .loaded(let list):
                ForEach(list.prefix(3)) { a in AnnouncementRow(announcement: a) }
            }
        }
    }

    private var saathiEntry: some View {
        Button { router.askSaathi("What should I do next?") } label: {
            HStack(spacing: NaviqSpacing.m) {
                Image(systemName: "message.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.22)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Saathi").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                    Text("“What should I do next?”").font(NaviqFont.callout).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "arrow.up.right.circle.fill").font(.title2).foregroundStyle(.white)
            }
            .padding(NaviqSpacing.l)
            .background { RoundedRectangle(cornerRadius: NaviqSpacing.radius, style: .continuous).fill(NaviqColor.warmGradient) }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Saathi assistant")
    }

    // MARK: Actions

    private func open(_ move: NextMove) {
        Haptics.tap()
        switch move.target.type {
        case "opportunity": if let id = move.target.id { path.append(OpportunityLink(id: id)) }
        case "application": router.tab = .applications
        case "milestone", "roadmap": router.tab = .roadmap
        case "profile": showProfile = true
        default: break
        }
    }

    private func symbol(for kind: String) -> String {
        switch kind {
        case "overdue_action": "exclamationmark.circle.fill"
        case "deadline_soon": "timer"
        case "track_saved": "tray.and.arrow.down.fill"
        case "explore_match": "sparkle.magnifyingglass"
        case "roadmap", "create_roadmap": "map.fill"
        default: "person.text.rectangle.fill"
        }
    }

    private func tint(for kind: String) -> Color {
        switch kind {
        case "overdue_action": NaviqColor.blush
        case "deadline_soon": NaviqColor.sunny
        case "track_saved": NaviqColor.sky
        case "explore_match": NaviqColor.mint
        default: NaviqColor.lilac
        }
    }
}

/// Circular progress for real, user-confirmed milestone completion.
struct ProgressRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 78
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    var body: some View {
        ZStack {
            Circle().stroke(NaviqColor.surfaceSunken, lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(NaviqColor.jade, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth, value: fraction)
            Text("\(completed)/\(total)")
                .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(NaviqColor.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roadmap progress")
        .accessibilityValue("\(completed) of \(total) milestones completed")
    }
}

/// The lead "next move" hero.
private struct LeadMoveView: View {
    let move: NextMove

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            Label("Your next move", systemImage: "bolt.fill")
                .font(.system(.footnote, design: .rounded).weight(.heavy))
                .foregroundStyle(NaviqColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(NaviqColor.sunny) }
            Text(move.title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Text(move.detail)
                .font(NaviqFont.body)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(move.reason).multilineTextAlignment(.leading)
            }
            .font(NaviqFont.meta)
            .foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 6) {
                Text("Let's go").font(.system(.subheadline, design: .rounded).weight(.heavy))
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(NaviqColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background { Capsule().fill(.white) }
            .padding(.top, 2)
        }
        .padding(NaviqSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(NaviqColor.heroGradient)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.12)).frame(width: 150).offset(x: 50, y: -50)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(.white.opacity(0.08)).frame(width: 100).offset(x: 20, y: 40)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: NaviqColor.accent.opacity(0.35), radius: 18, y: 10)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the related screen")
    }
}

struct AnnouncementRow: View {
    let announcement: Announcement
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconBadge(systemImage: "megaphone.fill", fill: NaviqColor.blush, size: 36)
                Text(announcement.category.capitalized)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background { Capsule().fill(NaviqColor.blush) }
                    .foregroundStyle(NaviqColor.ink)
                Text("Official campus notice").font(NaviqFont.kicker).foregroundStyle(NaviqColor.inkTertiary)
            }
            Text(announcement.title).font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink)
            Text(announcement.body)
                .font(NaviqFont.callout)
                .foregroundStyle(NaviqColor.inkSecondary)
                .lineLimit(expanded ? nil : 3)
            HStack(spacing: NaviqSpacing.m) {
                if let published = announcement.publishedAt {
                    Text("\(announcement.publisherName ?? "Campus admin") · \(published.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(NaviqColor.inkTertiary)
                }
                Spacer()
                if let url = announcement.sourceUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label("Source", systemImage: "arrow.up.right.square") }
                        .font(.system(.caption, design: .rounded).weight(.bold))
                }
                Button(expanded ? "Less" : "More") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
        }
        .naviqCard()
    }
}
