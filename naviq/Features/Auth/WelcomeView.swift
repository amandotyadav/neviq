import SwiftUI

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var mode: AuthMode?

    enum AuthMode: String, Identifiable { case signIn, register; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NaviqWordmark(markSize: 28)
                    .padding(.top, 12)

                Text("Your future,\nbetter navigated.")
                    .heroStyle()
                    .foregroundStyle(NaviqColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 52)

                RouteGraphic(waypoints: 4, completed: 1)
                    .frame(height: 120)
                    .padding(.vertical, 14)

                Text("Scholarships, internships, fellowships and campus notices — checked against official sources and matched to you.")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    point("01", "Discover", "Every listing links to its official source and shows when it was checked.")
                    Hairline()
                    point("02", "Find your direction", "See which criteria you meet, which you don't, and what's unknown.")
                    Hairline()
                    point("03", "Make your next move", "Roadmaps, drafts and deadlines in one place.")
                }
                .padding(.top, 30)

                if let notice = session.notice {
                    NoticeBanner(text: notice, tone: .info).padding(.top, 20)
                }
            }
            .padding(.horizontal, NaviqSpacing.page)
            .padding(.bottom, 24)
        }
        .naviqPage()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                PrimaryAction(title: "Create account") { mode = .register }
                Button("I already have an account") { mode = .signIn }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, NaviqSpacing.page)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background { NaviqColor.paper.ignoresSafeArea() }
            .overlay(alignment: .top) { Hairline() }
        }
        .sheet(item: $mode) { mode in
            AuthFormView(mode: mode)
                .presentationDragIndicator(.visible)
        }
    }

    private func point(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(number).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(NaviqColor.accent).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).itemTitleStyle().foregroundStyle(NaviqColor.ink)
                Text(detail).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
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
