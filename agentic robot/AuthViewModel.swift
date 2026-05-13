import SwiftUI
import FirebaseAuth
import Combine

class AuthViewModel: ObservableObject {

    @Published var user: FirebaseAuth.User?
    @Published var errorMessage: String? // Published property for error messages

    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        self.authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user // Update user when authentication state changes
            }
        }
    }

    deinit {
        if let authStateListener = authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            DispatchQueue.main.async {
                if let user = result?.user {
                    self.user = user
                    self.errorMessage = nil // Clear error message on success
                    completion(true)
                } else {
                    self.errorMessage = error?.localizedDescription // Set error message
                    completion(false)
                }
            }
        }
    }

    func register(email: String, password: String) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            DispatchQueue.main.async {
                if let user = result?.user {
                    self.user = user
                    self.errorMessage = nil // Clear error message on success
                } else {
                    if let error = error {
                        print("Registration error: \(error.localizedDescription)") // Print error details
                    }
                    self.errorMessage = error?.localizedDescription // Set error message
                }
            }
        }
    }


    func logout() {
        try? Auth.auth().signOut()
        user = nil
    }
}
