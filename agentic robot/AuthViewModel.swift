//
//  AuthViewModel.swift
//  agentic robot
//
//  Created by q2 on 12/5/26.
//

import SwiftUI
import Combine
import FirebaseAuth

class AuthViewModel: ObservableObject {

    @Published var user: FirebaseAuth.User?

    init() {
        self.user = Auth.auth().currentUser
    }

    func login(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in

            if let user = result?.user {
                DispatchQueue.main.async {
                    self.user = user
                }
            }
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        user = nil
    }
}
