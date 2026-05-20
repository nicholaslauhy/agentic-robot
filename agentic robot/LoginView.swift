import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var shakeTrigger: CGFloat = 0

    // onCreateAccount removed — admins create accounts from HomeView
    @Binding var successMessage: String?

    var body: some View {
        VStack(spacing: 20) {

            Text("Login")
                .font(.largeTitle)
                .bold()

            if let successMessage = successMessage {
                Text(successMessage)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .padding()

            HStack {
                Group {
                    if isPasswordVisible {
                        TextField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Password", text: $password)
                    }
                }

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .padding()

            Button("Login") {
                if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    authViewModel.errorMessage = "Please fill in all fields."
                    shakeTrigger += 1
                    return
                }

                authViewModel.login(email: email, password: password) { success in
                    if success {
                        successMessage = nil
                    } else {
                        shakeTrigger += 1
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            // "Create Account" button intentionally removed.
            // Only admins can create accounts, from the home screen.
        }
        .padding()
        .modifier(ShakeEffect(animatableData: shakeTrigger))
        .animation(.default, value: shakeTrigger)
    }
}
