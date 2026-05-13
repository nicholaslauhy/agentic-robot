//
//  RegisterView.swift
//  agentic robot
//
//  Created by q2 on 13/5/26.
//

import SwiftUI

struct RegisterView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var email = ""
    @State private var password = ""

    var onRegisterSuccess: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                Text("Create Account")
                    .font(.largeTitle)

                TextField("Type your email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .padding(.horizontal)

                SecureField("Type your password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .padding(.horizontal)

                Button("Register") {
                    if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                        auth.errorMessage = "Please fill in all fields."
                        return
                    }

                    auth.register(email: email, password: password) { success in

                        if success {
                            onRegisterSuccess()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Cancel"){
                    onCancel()
                }
                .foregroundColor(.red)
                .padding(.top, 5)

                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding(.top, 5)
                }
            }
            .padding()
        }
        .onTapGesture {
            // Dismiss the keyboard when tapping outside
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}



