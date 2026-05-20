import SwiftUI

/// The landing screen after login.
/// Admins see "Add Member" and "Report Generation".
/// Members only see "Report Generation".
struct HomeView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var displayedText = ""
    @State private var showButtons = false

    private let fullText = "What do you want to do today?"

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header: Welcome + Logout
            HStack {
                Text("Welcome")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button("Logout") {
                    auth.logout()
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.top)

            Spacer()

            // MARK: - Typewriter prompt, sits right below Welcome
            VStack(spacing: 24) {
                Text(displayedText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // MARK: - Action buttons
                if showButtons {
                    VStack(spacing: 16) {

                        // Admin-only: Add Member (inline create account)
                        if auth.isAdmin {
                            NavigationLink(destination: MemberManagementView()) {
                                Label("Add Member", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }

                        // Everyone: Report Generation
                        NavigationLink(destination: LoggedInView()) {
                            Label("Report Generation", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.12))
                                .foregroundColor(.green)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Spacer()
        }
        .navigationBarHidden(true)
        .onAppear {
            startTypewriter()
        }
    }

    private func startTypewriter() {
        displayedText = ""
        showButtons = false

        Task {
            for char in fullText {
                try? await Task.sleep(for: .milliseconds(40))
                await MainActor.run { displayedText.append(char) }
            }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.4)) {
                    showButtons = true
                }
            }
        }
    }
}
