import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    var onCreateAccount: () -> Void

    var body: some View {
        VStack {

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .padding()

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Login") {
                authViewModel.login(email: email, password: password) { _ in }
            }
            .padding()

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage).foregroundColor(.red)
            }

            Button("Create Account") {
                onCreateAccount()
            }
        }
        .padding()
    }
}
