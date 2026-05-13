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
                    
                    Text("Login")
                        .font(.largeTitle)
                        .bold()
                    
                    if let msg = successMessage {
                        Text(msg)
                            .foregroundColor(.green)
                    }
                    
                    if showRegisterPage {
                        RegisterView(

                            onRegisterSuccess: {
                                showRegisterPage = false
                                successMessage = "User successfully created!"
                            },

                            onCancel: {
                                showRegisterPage = false
                                successMessage = nil
                            }
                        )
                    } else {
                        LoginView(
                            onCreateAccount: {
                                showRegisterPage = true
                                successMessage = nil
                            }
                        )
                    }
                }
                .navigationTitle("")
            }
        }
    }
}
