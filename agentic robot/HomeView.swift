import SwiftUI

struct HomeView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var displayedText = ""
    @State private var showSubtitle = false
    @State private var showButtons = false
    @State private var typewriterTask: Task<Void, Never>? = nil

    private let fullText = "What do you want to do today?"

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            VStack(spacing: 24) {

                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(HTXTheme.primaryPurple)

                        Text(auth.isAdmin ? "Administrator" : "Member")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Logout") {
                        auth.logout()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.top)

                Spacer()

                // MARK: - Typewriter
                VStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(HTXTheme.primaryPurple)
                        .padding(.bottom, 4)

                    Text(displayedText)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
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

                // MARK: - Action Buttons
                if showButtons {
                    VStack(spacing: 14) {

                        // Admin only: Add Member
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

                        // Everyone: Report Generation
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

                        // Everyone: Scan Barcode
                        NavigationLink {
                            ReportScannerView()
                        } label: {
                            HomeActionRow(
                                icon: "barcode.viewfinder",
                                title: "Scan Report Barcode",
                                subtitle: "Point camera at a report barcode"
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        // Everyone: View All Reports
                        NavigationLink {
                            ReportsListView()
                        } label: {
                            HomeActionRow(
                                icon: "folder.fill",
                                title: "View Existing Reports",
                                subtitle: "Browse and search all generated reports"
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .tint(HTXTheme.primaryPurple)
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
                await MainActor.run { displayedText.append(char) }
            }

            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(180))

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) { showSubtitle = true }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.12)) {
                    showButtons = true
                }
            }
        }
    }
}

// MARK: - Shared Action Row
private struct HomeActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: [HTXTheme.primaryPurple, HTXTheme.secondaryPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

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
                .foregroundColor(HTXTheme.primaryPurple)
        }
        .padding()
        .subtleHTXCard()
    }
}
