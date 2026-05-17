import SwiftUI
import FirebaseAuth
import Combine
import UIKit

class AuthViewModel: ObservableObject {

    @Published var user: FirebaseAuth.User?
    @Published var errorMessage: String?
    @Published var didShowIntroAnimation = false

    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        // FirebaseAuth remembers the previous logged-in user across app launches by default.
        // Force sign-out on app start so every fresh run starts from the login screen.
        try? Auth.auth().signOut()
        self.user = nil

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
    
    private func triggerErrorHaptic() {

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
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
                    self.triggerErrorHaptic()
                    completion(false)
                }
            }
        }
    }

    func register(email: String, password: String, completion: @escaping (Bool) -> Void) {

        Auth.auth().createUser(withEmail: email, password: password) { result, error in

            DispatchQueue.main.async {

                if result?.user != nil {

                    do {
                        try Auth.auth().signOut()
                    } catch {
                        self.errorMessage = "Failed to sign out after registration."
                        completion(false)
                        return
                    }

                    self.user = nil
                    self.errorMessage = nil

                    completion(true)
                } else {
                    self.errorMessage = self.mapAuthError(error)
                    self.triggerErrorHaptic()
                    completion(false)
                }
            }
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        user = nil
        didShowIntroAnimation = false
    }
}
