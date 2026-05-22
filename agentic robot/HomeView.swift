import SwiftUI

struct HomeView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var displayedText = ""
    @State private var showButtons = false
    @State private var goToMembers = false
    @State private var goToReportGeneration = false

    private let fullText = "What do you want to do today?"

    var body: some View {
        ZStack {
            HTXBackground()

            VStack(spacing: 0) {
                HTXScreenHeader(
                    title: "Welcome",
                    subtitle: auth.isAdmin ? "Administrator Console" : "Operations Member",
                    trailing: AnyView(HTXLogoutButton { auth.logout() })
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    HTXLogoView(size: 96)

                    Text("HTX")
                        .font(.system(size: 30, weight: .black, design: .default))
                        .tracking(7)
                        .foregroundColor(.white)
                        .shadow(color: HTXTheme.accentBright.opacity(0.55), radius: 12)
                }

                Spacer().frame(height: 34)

                Text(displayedText)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(minHeight: 32)

                Spacer().frame(height: 34)

                if showButtons {
                    VStack(spacing: 14) {
                        if auth.isAdmin {
                            Button {
                                goToMembers = true
                            } label: {
                                HTXHomeCard(
                                    icon: "person.badge.plus.fill",
                                    title: "Add Member",
                                    subtitle: "Create, activate, and manage accounts",
                                    color: HTXTheme.accentBright
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            goToReportGeneration = true
                        } label: {
                            HTXHomeCard(
                                icon: "doc.text.viewfinder",
                                title: "Report Generation",
                                subtitle: "Scan licence plate and analyse damage",
                                color: HTXTheme.cyan
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 24)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $goToMembers) {
            MemberManagementView()
                .environmentObject(auth)
        }
        .navigationDestination(isPresented: $goToReportGeneration) {
            LoggedInView()
                .environmentObject(auth)
        }
        .onAppear { startTypewriter() }
    }

    private func startTypewriter() {
        displayedText = ""
        showButtons = false

        Task {
            for char in fullText {
                try? await Task.sleep(for: .milliseconds(32))
                await MainActor.run { displayedText.append(char) }
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    showButtons = true
                }
            }
        }
    }
}

// MARK: - Home Action Card
struct HTXHomeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.38), color.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(color.opacity(0.55), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(HTXTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(18)
        .background(Color.white.opacity(isPressed ? 0.17 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), color.opacity(0.44)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: color.opacity(0.16), radius: 15, y: 8)
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.spring(response: 0.24), value: isPressed)
    }
}
