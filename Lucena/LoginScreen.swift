import SwiftUI

/// Sign in / sign up — the Annotated Board identity: paper and ink, the rook wordmark, no gradients,
/// no rounded corners. It is a printed form, not a glassy card.
///
/// Deliberately minimal: two fields and one button. Everything else (avatars, "remember me", social
/// buttons) is furniture for a product that has none of those concepts.
struct LoginScreen: View {
    @Environment(\.authClient) private var auth

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focus: Field?

    private enum Mode { case signIn, signUp }
    private enum Field { case email, password }

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            masthead
            form
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.xxxl)
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.desk)
        .onAppear { focus = .email }
    }

    // MARK: - masthead

    private var masthead: some View {
        VStack(spacing: Theme.Spacing.md) {
            // The rook that reads as the L in Lucena.
            Image("logo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .foregroundStyle(Theme.Palette.ink)
            Text(Strings.Auth.wordmark)
                .font(Theme.Typography.serif(34, .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text(Strings.Auth.tagline)
                .font(Theme.Typography.serif(14.5).italic())
                .foregroundStyle(Theme.Palette.ink55)
        }
    }

    // MARK: - form

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            field(Strings.Auth.email, text: $email, field: .email)
            field(Strings.Auth.password, text: $password, field: .password, secure: true)

            if let error {
                Text(verbatim: error)                    // server-supplied, not chrome copy
                    .font(Theme.Typography.serif(13.5))
                    .foregroundStyle(Theme.Palette.mistakeRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            submit
            toggle
        }
        .frame(width: 340)
        .padding(Theme.Spacing.xl)
        .background(Theme.Palette.paper)
        .overlay(Rectangle().stroke(Theme.Palette.ink.opacity(0.3), lineWidth: 1))
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, field f: Field,
                       secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.ink45)
            Group {
                if secure {
                    SecureField("", text: text).onSubmit(go)
                } else {
                    TextField("", text: text)
                        .textContentType(.emailAddress)
                        .onSubmit { focus = .password }
                }
            }
            .textFieldStyle(.plain)
            .font(Theme.Typography.serif(15))
            .foregroundStyle(Theme.Palette.ink)
            .focused($focus, equals: f)
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(Theme.Palette.paperDeep)
            .overlay(Rectangle().stroke(
                focus == f ? Theme.Palette.gold : Theme.Palette.ink22, lineWidth: 1))
        }
    }

    private var submit: some View {
        Button(action: go) {
            HStack(spacing: Theme.Spacing.xs) {
                if busy {
                    ProgressView().controlSize(.small).tint(Theme.Palette.paper)
                }
                Text(busy ? Strings.Auth.working
                          : (mode == .signIn ? Strings.Auth.signIn : Strings.Auth.createAccount))
                    .font(Theme.Typography.serif(15, .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Palette.ink)
            .foregroundStyle(Theme.Palette.paper)
        }
        .buttonStyle(.plain)
        .disabled(busy || email.isEmpty || password.isEmpty)
        .opacity(busy || email.isEmpty || password.isEmpty ? 0.5 : 1)
    }

    private var toggle: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Text(mode == .signIn ? Strings.Auth.noAccountYet : Strings.Auth.haveAnAccount)
                .foregroundStyle(Theme.Palette.ink55)
            Button(mode == .signIn ? Strings.Auth.createOne : Strings.Auth.signIn) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = (mode == .signIn) ? .signUp : .signIn
                    error = nil
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.coachBlue)
            .underline()
        }
        .font(Theme.Typography.serif(13))
        // No "Forgot password?": resetting one needs a reset-token table AND an email provider to send
        // the link, and there is no email integration in the stack. A link that goes nowhere is worse
        // than no link. See RELEASE_CHECKLIST.md.
    }

    // MARK: - action

    private func go() {
        // `auth` is environment-injected and nil-defaulted (the house pattern, so previews can omit
        // it) — a preview of this screen has no client and simply cannot submit.
        guard let auth, !busy, !email.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                if mode == .signIn {
                    try await auth.signIn(email: email, password: password)
                } else {
                    try await auth.signUp(email: email, password: password)
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.error = error.localizedDescription
                }
            }
            busy = false
        }
    }
}
