import SwiftUI

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var mode: AuthMode?

    enum AuthMode: String, Identifiable { case signIn, register; var id: String { rawValue } }

    var body: some View {
        ZStack {
            NaviqColor.heroGradient.ignoresSafeArea()
            Circle().fill(.white.opacity(0.10)).frame(width: 340).offset(x: 150, y: -300)
            Circle().fill(NaviqColor.sunny.opacity(0.25)).frame(width: 220).offset(x: -170, y: 330)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        NaviqMark(size: 30, ink: .white, accent: NaviqColor.sunny)
                        Text("naviq").font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Naviq")
                    .padding(.top, NaviqSpacing.xl)

                    Spacer(minLength: 24)

                    Text("Your future,\nbetter navigated.")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)

                    Text("Scholarships, internships, fellowships and campus notices — checked against official sources, matched to you, and turned into a plan.")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, NaviqSpacing.l)

                    VStack(spacing: NaviqSpacing.m) {
                        promise("magnifyingglass", NaviqColor.sunny, "Discover", "Verified opportunities with their official source.")
                        promise("safari.fill", NaviqColor.mint, "Find your direction", "See what you meet, what you're missing, and why.")
                        promise("bolt.fill", NaviqColor.blush, "Make your next move", "Roadmaps, drafts, and deadlines in one place.")
                    }
                    .padding(.top, NaviqSpacing.xl)

                    if let notice = session.notice {
                        NoticeBanner(text: notice, tone: .info).padding(.top, NaviqSpacing.xl)
                    }

                }
                .padding(.horizontal, NaviqSpacing.page)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: NaviqSpacing.m) {
                        Button { mode = .register } label: {
                            Text("Create your account")
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(Color(UIColor(hex: 0x17153B)))
                                .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NaviqColor.sunny) }
                        }
                        Button { mode = .signIn } label: {
                            Text("I already have an account")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(.white)
                                .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.18)) }
                        }
                    }
            .padding(.horizontal, NaviqSpacing.page)
            .padding(.top, NaviqSpacing.m)
            .padding(.bottom, NaviqSpacing.s)
        }
        .sheet(item: $mode) { mode in
            AuthFormView(mode: mode)
                .presentationDragIndicator(.visible)
        }
    }

    private func promise(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: NaviqSpacing.m) {
            IconBadge(systemImage: symbol, fill: color, foreground: Color(UIColor(hex: 0x17153B)), size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                Text(detail).font(.system(.subheadline, design: .rounded)).foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(NaviqSpacing.m)
        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.14)) }
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
                    .buttonStyle(PrimaryButtonStyle())
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
