import SwiftUI

struct RootView: View {

    @EnvironmentObject var auth: AuthViewModel
    @State private var showRegisterPage = false
    @State private var successMessage: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                
                if auth.user != nil {
                    LoggedInView()
                        .environmentObject(auth)
                } else {
                    
                    VStack(spacing: 20) {
                        
                        if showRegisterPage {
                            
                            RegisterView(
                                onRegisterSuccess: {
                                    auth.errorMessage = nil
                                    showRegisterPage = false
                                    successMessage = "User successfully created! Please log in."
                                },
                                onCancel: {
                                    auth.errorMessage = nil
                                    showRegisterPage = false
                                    successMessage = nil
                                }
                            )
                            
                        } else {
                            
                            LoginView(
                                onCreateAccount: {
                                    auth.errorMessage = nil
                                    showRegisterPage = true
                                    successMessage = nil
                                },
                                successMessage: $successMessage
                            )
                        }
                    }
                }
            }
        }
    }
}
