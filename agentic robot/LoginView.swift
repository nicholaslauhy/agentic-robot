import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var shakeTrigger: CGFloat = 0

    @Binding var successMessage: String?

    var body: some View {
        ZStack {
            HTXBackground()

            // Radial glow accent top-right
            RadialGradient(
                colors: [HTXTheme.accentBright.opacity(0.18), .clear],
                center: UnitPoint(x: 0.75, y: 0.15),
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    Spacer().frame(height: 60)

                    // MARK: Logo + Wordmark
                    VStack(spacing: 14) {
                        HTXLogoView(size: 120)
                            .transition(.opacity.combined(with: .scale))

                        Text("HTX")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(8)
                            .foregroundColor(.white)
                            .shadow(color: HTXTheme.accentBright.opacity(0.55), radius: 12)
                    }

                    Spacer().frame(height: 52)

                    // MARK: Login Card
                    HTXCard {
                        VStack(spacing: 20) {

                            if let successMessage {
                                HTXAlert(message: successMessage, isError: false)
                            }

                            if let errorMessage = authViewModel.errorMessage {
                                HTXAlert(message: errorMessage, isError: true)
                            }

                            HTXTextField(
                                label: "Email",
                                placeholder: "Enter your email",
                                text: $email,
                                keyboardType: .emailAddress
                            )

                            HTXSecureField(
                                label: "Password",
                                placeholder: "Enter your password",
                                text: $password,
                                isVisible: $isPasswordVisible
                            )

                            HTXPrimaryButton("LOGIN") {
                                handleLogin()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .modifier(ShakeEffect(animatableData: shakeTrigger))
                    .animation(.default, value: shakeTrigger)

                    Spacer().frame(height: 24)

                    Text("Contact your admin to register")
                        .font(.subheadline)
                        .foregroundColor(HTXTheme.accent.opacity(0.75))

                    Spacer().frame(height: 40)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func handleLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            authViewModel.errorMessage = "Please fill in all fields."
            shakeTrigger += 1
            return
        }

        authViewModel.login(email: trimmedEmail, password: trimmedPassword) { success in
            if success {
                successMessage = nil
            } else {
                shakeTrigger += 1
            }
        }
    }
}
