//
//  AuthView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import Observation
import UIKit

private enum AuthField: Hashable {
    case email
    case password
    case displayName
}

struct AuthView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"

        var id: String { rawValue }
    }

    @Environment(AuthService.self) private var authService
    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var displayName: String = ""
    @State private var showPassword: Bool = false
    @FocusState private var focusedField: AuthField?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        guard trimmedEmail.isValidEmail && trimmedPassword.count >= 6 else {
            return false
        }

        if mode == .signUp {
            return !trimmedDisplayName.isEmpty
        }

        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = mode == .signUp ? .displayName : .password
                        }

                    if mode == .signUp {
                        TextField("Display Name", text: $displayName)
                            .textInputAutocapitalization(.words)
                            .textContentType(.name)
                            .focused($focusedField, equals: .displayName)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                    }

                    SecureFieldView(
                        title: "Password",
                        text: $password,
                        showPassword: $showPassword,
                        focusedField: _focusedField,
                        field: .password
                    )
                    .submitLabel(.go)
                    .onSubmit(performSubmit)
                }

                Button(action: performSubmit) {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid || authService.isLoading)

                DividerWithLabel(label: "or continue with")

                Button(action: presentGoogleSignIn) {
                    HStack(spacing: 12) {
                        Image(systemName: "g.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.primary)

                        Text("Sign In with Google")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .disabled(authService.isLoading)

                VStack(spacing: 8) {
                    Text("Password must be at least 6 characters.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if mode == .signUp {
                        Text("Display name appears to other users in chats.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("MessageAI")
        }
        .alert(
            "Authentication Error",
            isPresented: .init(
                get: { authService.errorMessage != nil },
                set: { if !$0 { authService.errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    authService.errorMessage = nil
                }
            },
            message: {
                Text(authService.errorMessage ?? "Unknown error")
            }
        )
    }

    private func performSubmit() {
        guard isFormValid else { return }
        focusedField = nil

        Task {
            switch mode {
            case .signIn:
                await authService.signIn(email: trimmedEmail.lowercased(), password: trimmedPassword)
            case .signUp:
                await authService.signUp(
                    email: trimmedEmail.lowercased(),
                    password: trimmedPassword,
                    displayName: trimmedDisplayName
                )
            }
        }
    }

    private func presentGoogleSignIn() {
        Task { @MainActor in
            guard let controller = findTopViewController() else {
                authService.errorMessage = "Unable to present Google Sign-In UI."
                return
            }
            await authService.signInWithGoogle(presentingViewController: controller)
        }
    }
}

private struct SecureFieldView: View {
    let title: String
    @Binding var text: String
    @Binding var showPassword: Bool
    @FocusState<AuthField?> var focusedField: AuthField?
    let field: AuthField

    var body: some View {
        HStack {
            if showPassword {
                TextField(title, text: $text)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                    .focused($focusedField, equals: field)
            } else {
                SecureField(title, text: $text)
                    .textContentType(.password)
                    .focused($focusedField, equals: field)
            }

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }
    }
}

private struct DividerWithLabel: View {
    let label: String

    var body: some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.secondary.opacity(0.3))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.secondary.opacity(0.3))
        }
    }
}

private extension String {
    var isValidEmail: Bool {
        guard !isEmpty else { return false }
        let pattern = #"^\S+@\S+\.\S+$"#
        return range(of: pattern, options: .regularExpression) != nil
    }
}

@MainActor
private func findTopViewController() -> UIViewController? {
    guard
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else {
        return nil
    }

    return root.topMostViewController()
}

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        if let navigation = self as? UINavigationController,
           let visible = navigation.visibleViewController {
            return visible.topMostViewController()
        }
        if let tab = self as? UITabBarController,
           let selected = tab.selectedViewController {
            return selected.topMostViewController()
        }
        return self
    }
}
