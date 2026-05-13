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
    
    private func mapAuthError(_ error: Error?) -> String {

        let nsError = error as NSError?

        let defaultMessage = "Something went wrong. Please try again!"

        guard let code = nsError?.code else {
            return defaultMessage
        }

        switch code {
            
        case AuthErrorCode.wrongPassword.rawValue,
             AuthErrorCode.invalidCredential.rawValue,
             AuthErrorCode.userNotFound.rawValue:
            return "Incorrect username/password. Please try again!"

        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "This email is already in use."

        case AuthErrorCode.weakPassword.rawValue:
            return "Password should be at least 6 characters."

        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address."

        default:
            return defaultMessage
        }
    }

    func login(email: String, password: String, completion: @escaping (Bool) -> Void) {

        Auth.auth().signIn(withEmail: email, password: password) { result, error in

            DispatchQueue.main.async {

                if let user = result?.user {
                    self.user = user
                    self.errorMessage = nil
                    completion(true)

                } else {
                    self.errorMessage = self.mapAuthError(error)
                    completion(false)
                }
            }
        }
    }

    func register(email: String, password: String, completion: @escaping (Bool) -> Void) {

        Auth.auth().createUser(withEmail: email, password: password) { result, error in

            DispatchQueue.main.async {

                if let user = result?.user {
                    self.user = user
                    self.errorMessage = nil
                    completion(true)

                } else {
                    self.errorMessage = self.mapAuthError(error)
                    completion(false)
                }
            }
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        user = nil
    }
}
