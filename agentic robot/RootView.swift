import SwiftUI

/// Top-level router. Shows Login when logged out, HomeView when logged in.
struct RootView: View {

    @EnvironmentObject var auth: AuthViewModel
    @State private var successMessage: String? = nil

    var body: some View {
        Group {
            if auth.user != nil {
                if auth.isLoadingRole || auth.role == nil {
                    ProgressView("Loading account…")
                        .tint(HTXTheme.primaryPurple)
                } else {
                    NavigationStack {
                        HomeView()
                    }
                }
            } else {
                // No Register flow here — admins add members from within the app
                LoginView(successMessage: $successMessage)
            }
        }
    }
}
