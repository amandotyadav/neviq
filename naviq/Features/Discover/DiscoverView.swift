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
    @Namespace private var categoryUnderline
    @FocusState private var searchFocused: Bool

    /// A featured piece only when real data justifies it: open, verified, fresh and a confirmed fit.
    private var featured: Opportunity? {
        guard model.query.text.isEmpty, !model.query.isFiltered, model.query.type == nil, model.query.sort == "relevance",
              let first = model.items.first, first.availability == "open", first.isVerified, !first.isStale,
              let m = first.match, !m.hardBlocked, m.audienceRestricted != true, m.confirmedFit == true else { return nil }
        return first
    }

    /// Filters from the sheet only (the category tabs and search are shown on screen already).
    private var hasAdvancedFilters: Bool {
        let q = model.query
        return q.workMode != nil || !q.location.isEmpty || !q.skills.isEmpty || q.verifiedOnly || q.includeClosed || q.campusOnly || q.deadlineWithinDays != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    EditorialHeader(eyebrow: "Discover", title: "Opportunities worth your time",
                                    subtitle: "Every listing links to its official source. Unknown details stay marked unknown.") {
                        Button { showFilters = true } label: {
                            HStack(spacing: 5) {
                                Text("Filters")
                                if hasAdvancedFilters { Circle().fill(NaviqColor.accent).frame(width: 6, height: 6) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NaviqColor.accent)
                        }
                        .accessibilityLabel(hasAdvancedFilters ? "Filters, active" : "Filters")
                        .accessibilityIdentifier("discover.filters")
                    }
                    .padding(.top, 8)

                    searchField.padding(.top, 22)
                    categoryNav.padding(.top, 18)
                    resultsHeader.padding(.top, 22).padding(.bottom, 4)
                    results
                    officialPortals.padding(.top, 44)
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, 48)
            }
            .naviqPage()
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: Search & categories

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(NaviqColor.inkSecondary)
            TextField("Title, organisation or skill", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { model.query.text = searchText.trimmed }
                .accessibilityIdentifier("discover.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    model.query.text = ""
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NaviqColor.inkTertiary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(NaviqColor.forest).frame(height: 1.5) }
        .onChange(of: searchText) { _, new in if new.isEmpty, !model.query.text.isEmpty { model.query.text = "" } }
    }

    private var categoryNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                categoryTab("All", selected: model.query.type == nil) { model.query.type = nil }
                ForEach(OpportunityType.allCases) { t in
                    categoryTab(t.label, selected: model.query.type == t) { model.query.type = model.query.type == t ? nil : t }
                }
            }
            .padding(.horizontal, 1)
            .padding(.trailing, 28)
        }
        .scrollClipDisabled()
        .overlay(alignment: .bottom) { Hairline().offset(y: 1) }
    }

    private func categoryTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? NaviqColor.ink : NaviqColor.inkSecondary)
                ZStack {
                    Rectangle().fill(Color.clear).frame(height: 2.5)
                    if selected { Rectangle().fill(NaviqColor.accent).frame(height: 2.5).matchedGeometryEffect(id: "underline", in: categoryUnderline) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Results

    private var resultsHeader: some View {
        HStack {
            if case .loaded = model.state {
                Text("\(model.total) result\(model.total == 1 ? "" : "s")").eyebrowStyle(NaviqColor.ink)
            } else {
                Text("Results").eyebrowStyle(NaviqColor.ink)
            }
            Spacer()
            Menu {
                Picker("Sort", selection: $model.query.sort) {
                    Text("Best match").tag("relevance")
                    Text("Deadline soonest").tag("deadline")
                    Text("Recently updated").tag("recent")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sort: \(sortLabel)")
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NaviqColor.accent)
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
            SkeletonRows(count: 4).padding(.top, NaviqSpacing.l)
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
            ) { model.query = NaviqAPI.OpportunityQuery(); searchText = "" }
        case .loaded:
            if let featured {
                NavigationLink(value: OpportunityLink(id: featured.id)) { OpportunityFeature(opportunity: featured, eyebrow: "Featured · best match") }
                    .buttonStyle(.plain)
                    .padding(.top, NaviqSpacing.l)
            }
            let list = featured == nil ? model.items : Array(model.items.dropFirst())
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, opp in
                    if i > 0 || featured == nil { if i > 0 { Hairline() } }
                    NavigationLink(value: OpportunityLink(id: opp.id)) { OpportunityRow(opportunity: opp, index: i + (featured == nil ? 1 : 2)) }
                        .buttonStyle(.plain)
                        .onAppear { if opp.id == model.items.last?.id { Task { await model.loadMore() } } }
                }
            }
            .padding(.top, featured == nil ? 0 : NaviqSpacing.s)
            if let err = model.loadMoreError {
                NoticeBanner(text: err).padding(.top, NaviqSpacing.m)
                Button("Retry") { model.loadMoreError = nil; Task { await model.loadMore() } }
                    .buttonStyle(SecondaryButtonStyle())
            } else if model.page < model.totalPages {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }

    private var officialPortals: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            SectionEyebrow(title: "Official portals")
            Text("Browse these directly for listings Naviq hasn't verified yet.")
                .font(.footnote)
                .foregroundStyle(NaviqColor.inkSecondary)
            VStack(spacing: 0) {
                portal("National Scholarship Portal", "scholarships.gov.in", "https://scholarships.gov.in/")
                Hairline()
                portal("AICTE National Internship Portal", "internship.aicte-india.org", "https://internship.aicte-india.org/")
                Hairline()
                portal("National Career Service", "ncs.gov.in", "https://www.ncs.gov.in/")
            }
        }
    }

    private func portal(_ name: String, _ host: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).itemTitleStyle().foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                    Text(host).font(.caption).foregroundStyle(NaviqColor.inkSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(NaviqColor.accent)
            }
            .padding(.vertical, 14)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    EditorialHeader(eyebrow: "Discover", title: "Filters")

                    group("Availability") {
                        toggleRow("Include closed listings", isOn: $draft.includeClosed)
                        toggleRow("Verified sources only", isOn: $draft.verifiedOnly)
                        toggleRow("My campus only", isOn: $draft.campusOnly)
                    }

                    group("Closing within") {
                        FlowLayout(spacing: 8) {
                            ForEach([(Int?.none, "Any time"), (Int?.some(7), "7 days"), (Int?.some(30), "30 days"), (Int?.some(90), "90 days")], id: \.1) { value, label in
                                Button { draft.deadlineWithinDays = value } label: { Chip(text: label, selected: draft.deadlineWithinDays == value) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    group("Work mode") {
                        FlowLayout(spacing: 8) {
                            ForEach([(String?.none, "Any"), (String?.some("remote"), "Remote"), (String?.some("hybrid"), "Hybrid"), (String?.some("onsite"), "On-site")], id: \.1) { value, label in
                                Button { draft.workMode = value } label: { Chip(text: label, selected: draft.workMode == value) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    group("Location") {
                        TextField("City or state", text: $draft.location)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) { Rectangle().fill(NaviqColor.forest).frame(height: 1.5) }
                    }

                    group("Skills") {
                        TokenEditor(title: "Show listings that ask for any of these", tokens: $draft.skills, suggestions: [])
                    }
                }
                .padding(NaviqSpacing.page)
            }
            .naviqPage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = NaviqAPI.OpportunityQuery(text: query.text, type: query.type, sort: query.sort) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { query = draft; dismiss() }.fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .tint(NaviqColor.accent)
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: title)
            content()
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) { Text(title).font(.system(.body, design: .serif)).foregroundStyle(NaviqColor.ink) }
                .tint(NaviqColor.forest)
                .padding(.vertical, 8)
            Hairline()
        }
    }
}
