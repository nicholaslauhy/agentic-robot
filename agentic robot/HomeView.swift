import SwiftUI

struct HomeView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var displayedText = ""
    @State private var showSubtitle = false
    @State private var showButtons = false
    @State private var typewriterTask: Task<Void, Never>? = nil

    private let fullText = "What do you want to do today?"

    var body: some View {
        VStack(spacing: 24) {

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome")
                        .font(.largeTitle)
                        .bold()

                    Text(auth.isAdmin ? "Administrator" : "Member")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Logout") {
                    auth.logout()
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.top)

            Spacer()

            VStack(spacing: 10) {
                Text(displayedText)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 34)
                    .padding(.horizontal)

                if showSubtitle {
                    Text("Choose an action below to continue.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal)

            if showButtons {
                VStack(spacing: 16) {
                    if auth.isAdmin {
                        NavigationLink {
                            MemberManagementView()
                        } label: {
                            HomeActionRow(
                                icon: "person.badge.plus.fill",
                                title: "Add Member",
                                subtitle: "Create and manage team accounts"
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    NavigationLink {
                        LoggedInView()
                    } label: {
                        HomeActionRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Report Generation",
                            subtitle: "Scan licence plate and generate report"
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .onAppear { startTypewriter() }
        .onDisappear {
            typewriterTask?.cancel()
            typewriterTask = nil
        }
    }

    private func startTypewriter() {
        typewriterTask?.cancel()
        displayedText = ""
        showSubtitle = false
        showButtons = false

        typewriterTask = Task {
            for char in fullText {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(38))
                if Task.isCancelled { return }

                await MainActor.run {
                    displayedText.append(char)
                }
            }

            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(180))

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showSubtitle = true
                }

                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.12)) {
                    showButtons = true
                }
            }
        }
    }
}

private struct HomeActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
