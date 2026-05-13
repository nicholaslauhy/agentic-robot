import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var shakeTrigger: CGFloat = 0

    var onCreateAccount: () -> Void
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

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Login") {
                if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                    authViewModel.errorMessage = "Please fill in all fields."
                    shakeTrigger += 1;
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

            Button("Create Account") {
                onCreateAccount()
            }
        }
        .padding()
        .modifier(ShakeEffect(animatableData: shakeTrigger))
        .animation(.default, value: shakeTrigger)
    }
}
