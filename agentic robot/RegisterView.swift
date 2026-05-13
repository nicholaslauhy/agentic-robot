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

    var onAccountCreated: () -> Void // Closure to handle navigation after account creation

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                Text("Create Account")
                    .font(.largeTitle)

                TextField("Type your email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)

                SecureField("Type your password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button("Register") {
                    auth.register(email: email, password: password)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if auth.errorMessage == nil {
                            onAccountCreated()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
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



