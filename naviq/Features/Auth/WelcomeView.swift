import SwiftUI

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var mode: AuthMode?

    enum AuthMode: String, Identifiable { case signIn, register; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NaviqWordmark(markSize: 30)
                    .padding(.top, NaviqSpacing.xl)

                Spacer(minLength: 56)

                Text("Your future,\nbetter navigated.")
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(NaviqColor.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("Scholarships, internships, fellowships and campus notices — checked against official sources, matched to you, and turned into a plan.")
                    .font(.title3)
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .padding(.top, NaviqSpacing.l)

                VStack(alignment: .leading, spacing: NaviqSpacing.m) {
                    promise("01", "Discover", "Verified opportunities with their official source.")
                    promise("02", "Find your direction", "See what you meet, what you're missing, and why.")
                    promise("03", "Make your next move", "Roadmaps, drafts, and deadlines in one place.")
                }
                .padding(.top, NaviqSpacing.xxl)

                if let notice = session.notice {
                    NoticeBanner(text: notice, tone: .info).padding(.top, NaviqSpacing.xl)
                }

                VStack(spacing: NaviqSpacing.m) {
                    Button("Create your account") { mode = .register }
                        .buttonStyle(PrimaryButtonStyle(tint: NaviqColor.ink))
                    Button("I already have an account") { mode = .signIn }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, NaviqSpacing.xxl)
                .padding(.bottom, NaviqSpacing.xl)
            }
            .padding(.horizontal, NaviqSpacing.page)
        }
        .naviqPage()
        .sheet(item: $mode) { mode in
            AuthFormView(mode: mode)
                .presentationDragIndicator(.visible)
        }
    }

    private func promise(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NaviqSpacing.m) {
            Text(number)
                .font(.system(.footnote, design: .serif).weight(.bold).monospacedDigit())
                .foregroundStyle(NaviqColor.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(NaviqColor.ink)
                Text(detail).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AuthFormView: View {
    let mode: WelcomeView.AuthMode
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var error: APIError?
    @FocusState private var focus: Field?

    enum Field { case name, email, password }

    private var isRegister: Bool { mode == .register }
    private var canSubmit: Bool {
        email.contains("@") && password.count >= (isRegister ? 8 : 1) && (!isRegister || !name.trimmed.isEmpty) && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NaviqSpacing.l) {
                    Text(isRegister ? "Create your account" : "Welcome back")
                        .font(NaviqFont.title)
                        .foregroundStyle(NaviqColor.ink)
                    Text(isRegister ? "Any email works — you don't need a college email address." : "Sign in to continue where you left off.")
                        .foregroundStyle(NaviqColor.inkSecondary)

                    if isRegister {
                        LabeledField(label: "Your name", error: error?.fieldMessage("name")) {
                            TextField("Full name", text: $name)
                                .textContentType(.name)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .email }
                        }
                    }
                    LabeledField(label: "Email", error: error?.fieldMessage("email")) {
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                    LabeledField(label: "Password", hint: isRegister ? "At least 8 characters." : nil, error: error?.fieldMessage("password")) {
                        SecureField("Password", text: $password)
                            .textContentType(isRegister ? .newPassword : .password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { if canSubmit { submit() } }
                    }

                    if let error, error.fieldMessage("email") == nil, error.fieldMessage("password") == nil, error.fieldMessage("name") == nil {
                        NoticeBanner(text: error.localizedDescription)
                    }

                    Button {
                        submit()
                    } label: {
                        if isSubmitting { ProgressView().tint(NaviqColor.onAccent) } else { Text(isRegister ? "Create account" : "Sign in") }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: NaviqColor.ink))
                    .disabled(!canSubmit)
                    .padding(.top, NaviqSpacing.s)

                    if isRegister {
                        Text("Naviq stores your profile to personalise matches. You can edit or delete it any time in Settings.")
                            .font(.footnote)
                            .foregroundStyle(NaviqColor.inkTertiary)
                    }
                }
                .padding(NaviqSpacing.page)
            }
            .scrollDismissesKeyboard(.interactively)
            .naviqPage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focus = isRegister ? .name : .email }
        }
    }

    private func submit() {
        isSubmitting = true
        error = nil
        Task {
            do {
                if isRegister {
                    try await session.register(name: name.trimmed, email: email.trimmed, password: password)
                } else {
                    try await session.signIn(email: email.trimmed, password: password)
                }
                Haptics.success()
            } catch let e as APIError {
                error = e
                Haptics.warning()
            } catch {
                self.error = .network(error.localizedDescription)
            }
            isSubmitting = false
        }
    }
}
