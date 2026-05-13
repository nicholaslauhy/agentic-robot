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
    @State private var shakeTrigger: CGFloat = 0

    var onRegisterSuccess: () -> Void
    var onCancel: () -> Void

    var body: some View {

        VStack(spacing: 20) {

            // HEADER
            Text("Create Account")
                .font(.largeTitle)
                .bold()

            // ERROR MESSAGE
            if let errorMessage = auth.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // EMAIL FIELD
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .padding(.horizontal)

            // PASSWORD FIELD
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            // REGISTER BUTTON
            Button("Register") {

                if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                    auth.errorMessage = "Please fill in all fields."
                    shakeTrigger += 1
                    return
                }

                auth.register(email: email, password: password) { success in

                    if success {
                        onRegisterSuccess()
                    } else {
                        shakeTrigger += 1
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            // CANCEL BUTTON
            Button("Cancel") {
                onCancel()
            }
            .foregroundColor(.red)
        }
        .padding()
        .modifier(ShakeEffect(animatableData: shakeTrigger))
        .animation(.default, value: shakeTrigger)
    }
}



