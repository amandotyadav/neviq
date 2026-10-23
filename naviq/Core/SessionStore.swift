import Foundation
import Observation

/// App-wide session: the signed-in user and auth lifecycle.
@Observable
final class SessionStore {
    enum Phase: Equatable { case launching, signedOut, onboarding, ready }

    private(set) var phase: Phase = .launching
    private(set) var user: User?
    /// Shown on the welcome screen after an unexpected sign-out.
    var notice: String?

    private let tokenAccount = "access-token"

    init() {
        APIClient.shared.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.handleExpiredSession() }
        }
    }

    func restore() async {
        guard let token = Keychain.read(account: tokenAccount) else {
            phase = .signedOut
            return
        }
        APIClient.shared.token = token
        do {
            apply(try await NaviqAPI.me())
        } catch APIError.unauthorized {
            clearLocal()
        } catch {
            // Server unreachable: keep the token, show the error on sign-in.
            notice = error.localizedDescription
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let payload = try await NaviqAPI.login(email: email, password: password)
        store(payload)
    }

    func register(name: String, email: String, password: String) async throws {
        let payload = try await NaviqAPI.register(name: name, email: email, password: password)
        store(payload)
    }

    func signOut() async {
        try? await NaviqAPI.logout()
        await NotificationScheduler.shared.cancelAll()
        clearLocal()
    }

    /// Called after account deletion succeeded on the server.
    func accountDeleted() async {
        await NotificationScheduler.shared.cancelAll()
        clearLocal()
        notice = "Your account and data have been deleted."
    }

    func update(_ user: User) { apply(user) }

    func refresh() async {
        if let user = try? await NaviqAPI.me() { apply(user) }
    }

    private func store(_ payload: AuthPayload) {
        Keychain.save(payload.token, account: tokenAccount)
        APIClient.shared.token = payload.token
        notice = nil
        apply(payload.user)
    }

    private func apply(_ user: User) {
        self.user = user
        phase = user.onboardingCompletedAt == nil && !user.isAdmin ? .onboarding : .ready
    }

    private func handleExpiredSession() {
        guard phase != .signedOut else { return }
        clearLocal()
        notice = "Your session ended. Please sign in again."
    }

    private func clearLocal() {
        Keychain.delete(account: tokenAccount)
        APIClient.shared.token = nil
        user = nil
        phase = .signedOut
    }
}
