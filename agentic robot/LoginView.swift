//
//  LoginView.swift
//  agentic robot
//
//  Created by q2 on 12/5/26.
//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {

            Text("Login")
                .font(.largeTitle)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button("Login") {
                auth.login(email: email, password: password)
            }
        }
        .padding()
    }
}
