//
//  HTXTheme.swift
//  agentic robot
//
//  Created by q2 on 22/5/26.
//

import SwiftUI

// MARK: - HTX Brand Colors & Theme
enum HTXTheme {
    static let gradientTop    = Color(red: 0.18, green: 0.00, blue: 0.38)   // #2D0060
    static let gradientMid    = Color(red: 0.48, green: 0.12, blue: 0.64)   // #7B1FA2
    static let gradientBot    = Color(red: 0.29, green: 0.00, blue: 0.50)   // #4A0080
    static let accent         = Color(red: 0.81, green: 0.58, blue: 0.85)   // #CE93D8
    static let accentBright   = Color(red: 0.88, green: 0.25, blue: 0.98)   // #E040FB
    static let cardBg         = Color.white.opacity(0.10)
    static let cardBorder     = Color.white.opacity(0.18)
    static let inputBg        = Color.white.opacity(0.12)
    static let inputBorder    = Color.white.opacity(0.25)
    static let errorRed       = Color(red: 1, green: 0.42, blue: 0.42)
    static let successGreen   = Color(red: 0.41, green: 0.94, blue: 0.68)
    static let destructiveRed = Color(red: 1, green: 0.27, blue: 0.27)
    static let civBlue        = Color(red: 0.08, green: 0.40, blue: 0.85)
    static let scdfRed        = Color(red: 0.72, green: 0.11, blue: 0.09)
}

// MARK: - Background Gradient
struct HTXBackground: View {
    var body: some View {
        LinearGradient(
            colors: [HTXTheme.gradientTop, HTXTheme.gradientMid, HTXTheme.gradientBot],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Frosted Glass Card
struct HTXCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(24)
            .background(HTXTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(HTXTheme.cardBorder, lineWidth: 1))
    }
}

// MARK: - HTX Text Field
struct HTXTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundColor(HTXTheme.accent)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .padding(14)
                .background(HTXTheme.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HTXTheme.inputBorder, lineWidth: 1))
                .foregroundColor(.white)
                .tint(HTXTheme.accentBright)
        }
    }
}

// MARK: - HTX Secure Field
struct HTXSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundColor(HTXTheme.accent)

            HStack {
                Group {
                    if isVisible {
                        TextField(placeholder, text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .foregroundColor(.white)

                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(HTXTheme.accent)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(HTXTheme.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HTXTheme.inputBorder, lineWidth: 1))
            .tint(HTXTheme.accentBright)
        }
    }
}

// MARK: - Primary Button (purple gradient)
struct HTXPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.isLoading = isLoading; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .fontWeight(.bold)
                        .tracking(1.5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .background(
            LinearGradient(colors: [Color(red: 0.61, green: 0.15, blue: 0.69), HTXTheme.accentBright],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(Capsule())
        .foregroundColor(.white)
        .shadow(color: HTXTheme.accentBright.opacity(0.4), radius: 12, y: 4)
        .disabled(isLoading)
    }
}

// MARK: - Ghost Button
struct HTXGhostButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .foregroundColor(.white)
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Alert Banner
struct HTXAlert: View {
    let message: String
    let isError: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 15))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(isError ? HTXTheme.errorRed : HTXTheme.successGreen)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? HTXTheme.errorRed : HTXTheme.successGreen).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            (isError ? HTXTheme.errorRed : HTXTheme.successGreen).opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Logout Button
struct HTXLogoutButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Logout")
                .font(.subheadline)
                .fontWeight(.bold)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(HTXTheme.destructiveRed.opacity(0.15))
                .foregroundColor(HTXTheme.destructiveRed)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(HTXTheme.destructiveRed.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - HTX Logo View
/// Uses the HTX logo asset from Assets.xcassets (named "HTXLogo").
/// Falls back to an SF Symbol placeholder if the image is missing.
struct HTXLogoView: View {
    var size: CGFloat = 120
    var body: some View {
        Group {
            if let _ = UIImage(named: "htx_logo") {
                Image("htx_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                // Placeholder until the real asset is added
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: size, height: size)
                    Image(systemName: "hexagon.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.6)
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 0.39, green: 0.71, blue: 0.96), HTXTheme.accentBright],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
        }
        .shadow(color: HTXTheme.accentBright.opacity(0.4), radius: 20)
    }
}


// MARK: - Subtle HTX Styling Helpers
// These are meant for the post-login screens: light, readable iOS UI with a small HTX purple accent.
extension HTXTheme {
    static let primaryPurple = Color(red: 0.36, green: 0.10, blue: 0.58)
    static let secondaryPurple = Color(red: 0.52, green: 0.18, blue: 0.72)
    static let softPurpleBackground = Color(red: 0.985, green: 0.970, blue: 1.000)
    static let softPurpleCard = Color(red: 0.995, green: 0.985, blue: 1.000)
    static let softPurpleBorder = Color(red: 0.36, green: 0.10, blue: 0.58).opacity(0.16)
}

struct SubtleHTXBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            LinearGradient(
                colors: [HTXTheme.primaryPurple.opacity(0.16), HTXTheme.softPurpleBackground.opacity(0.55), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct SubtleHTXTitleBar: View {
    let title: String
    let subtitle: String?
    let trailing: AnyView?

    init(title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(HTXTheme.primaryPurple)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
}

struct SubtleHTXCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(HTXTheme.softPurpleCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HTXTheme.softPurpleBorder, lineWidth: 1)
            )
            .shadow(color: HTXTheme.primaryPurple.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

struct SubtleHTXPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? HTXTheme.secondaryPurple : HTXTheme.primaryPurple)
            )
            .foregroundColor(.white)
            .shadow(color: HTXTheme.primaryPurple.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 8, x: 0, y: 4)
    }
}

struct SubtleHTXGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
                .foregroundColor(HTXTheme.primaryPurple)
            configuration.content
        }
        .padding(16)
        .modifier(SubtleHTXCardModifier())
    }
}

extension View {
    func subtleHTXCard() -> some View { modifier(SubtleHTXCardModifier()) }
}
