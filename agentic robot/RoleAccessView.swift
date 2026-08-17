import SwiftUI

enum RequiredAppRole: String {
    case admin
    case member

    var title: String {
        switch self {
        case .admin: return "Administrators Only"
        case .member: return "Members Only"
        }
    }

    var message: String {
        switch self {
        case .admin:
            return "This area contains administrative records and account controls."
        case .member:
            return "Report submission is available from a member account."
        }
    }
}

private struct RoleAccessModifier: ViewModifier {
    @EnvironmentObject private var auth: AuthViewModel

    let requiredRole: RequiredAppRole

    @ViewBuilder
    func body(content: Content) -> some View {
        if auth.isLoadingRole {
            ProgressView("Checking account access…")
                .tint(HTXTheme.primaryPurple)
        } else if auth.role == requiredRole.rawValue {
            content
        } else {
            RoleAccessDeniedView(requiredRole: requiredRole)
        }
    }
}

private struct RoleAccessDeniedView: View {
    @Environment(\.dismiss) private var dismiss

    let requiredRole: RequiredAppRole

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(HTXTheme.primaryPurple)

                Text(requiredRole.title)
                    .font(.title2.weight(.bold))

                Text(requiredRole.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Return to Home") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(HTXTheme.primaryPurple)
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 440)
            .subtleHTXCard()
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }
}

extension View {
    func requiresRole(_ role: RequiredAppRole) -> some View {
        modifier(RoleAccessModifier(requiredRole: role))
    }
}
