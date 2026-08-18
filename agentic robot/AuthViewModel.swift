import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine
import UIKit

struct UserProfile: Equatable {
    let uid: String
    let email: String
    let username: String
    let role: String
    let active: Bool

    var hasUsername: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class AuthViewModel: ObservableObject {

    @Published var user: FirebaseAuth.User?
    @Published var profile: UserProfile?
    @Published var role: String?
    @Published var isLoadingRole = true
    @Published var errorMessage: String?
    @Published var didShowIntroAnimation = false

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var profileListener: ListenerRegistration?
    private var observedProfileUID: String?
    private var pendingLoginCompletion: ((Bool) -> Void)?

    init() {
        // Firebase Authentication restores its persisted session automatically.
        // Keep the app in its loading state until the auth listener has told us
        // whether a user exists and, when one does, their Firestore profile has
        // also been resolved.
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.handleAuthStateChange(user)
            }
        }
    }

    deinit {
        profileListener?.remove()
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    var isAdmin: Bool {
        role == RequiredAppRole.admin.rawValue
    }

    var isMember: Bool {
        role == RequiredAppRole.member.rawValue
    }

    var currentUsername: String {
        profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var currentEmail: String {
        profile?.email ?? user?.email ?? ""
    }

    var hasUsername: Bool {
        profile?.hasUsername == true
    }

    private static func normalizedRole(from rawRole: String?) -> String? {
        let normalized = rawRole?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized == RequiredAppRole.admin.rawValue ||
                normalized == RequiredAppRole.member.rawValue else {
            return nil
        }
        return normalized
    }

    private func handleAuthStateChange(_ newUser: FirebaseAuth.User?) {
        user = newUser

        guard let newUser else {
            stopObservingProfile()
            profile = nil
            role = nil
            isLoadingRole = false
            return
        }

        observeProfile(for: newUser)
    }

    private func observeProfile(for firebaseUser: FirebaseAuth.User) {
        if observedProfileUID == firebaseUser.uid, profileListener != nil {
            return
        }

        stopObservingProfile()
        observedProfileUID = firebaseUser.uid
        isLoadingRole = true

        profileListener = Firestore.firestore()
            .collection("users")
            .document(firebaseUser.uid)
            .addSnapshotListener { [weak self, weak firebaseUser] snapshot, error in
                DispatchQueue.main.async {
                    guard let self, let firebaseUser else { return }

                    if let error {
                        self.rejectCurrentSession(
                            message: "Could not load your account profile: \(error.localizedDescription)"
                        )
                        return
                    }

                    guard let data = snapshot?.data() else {
                        self.rejectCurrentSession(
                            message: "Your account profile is missing. Please contact an administrator."
                        )
                        return
                    }

                    let active = data["active"] as? Bool ?? true
                    guard active else {
                        self.rejectCurrentSession(message: "Your account has been deactivated.")
                        return
                    }

                    guard let resolvedRole = Self.normalizedRole(from: data["role"] as? String) else {
                        self.rejectCurrentSession(
                            message: "Your account does not have a valid role. Please contact an administrator."
                        )
                        return
                    }
                    let resolvedEmail = (data["email"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedUsername = Self.profileUsername(from: data)

                    self.user = firebaseUser
                    self.role = resolvedRole
                    self.profile = UserProfile(
                        uid: firebaseUser.uid,
                        email: resolvedEmail?.isEmpty == false
                            ? resolvedEmail!
                            : (firebaseUser.email ?? ""),
                        username: resolvedUsername,
                        role: resolvedRole,
                        active: true
                    )
                    self.isLoadingRole = false
                    self.errorMessage = nil
                    self.syncFirebaseDisplayName(resolvedUsername, for: firebaseUser)
                    if resolvedRole == RequiredAppRole.admin.rawValue {
                        AdminNotificationService.shared.beginAdminSession(uid: firebaseUser.uid)
                    } else {
                        AdminNotificationService.shared.endSession()
                    }
                    self.finishPendingLogin(success: true)
                }
            }
    }

    private static func profileUsername(from data: [String: Any]) -> String {
        let candidates = [
            data["username"] as? String,
            data["displayName"] as? String,
            data["name"] as? String
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private func syncFirebaseDisplayName(_ username: String, for firebaseUser: FirebaseAuth.User) {
        guard !username.isEmpty, firebaseUser.displayName != username else { return }
        let changeRequest = firebaseUser.createProfileChangeRequest()
        changeRequest.displayName = username
        changeRequest.commitChanges { error in
            if let error {
                print("Could not sync Firebase display name: \(error.localizedDescription)")
            }
        }
    }

    private func rejectCurrentSession(message: String) {
        errorMessage = message
        isLoadingRole = false
        finishPendingLogin(success: false)
        try? Auth.auth().signOut()
        user = nil
        profile = nil
        role = nil
        stopObservingProfile()
        triggerErrorHaptic()
    }

    private func stopObservingProfile() {
        profileListener?.remove()
        profileListener = nil
        observedProfileUID = nil
    }

    private func finishPendingLogin(success: Bool) {
        let completion = pendingLoginCompletion
        pendingLoginCompletion = nil
        completion?(success)
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
            return "Incorrect email or password. Please try again."
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

    // MARK: - Login

    func login(
        email: String,
        password: String,
        completion: @escaping (Bool) -> Void
    ) {
        errorMessage = nil
        isLoadingRole = true
        pendingLoginCompletion = completion

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.errorMessage = self.mapAuthError(error)
                    self.isLoadingRole = false
                    self.triggerErrorHaptic()
                    self.finishPendingLogin(success: false)
                    return
                }

                guard let firebaseUser = result?.user else {
                    self.errorMessage = "Could not retrieve user account."
                    self.isLoadingRole = false
                    self.triggerErrorHaptic()
                    self.finishPendingLogin(success: false)
                    return
                }

                self.user = firebaseUser
                self.observeProfile(for: firebaseUser)
            }
        }
    }

    // MARK: - Register

    func register(
        email: String,
        password: String,
        username: String = "",
        completion: @escaping (Bool) -> Void
    ) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let newUser = result?.user {
                    Firestore.firestore()
                        .collection("users")
                        .document(newUser.uid)
                        .setData([
                            "role": "member",
                            "email": email,
                            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
                            "active": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "updatedAt": FieldValue.serverTimestamp()
                        ]) { _ in
                            do {
                                try Auth.auth().signOut()
                            } catch {
                                self.errorMessage = "Failed to sign out after registration."
                                completion(false)
                                return
                            }

                            self.user = nil
                            self.profile = nil
                            self.role = nil
                            self.errorMessage = nil
                            self.isLoadingRole = false
                            completion(true)
                        }
                } else {
                    self.errorMessage = self.mapAuthError(error)
                    self.isLoadingRole = false
                    self.triggerErrorHaptic()
                    completion(false)
                }
            }
        }
    }

    // MARK: - Logout

    func logout() {
        pendingLoginCompletion = nil
        AdminNotificationService.shared.endSession()
        stopObservingProfile()
        try? Auth.auth().signOut()
        user = nil
        profile = nil
        role = nil
        isLoadingRole = false
        errorMessage = nil
        didShowIntroAnimation = false
    }
}
