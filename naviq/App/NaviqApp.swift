import SwiftUI

@main
struct NaviqApp: App {
    @State private var session = SessionStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .tint(NaviqColor.accent)
        }
    }
}

/// Cross-tab navigation and hand-offs (e.g. "Ask Saathi about this").
@Observable
final class AppRouter {
    enum Tab: Hashable { case home, discover, saathi, roadmap, applications }

    var tab: Tab = .home
    /// Prompt queued for Saathi from another screen.
    var saathiPrompt: (text: String, opportunityId: String?)?
    /// Bumped when data changes elsewhere so lists can refresh.
    var applicationsVersion = 0
    var roadmapVersion = 0
    var savedVersion = 0

    func askSaathi(_ text: String, opportunityId: String? = nil) {
        saathiPrompt = (text, opportunityId)
        tab = .saathi
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                WelcomeView()
            case .onboarding:
                OnboardingFlow()
            case .ready:
                MainTabView()
            }
        }
        .animation(.smooth(duration: 0.35), value: session.phase)
        .task { await session.restore() }
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            NaviqMark(size: 56)
            ProgressView().tint(NaviqColor.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .naviqPage()
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "safari", value: AppRouter.Tab.home) { HomeView() }
            Tab("Discover", systemImage: "magnifyingglass", value: AppRouter.Tab.discover) { DiscoverView() }
            Tab("Saathi", systemImage: "message.fill", value: AppRouter.Tab.saathi) { SaathiView() }
            Tab("Roadmap", systemImage: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath", value: AppRouter.Tab.roadmap) { RoadmapView() }
            Tab("Applications", systemImage: "tray.full", value: AppRouter.Tab.applications) { ApplicationsView() }
        }
    }
}
