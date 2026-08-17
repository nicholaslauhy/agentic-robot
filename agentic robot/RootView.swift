import SwiftUI

/// Top-level router. Shows Login when logged out, HomeView when logged in.
struct RootView: View {

    @EnvironmentObject var auth: AuthViewModel
    @State private var successMessage: String? = nil

    var body: some View {
        Group {
            if auth.isLoadingRole {
                ProgressView("Loading account…")
                    .tint(HTXTheme.primaryPurple)
            } else if auth.user != nil, auth.profile != nil, auth.role != nil {
                NavigationStack {
                    HomeView()
                }
            } else {
                // No Register flow here — admins add members from within the app
                LoginView(successMessage: $successMessage)
            }
        }
    }
}
