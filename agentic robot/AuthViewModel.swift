import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine
import UIKit

class AuthViewModel: ObservableObject {

    @Published var user: FirebaseAuth.User?
    @Published var role: String?           // "admin" or "member"
    @Published var isLoadingRole: Bool = false   // ← NEW: true while Firestore fetch is in flight
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

        isLoadingRole = true   // ← signal that role is not yet confirmed

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument { [weak self] snapshot, error in

                DispatchQueue.main.async {

                    guard let self else { completion(); return }

                    defer { self.isLoadingRole = false }   // ← always clear the flag

                    guard let data = snapshot?.data() else {
                        self.role = nil
                        completion()
                        return
                    }

                    let active = data["active"] as? Bool ?? false
                    let role = Self.normalizedRole(from: data["role"] as? String)

                    // Block inactive users
                    if active == false {
                        try? Auth.auth().signOut()
                        self.user = nil
                        self.role = nil
                        self.errorMessage = "Your account has been deactivated."
                        completion()
                        return
                    }

                    self.role = role
                    completion()
                }
            }
    }

    // @Published role drives this — SwiftUI will re-render any view
    // reading isAdmin whenever role changes.
    var isAdmin: Bool {
        Self.normalizedRole(from: role) == "admin"
    }

    private static func normalizedRole(from rawRole: String?) -> String {
        rawRole?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "member"
    }

    // MARK: - Error Mapping

    private func mapAuthError(_ error: Error?) -> String {

        let nsError = error as NSError?
        let defaultMessage = "Something went wrong. Please try again!"
        guard let code = nsError?.code else { return defaultMessage }

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

                if let error = error {
                    self.errorMessage = self.mapAuthError(error)
                    self.triggerErrorHaptic()
                    completion(false)
                    return
                }

                guard let user = result?.user else {
                    self.errorMessage = "Could not retrieve user account."
                    self.triggerErrorHaptic()
                    completion(false)
                    return
                }

                self.user = user

                self.fetchRole(for: user.uid) {
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
                            "role":   "member",
                            "email":  email,
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
        isLoadingRole = false
        errorMessage = nil
        didShowIntroAnimation = false
    }
}
