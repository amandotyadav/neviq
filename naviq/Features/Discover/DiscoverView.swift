import SwiftUI

@Observable
final class DiscoverModel {
    var query = NaviqAPI.OpportunityQuery()
    var items: [Opportunity] = []
    var state: LoadState<Void> = .idle
    var total = 0
    var page = 1
    var totalPages = 1
    var loadMoreError: String?

    func reload() async {
        state = .loading
        page = 1
        loadMoreError = nil
        do {
            let env = try await NaviqAPI.opportunities(query, page: 1)
            items = env.data
            total = env.meta?.total ?? env.data.count
            totalPages = env.meta?.totalPages ?? 1
            state = .loaded(())
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard page < totalPages, loadMoreError == nil else { return }
        do {
            let env = try await NaviqAPI.opportunities(query, page: page + 1)
            page += 1
            let existing = Set(items.map(\.id))
            items.append(contentsOf: env.data.filter { !existing.contains($0.id) })
        } catch {
            loadMoreError = error.localizedDescription
        }
    }
}

struct DiscoverView: View {
    @Environment(AppRouter.self) private var router
    @State private var model = DiscoverModel()
    @State private var searchText: String = ""
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    Text("Discover")
                        .font(NaviqFont.display)
                        .foregroundStyle(NaviqColor.ink)
                        .padding(.bottom, 4)
                    Text("Every listing links to its official source. Unknown details stay marked unknown.")
                        .font(.subheadline)
                        .foregroundStyle(NaviqColor.inkSecondary)
                        .padding(.bottom, NaviqSpacing.l)

                    typeStrip.padding(.bottom, NaviqSpacing.m)
                    resultsHeader
                    Hairline().padding(.top, 8)
                    results
                    officialPortals.padding(.top, NaviqSpacing.xxl)
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, NaviqSpacing.xxl)
            }
            .naviqPage()
            .searchable(text: $searchText, prompt: "Title, organisation, or skill")
            .onSubmit(of: .search) { model.query.text = searchText.trimmed }
            .onChange(of: searchText) { _, new in if new.isEmpty { model.query.text = "" } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: model.query.isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(model.query.isFiltered ? "Filters, active" : "Filters")
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(query: $model.query)
                    .presentationDetents([.medium, .large])
            }
            .navigationDestination(for: OpportunityLink.self) { OpportunityDetailView(opportunityId: $0.id) }
            .task(id: model.query) { await model.reload() }
            .onChange(of: router.savedVersion) { Task { await model.reload() } }
            .refreshable { await model.reload() }
        }
    }

    private var typeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { model.query.type = nil } label: { Chip(text: "All", selected: model.query.type == nil) }
                    .buttonStyle(.plain)
                ForEach(OpportunityType.allCases) { t in
                    Button { model.query.type = model.query.type == t ? nil : t } label: {
                        Chip(text: t.label, selected: model.query.type == t, systemImage: t.symbol)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var resultsHeader: some View {
        HStack {
            if case .loaded = model.state {
                Text("\(model.total) result\(model.total == 1 ? "" : "s")").kickerStyle()
            } else {
                Text("Results").kickerStyle()
            }
            Spacer()
            Menu {
                Picker("Sort", selection: $model.query.sort) {
                    Text("Best match").tag("relevance")
                    Text("Deadline soonest").tag("deadline")
                    Text("Recently updated").tag("recent")
                }
            } label: {
                Label(sortLabel, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var sortLabel: String {
        switch model.query.sort {
        case "deadline": "Deadline"
        case "recent": "Recent"
        default: "Best match"
        }
    }

    @ViewBuilder private var results: some View {
        switch model.state {
        case .idle, .loading:
            SkeletonRows(count: 4).padding(.top, NaviqSpacing.m)
        case .failed(let message):
            ErrorStateView(message: message) { Task { await model.reload() } }
        case .loaded where model.items.isEmpty:
            EmptyStateView(
                symbol: "tray",
                title: model.query.isFiltered || !model.query.text.isEmpty ? "Nothing matches these filters" : "No listings yet",
                message: model.query.isFiltered || !model.query.text.isEmpty
                    ? "Try removing a filter. Closed listings are hidden unless you include them."
                    : "Naviq only lists opportunities verified against official sources. New listings appear as administrators verify them.",
                actionTitle: model.query.isFiltered ? "Clear filters" : nil
            ) { model.query = NaviqAPI.OpportunityQuery() }
        case .loaded:
            ForEach(model.items) { opp in
                NavigationLink(value: OpportunityLink(id: opp.id)) { OpportunityRow(opportunity: opp) }
                    .buttonStyle(.plain)
                    .onAppear { if opp.id == model.items.last?.id { Task { await model.loadMore() } } }
                Hairline()
            }
            if let err = model.loadMoreError {
                NoticeBanner(text: err).padding(.top, NaviqSpacing.m)
                Button("Retry") { model.loadMoreError = nil; Task { await model.loadMore() } }
            } else if model.page < model.totalPages {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }

    private var officialPortals: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            SectionHeader(kicker: "Official portals")
            Text("Browse these directly for listings Naviq hasn't verified yet.")
                .font(.footnote)
                .foregroundStyle(NaviqColor.inkSecondary)
            portal("National Scholarship Portal", "scholarships.gov.in", "https://scholarships.gov.in/")
            portal("AICTE National Internship Portal", "internship.aicte-india.org", "https://internship.aicte-india.org/")
            portal("National Career Service", "ncs.gov.in", "https://www.ncs.gov.in/")
        }
    }

    private func portal(_ name: String, _ host: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(NaviqColor.ink)
                    Text(host).font(.caption).foregroundStyle(NaviqColor.inkTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(NaviqColor.accent)
            }
            .padding(.vertical, 8)
        }
        .accessibilityHint("Opens the official website")
    }
}

struct FilterSheet: View {
    @Binding var query: NaviqAPI.OpportunityQuery
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NaviqAPI.OpportunityQuery

    init(query: Binding<NaviqAPI.OpportunityQuery>) {
        _query = query
        self.draft = query.wrappedValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Availability") {
                    Toggle("Include closed listings", isOn: $draft.includeClosed)
                    Toggle("Verified sources only", isOn: $draft.verifiedOnly)
                    Toggle("My campus only", isOn: $draft.campusOnly)
                    Picker("Closing within", selection: $draft.deadlineWithinDays) {
                        Text("Any time").tag(Int?.none)
                        Text("7 days").tag(Int?.some(7))
                        Text("30 days").tag(Int?.some(30))
                        Text("90 days").tag(Int?.some(90))
                    }
                }
                Section("Work mode") {
                    Picker("Work mode", selection: $draft.workMode) {
                        Text("Any").tag(String?.none)
                        Text("Remote").tag(String?.some("remote"))
                        Text("Hybrid").tag(String?.some("hybrid"))
                        Text("On-site").tag(String?.some("onsite"))
                    }
                    .pickerStyle(.segmented)
                }
                Section("Location") {
                    TextField("City or state", text: $draft.location)
                }
                Section {
                    TokenEditor(title: "Skills", tokens: $draft.skills, suggestions: [])
                } footer: {
                    Text("Shows listings that ask for any of these skills.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = NaviqAPI.OpportunityQuery(text: query.text, type: query.type, sort: query.sort) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { query = draft; dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
