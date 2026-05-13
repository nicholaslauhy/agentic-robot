//
//  RootView.swift
//  agentic robot
//
//  Created by q2 on 13/5/26.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject var auth: AuthViewModel
    @State private var showRegisterPage = false
    @State private var successMessage: String? = nil

    var body: some View {
        NavigationStack {

            if auth.user != nil {
                LoggedInView(onLogout: {
                    auth.logout()
                })

            } else {
                
                VStack(spacing: 20) {
                    
                    if showRegisterPage {
                        RegisterView(

                            onRegisterSuccess: {
                                auth.errorMessage = nil
                                showRegisterPage = false
                                successMessage = "User successfully created! Please log in with the same credentials."
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
                .navigationTitle("")
            }
        }
    }
}
