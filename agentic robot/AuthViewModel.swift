import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine
import UIKit

class AuthViewModel: ObservableObject {

    @Published var user: FirebaseAuth.User?
    @Published var role: String? // "admin" or "member"
    @Published var errorMessage: String?
    @Published var didShowIntroAnimation = false

    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {

        // Force logout on fresh app launch
        try? Auth.auth().signOut()

        self.user = nil
        self.role = nil

        self.authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in

            DispatchQueue.main.async {
                self?.user = user
            }
        }
    }

    deinit {

        if let authStateListener = authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    // MARK: - Role Fetch

    func fetchRole(for uid: String, completion: @escaping () -> Void) {

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument { [weak self] snapshot, error in

                DispatchQueue.main.async {

                    guard let data = snapshot?.data() else {

                        self?.role = nil
                        completion()
                        return
                    }

                    let active = data["active"] as? Bool ?? false
                    let role = data["role"] as? String ?? "member"

                    // BLOCK inactive users
                    if active == false {

                        do {
                            try Auth.auth().signOut()
                        } catch { }

                        self?.user = nil
                        self?.role = nil
                        self?.errorMessage = "Your account has been deactivated."

                        completion()
                        return
                    }

                    self?.role = role
                    completion()
                }
            }
    }

    var isAdmin: Bool {
        role == "admin"
    }

    // MARK: - Error Mapping

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

    // MARK: - Haptics

    private func triggerErrorHaptic() {

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - Login

    func login(email: String,
               password: String,
               completion: @escaping (Bool) -> Void) {

        errorMessage = nil

        Auth.auth().signIn(withEmail: email, password: password) { result, error in

            DispatchQueue.main.async {

                // Firebase login failed
                if let error = error {

                    self.errorMessage = self.mapAuthError(error)
                    self.triggerErrorHaptic()

                    completion(false)

                    return
                }

                // Missing user
                guard let user = result?.user else {

                    self.errorMessage = "Could not retrieve user account."
                    self.triggerErrorHaptic()

                    completion(false)

                    return
                }

                // Temporarily store user
                self.user = user

                // Fetch Firestore role + active state
                self.fetchRole(for: user.uid) {

                    // User got signed out because inactive
                    guard Auth.auth().currentUser != nil else {

                        self.triggerErrorHaptic()
                        completion(false)

                        return
                    }

                    self.errorMessage = nil
                    completion(true)
                }
            }
        }
    }

    // MARK: - Register

    func register(email: String,
                  password: String,
                  completion: @escaping (Bool) -> Void) {

        Auth.auth().createUser(withEmail: email, password: password) { result, error in

            DispatchQueue.main.async {

                if let newUser = result?.user {

                    Firestore.firestore()
                        .collection("users")
                        .document(newUser.uid)
                        .setData([
                            "role": "member",
                            "email": email,
                            "active": true
                        ]) { _ in

                            do {

                                try Auth.auth().signOut()

                            } catch {

                                self.errorMessage = "Failed to sign out after registration."

                                completion(false)

                                return
                            }

                            self.user = nil
                            self.role = nil
                            self.errorMessage = nil

                            completion(true)
                        }

                } else {

                    self.errorMessage = self.mapAuthError(error)
                    self.triggerErrorHaptic()

                    completion(false)
                }
            }
        }
    }

    // MARK: - Logout

    func logout() {

        try? Auth.auth().signOut()

        user = nil
        role = nil
        errorMessage = nil
        didShowIntroAnimation = false
    }
}
