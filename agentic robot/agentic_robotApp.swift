import SwiftUI
import FirebaseCore

@main
struct agentic_robotApp: App {
    @StateObject var auth = AuthViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
        }
    }
}
