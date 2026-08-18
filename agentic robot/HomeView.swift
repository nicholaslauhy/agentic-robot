import SwiftUI

struct HomeView: View {

    @EnvironmentObject var auth: AuthViewModel
    @ObservedObject private var notificationService = AdminNotificationService.shared

    @State private var displayedText = ""
    @State private var showSubtitle = false
    @State private var showButtons = false
    @State private var typewriterTask: Task<Void, Never>? = nil
    @State private var navigateToNP299 = false
    @State private var navigateToSecCom = false
    @State private var navigateToFuel = false

    private var fullText: String {
        auth.isAdmin
        ? "What would you like to manage?"
        : "What report would you like to submit?"
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // MARK: - Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.hasUsername ? "Welcome, \(auth.currentUsername)" : "Welcome")
                                .font(.largeTitle.weight(.bold))
                                .foregroundColor(HTXTheme.primaryPurple)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text(auth.isAdmin ? "Administrator" : "Member")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            if auth.isAdmin {
                                NavigationLink {
                                    AdminNotificationsView()
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "bell.fill")
                                            .font(.headline)
                                            .foregroundColor(HTXTheme.primaryPurple)
                                            .frame(width: 38, height: 38)
                                            .background(HTXTheme.primaryPurple.opacity(0.09))
                                            .clipShape(Circle())

                                        if notificationService.unreadCount > 0 {
                                            Text(notificationService.unreadCount > 99 ? "99+" : "\(notificationService.unreadCount)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5)
                                                .frame(minWidth: 18, minHeight: 18)
                                                .background(Color.red)
                                                .clipShape(Capsule())
                                                .offset(x: 4, y: -3)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Notifications, \(notificationService.unreadCount) unread")
                            }

                            Button("Logout") {
                                auth.logout()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    if !auth.hasUsername {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .foregroundColor(.orange)
                            Text(
                                auth.isAdmin
                                ? "Your username has not been set. Add it in Manage Accounts before submitting a form."
                                : "Your username has not been set. Ask an administrator to update your account before submitting a form."
                            )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal)
                    }

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
                    .padding(.vertical, 16)

                    // MARK: - Action Buttons
                    if showButtons && !auth.isLoadingRole {
                        VStack(spacing: 14) {

                        if auth.isAdmin {
                            // Administrator actions
                            NavigationLink {
                                MemberManagementView()
                            } label: {
                                HomeActionRow(
                                    icon: "person.badge.plus.fill",
                                    title: "Manage Accounts",
                                    subtitle: "Create and manage team accounts"
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            NavigationLink {
                                AdminChecklistReviewView()
                            } label: {
                                HomeActionRow(
                                    icon: "checklist.checked",
                                    title: "Pre-driving Follow-up",
                                    subtitle: "Review damage and decide whether NP299 is required"
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            NavigationLink {
                                AdminFuelFollowUpView()
                            } label: {
                                HomeActionRow(
                                    icon: "fuelpump.circle.fill",
                                    title: "Refuel Follow-up",
                                    subtitle: "Review and complete submitted refuel forms"
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            NavigationLink {
                                AdminVehicleManagementView()
                            } label: {
                                HomeActionRow(
                                    icon: "car.2.fill",
                                    title: "Vehicle Management",
                                    subtitle: "Update vehicle status and review vehicle history"
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            NavigationLink {
                                ReportScannerView()
                            } label: {
                                HomeActionRow(
                                    icon: "barcode.viewfinder",
                                    title: "Scan Report Barcode",
                                    subtitle: "Retrieve a report using its barcode"
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            NavigationLink {
                                ReportsListView()
                            } label: {
                                HomeActionRow(
                                    icon: "folder.fill",
                                    title: "View Existing Reports",
                                    subtitle: "Browse and search submitted reports"
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            // Member report forms
                            ForEach(ReportType.allCases) { type in
                                ReportTypeCard(type: type) {
                                    switch type {
                                    case .np299: navigateToNP299 = true
                                    case .secCom: navigateToSecCom = true
                                    case .fuelRefuel: navigateToFuel = true
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 28)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .tint(HTXTheme.primaryPurple)
        .onAppear { startTypewriter() }
        .onChange(of: auth.role) { _, _ in startTypewriter() }
        .onDisappear {
            typewriterTask?.cancel()
            typewriterTask = nil
        }
        .navigationDestination(isPresented: $navigateToNP299) {
            LoggedInView()
        }
        .navigationDestination(isPresented: $navigateToSecCom) {
            SecComPreDrivingChecklistView {
                navigateToSecCom = false
            }
        }
        .navigationDestination(isPresented: $navigateToFuel) {
            FuelRefuelView {
                navigateToFuel = false
            }
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
